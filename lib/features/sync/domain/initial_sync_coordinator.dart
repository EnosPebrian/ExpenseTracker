import 'dart:convert';

import 'initial_sync_models.dart';
import 'initial_sync_repository.dart';
import 'initial_sync_transport.dart';
import 'sync_models.dart';

class InitialSyncCoordinator {
  InitialSyncCoordinator({required this.repository, required this.transport});

  final InitialSyncRepository repository;
  final InitialSyncTransport transport;
  Future<InitialSyncResult>? _activeRun;

  Future<InitialSyncManifest> inspectRemote(String bookId) {
    _requireCloud();
    return transport.inspect(bookId);
  }

  Future<InitialSyncResult> upload({
    required String bookId,
    required bool isOwner,
    required bool ownerConfirmed,
    Future<void> Function()? onProgress,
  }) {
    final active = _activeRun;
    if (active != null) return active;
    final run = _upload(
      bookId: bookId,
      isOwner: isOwner,
      ownerConfirmed: ownerConfirmed,
      onProgress: onProgress,
    );
    _activeRun = run;
    return run.whenComplete(() => _activeRun = null);
  }

  Future<InitialSyncResult> download({
    required String bookId,
    required String? authUserId,
    Future<void> Function()? onProgress,
  }) {
    final active = _activeRun;
    if (active != null) return active;
    final run = _download(
      bookId: bookId,
      authUserId: authUserId,
      onProgress: onProgress,
    );
    _activeRun = run;
    return run.whenComplete(() => _activeRun = null);
  }

  Future<void> prepareSecondary(String bookId) =>
      repository.prepareSecondary(bookId);

  Future<void> cancel(String bookId) async {
    final cursor = await repository.getCursor(bookId);
    final direction = cursor?.initializationDirection == 'download'
        ? InitialSyncDirection.download
        : InitialSyncDirection.upload;
    final sessionId = cursor?.initializationSessionId;
    if (sessionId != null &&
        transport.isConfigured &&
        transport.isAuthenticated) {
      await transport.cancel(sessionId);
    }
    await repository.cancelInitialization(bookId, direction);
  }

  Future<InitialSyncResult> _upload({
    required String bookId,
    required bool isOwner,
    required bool ownerConfirmed,
    Future<void> Function()? onProgress,
  }) async {
    try {
      _requireCloud();
      if (!isOwner) {
        throw const InitialSyncException(
          InitialSyncErrorCode.notOwner,
          'Only an active household owner can upload the initial history.',
        );
      }
      if (!ownerConfirmed) {
        throw const InitialSyncException(
          InitialSyncErrorCode.validation,
          'Confirm that this device contains the primary household records.',
        );
      }
      if (await repository.unresolvedConflictCount(bookId) > 0) {
        throw const InitialSyncException(
          InitialSyncErrorCode.conflict,
          'Resolve existing synchronization conflicts before initial upload.',
        );
      }
      var cursor = await repository.getCursor(bookId);
      if (!_canResume(cursor, InitialSyncDirection.upload) &&
          cursor?.initializationState !=
              SyncInitializationState.primaryUploadRequired) {
        throw const InitialSyncException(
          InitialSyncErrorCode.validation,
          'This household is not waiting for a primary upload.',
        );
      }
      InitialSyncManifest manifest;
      if (cursor?.initializationState ==
          SyncInitializationState.primaryUploadRequired) {
        final remote = await transport.inspect(bookId);
        if (remote.remoteInitializationComplete ||
            remote.remoteRecordCount > 0) {
          throw const InitialSyncException(
            InitialSyncErrorCode.remoteOccupied,
            'The remote household already contains financial records. Download it instead.',
          );
        }
        manifest = await repository.captureUploadSnapshot(bookId);
        if (manifest.totalCount <= 1) {
          throw const InitialSyncException(
            InitialSyncErrorCode.validation,
            'No household records were found for the initial upload.',
          );
        }
        cursor = await repository.getCursor(bookId);
      } else {
        manifest = _manifestFrom(cursor);
      }
      var sessionId = cursor?.initializationSessionId;
      if (sessionId == null) {
        final session = await transport.beginUpload(manifest);
        sessionId = session.id;
        await repository.startInitialization(
          bookId: bookId,
          direction: InitialSyncDirection.upload,
          sessionId: sessionId,
          manifest: manifest,
        );
      }
      for (final entityType in initialSyncEntityOrder) {
        while (true) {
          final rows = await repository.readUploadRows(
            bookId,
            entityType,
            limit: 100,
          );
          if (rows.isEmpty) break;
          await transport.uploadBatch(
            sessionId: sessionId,
            entityType: entityType,
            rows: rows,
          );
          await repository.markUploadRowsTransferred(
            bookId,
            entityType,
            rows.map((row) => row['id'] as String),
          );
          await onProgress?.call();
        }
      }
      final finalSequence = await transport.completeUpload(sessionId);
      await repository.completeUpload(bookId, finalSequence);
      return InitialSyncResult(
        success: true,
        message: 'Initial household upload completed.',
        manifest: manifest,
        finalSequence: finalSequence,
      );
    } on InitialSyncException catch (error) {
      await _recordFailureIfStarted(bookId, error);
      return InitialSyncResult(success: false, message: error.safeMessage);
    } catch (_) {
      const error = InitialSyncException(
        InitialSyncErrorCode.unavailable,
        'Initial upload stopped safely and can be resumed.',
      );
      await _recordFailureIfStarted(bookId, error);
      return const InitialSyncResult(
        success: false,
        message: 'Initial upload stopped safely and can be resumed.',
      );
    }
  }

