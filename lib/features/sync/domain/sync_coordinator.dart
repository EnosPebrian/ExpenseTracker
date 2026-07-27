import '../../master_data/domain/entities/financial_book.dart';
import 'sync_models.dart';
import 'sync_repository.dart';
import 'sync_transport.dart';

class SyncCoordinator {
  SyncCoordinator({
    required this.repository,
    required this.transport,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SyncRepository repository;
  final SyncTransport transport;
  final DateTime Function() _now;
  Future<SyncRunResult>? _activeRun;

  Future<SyncRunResult> synchronize(FinancialBook? book) {
    final active = _activeRun;
    if (active != null) return active;
    final run = _synchronize(book);
    _activeRun = run;
    return run.whenComplete(() => _activeRun = null);
  }

  Future<SyncRunResult> inspect(FinancialBook? book) async {
    if (book == null || book.remoteLinkedAt == null) {
      return const SyncRunResult(status: SyncStatus.localOnly);
    }
    if (!transport.isConfigured) {
      return const SyncRunResult(status: SyncStatus.notConfigured);
    }
    if (!transport.isAuthenticated) {
      return const SyncRunResult(status: SyncStatus.signedOut);
    }
    final cursor = await repository.getCursor(book.id);
    final guarded = _guardStatus(cursor?.initializationState);
    if (guarded != null) return SyncRunResult(status: guarded);
    final conflicts = await repository.unresolvedConflictCount(book.id);
    if (conflicts > 0) {
      return const SyncRunResult(status: SyncStatus.conflict);
    }
    final pending = await repository.pendingCount(book.id);
    return SyncRunResult(
      status: pending == 0 ? SyncStatus.synced : SyncStatus.pending,
      pendingCount: pending,
    );
  }

  Future<SyncRunResult> _synchronize(FinancialBook? book) async {
    final readiness = await inspect(book);
    if (readiness.status != SyncStatus.synced &&
        readiness.status != SyncStatus.pending) {
      return readiness;
    }
    final bookId = book!.id;
    await repository.recoverInterrupted(bookId);
    var pushed = 0;
    var pulled = 0;
    try {
      final operations = await repository.getEligibleOperations(bookId);
      if (operations.isNotEmpty) {
        await repository.markSending(
          operations.map((item) => item.operationId),
        );
        final results = await transport.push(bookId, operations);
        final operationsById = {
          for (final operation in operations) operation.operationId: operation,
        };
        final returnedIds = <String>{};
        for (final result in results) {
          returnedIds.add(result.operationId);
          final operation = operationsById[result.operationId];
          if (operation == null) continue;
          switch (result.status) {
            case PushResultStatus.applied:
            case PushResultStatus.alreadyApplied:
              await repository.markCompleted(
                operation.operationId,
                result.serverVersion,
              );
              pushed++;
            case PushResultStatus.versionConflict:
              await repository.recordConflict(operation, result);
            case PushResultStatus.unauthorized:
            case PushResultStatus.validationError:
              await repository.scheduleRetry(
                operation.operationId,
                errorCode: result.errorCode ?? result.status.name,
                safeMessage: result.status == PushResultStatus.unauthorized
                    ? 'Synchronization permission was denied.'
                    : 'A local change needs attention before it can sync.',
                nextAttemptAt: _retryAt(operation.attemptCount, terminal: true),
              );
          }
        }
        for (final operation in operations) {
          if (!returnedIds.contains(operation.operationId)) {
            await _retry(operation, 'incomplete_response');
          }
        }
      }

      var cursor = await repository.getCursor(bookId);
      while (true) {
        final batch = await transport.pull(
          bookId,
          afterSequence: cursor?.lastServerSequence ?? 0,
        );
        if (batch.changes.isEmpty) break;
        await repository.applyRemoteBatch(bookId, batch);
        pulled += batch.changes.length;
        cursor = await repository.getCursor(bookId);
        if (batch.changes.length < 100) break;
      }
      final conflicts = await repository.unresolvedConflictCount(bookId);
      final pending = await repository.pendingCount(bookId);
      return SyncRunResult(
        status: conflicts > 0
            ? SyncStatus.conflict
            : pending > 0
            ? SyncStatus.retryScheduled
            : SyncStatus.synced,
        pendingCount: pending,
        pushedCount: pushed,
        pulledCount: pulled,
      );
    } on SyncTransportException catch (error) {
      await repository.recoverInterrupted(bookId);
      final retryable = await repository.getEligibleOperations(
        bookId,
        limit: 50,
      );
      if (error.kind == SyncTransportErrorKind.network) {
        for (final operation in retryable) {
          await _retry(operation, error.kind.name);
        }
      } else if (error.kind == SyncTransportErrorKind.authorization ||
          error.kind == SyncTransportErrorKind.validation) {
        for (final operation in retryable) {
          await repository.scheduleRetry(
            operation.operationId,
            errorCode: error.kind == SyncTransportErrorKind.authorization
                ? 'unauthorized'
                : 'validation',
            safeMessage: error.safeMessage,
            nextAttemptAt: _retryAt(operation.attemptCount, terminal: true),
          );
        }
      }
      return SyncRunResult(
        status: switch (error.kind) {
          SyncTransportErrorKind.authentication => SyncStatus.signedOut,
          SyncTransportErrorKind.network => SyncStatus.offline,
          SyncTransportErrorKind.authorization ||
          SyncTransportErrorKind.validation => SyncStatus.error,
        },
        pendingCount: await repository.pendingCount(bookId),
        message: error.safeMessage,
      );
    } catch (_) {
      await repository.recoverInterrupted(bookId);
      return SyncRunResult(
        status: SyncStatus.error,
        pendingCount: await repository.pendingCount(bookId),
        message: 'Synchronization failed. Local finance remains usable.',
      );
    }
  }

  Future<void> _retry(SyncOperation operation, String code) =>
      repository.scheduleRetry(
        operation.operationId,
        errorCode: code,
        safeMessage: 'Synchronization will retry later.',
        nextAttemptAt: _retryAt(operation.attemptCount),
      );

  DateTime _retryAt(int attempts, {bool terminal = false}) {
    if (terminal) return _now().add(const Duration(days: 3650));
    final seconds = (5 * (1 << attempts.clamp(0, 8))).clamp(5, 900);
    return _now().add(Duration(seconds: seconds));
  }

  static SyncStatus? _guardStatus(SyncInitializationState? state) =>
      switch (state ?? SyncInitializationState.notInitialized) {
        SyncInitializationState.notInitialized ||
        SyncInitializationState.primaryUploadRequired =>
          SyncStatus.primaryUploadRequired,
        SyncInitializationState.secondaryDownloadRequired =>
          SyncStatus.secondaryDownloadRequired,
        SyncInitializationState.uploading ||
        SyncInitializationState.downloading => SyncStatus.initializing,
        SyncInitializationState.failed => SyncStatus.initializationFailed,
        SyncInitializationState.ready => null,
      };
}