  Future<InitialSyncResult> _download({
    required String bookId,
    required String? authUserId,
    Future<void> Function()? onProgress,
  }) async {
    try {
      _requireCloud();
      if (await repository.targetHasFinancialData(bookId)) {
        throw const InitialSyncException(
          InitialSyncErrorCode.localTargetPopulated,
          'Initial download cannot merge independent local financial history.',
        );
      }
      var cursor = await repository.getCursor(bookId);
      if (cursor == null) {
        await repository.prepareSecondary(bookId);
        cursor = await repository.getCursor(bookId);
      }
      if (!_canResume(cursor, InitialSyncDirection.download) &&
          cursor?.initializationState !=
              SyncInitializationState.secondaryDownloadRequired) {
        throw const InitialSyncException(
          InitialSyncErrorCode.validation,
          'This household is not waiting for an initial download.',
        );
      }
      String? sessionId = cursor?.initializationSessionId;
      InitialSyncManifest manifest;
      if (sessionId == null) {
        final session = await transport.beginDownload(bookId);
        sessionId = session.id;
        manifest = session.manifest;
        if (!manifest.remoteInitializationComplete) {
          throw const InitialSyncException(
            InitialSyncErrorCode.remoteIncomplete,
            'The primary household upload has not completed yet.',
          );
        }
        await repository.startInitialization(
          bookId: bookId,
          direction: InitialSyncDirection.download,
          sessionId: sessionId,
          manifest: manifest,
        );
        cursor = await repository.getCursor(bookId);
      } else {
        manifest = _manifestFrom(cursor);
      }
      final resumeEntity = cursor?.lastProcessedEntity;
      for (final entityType in initialSyncEntityOrder) {
        if (resumeEntity != null &&
            initialSyncEntityOrder.indexOf(entityType) <
                initialSyncEntityOrder.indexOf(resumeEntity)) {
          continue;
        }
        var after = entityType == resumeEntity
            ? cursor?.lastProcessedCursor
            : null;
        while (true) {
          final batch = await transport.downloadBatch(
            sessionId: sessionId,
            entityType: entityType,
            afterEntityId: after,
            limit: 100,
          );
          await repository.stageDownloadBatch(bookId, batch);
          await onProgress?.call();
          after = batch.nextCursor;
          if (batch.complete) break;
        }
      }
      await repository.activateDownload(
        bookId: bookId,
        manifest: manifest,
        authUserId: authUserId,
      );
      return InitialSyncResult(
        success: true,
        message: 'Shared household downloaded and activated.',
        manifest: manifest,
        finalSequence: manifest.snapshotSequence,
      );
    } on InitialSyncException catch (error) {
      await _recordFailureIfStarted(bookId, error);
      return InitialSyncResult(success: false, message: error.safeMessage);
    } catch (_) {
      const error = InitialSyncException(
        InitialSyncErrorCode.unavailable,
        'Initial download stopped safely and can be resumed.',
      );
      await _recordFailureIfStarted(bookId, error);
      return const InitialSyncResult(
        success: false,
        message: 'Initial download stopped safely and can be resumed.',
      );
    }
  }

  void _requireCloud() {
    if (!transport.isConfigured) {
      throw const InitialSyncException(
        InitialSyncErrorCode.notConfigured,
        'Cloud sharing is not configured.',
      );
    }
    if (!transport.isAuthenticated) {
      throw const InitialSyncException(
        InitialSyncErrorCode.signedOut,
        'Sign in is required before initial synchronization.',
      );
    }
  }

  Future<void> _recordFailureIfStarted(
    String bookId,
    InitialSyncException error,
  ) async {
    final cursor = await repository.getCursor(bookId);
    if (cursor?.initializationState == SyncInitializationState.uploading ||
        cursor?.initializationState == SyncInitializationState.downloading ||
        cursor?.initializationState == SyncInitializationState.failed) {
      await repository.recordFailure(
        bookId,
        code: error.code.name,
        message: error.safeMessage,
      );
    }
  }

  static bool _canResume(SyncCursor? cursor, InitialSyncDirection direction) =>
      (cursor?.initializationState == SyncInitializationState.uploading &&
          direction == InitialSyncDirection.upload) ||
      (cursor?.initializationState == SyncInitializationState.downloading &&
          direction == InitialSyncDirection.download) ||
      (cursor?.initializationState == SyncInitializationState.failed &&
          cursor?.initializationDirection == direction.name);

  static InitialSyncManifest _manifestFrom(SyncCursor? cursor) {
    final value = cursor?.manifest;
    if (value == null) {
      throw const InitialSyncException(
        InitialSyncErrorCode.validation,
        'Initial synchronization manifest is missing.',
      );
    }
    return InitialSyncManifest.fromJson(
      (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>(),
    );
  }
}
