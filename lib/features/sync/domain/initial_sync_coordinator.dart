import 'dart:convert';

import 'package:flutter/foundation.dart';

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
    bool replaceExisting = false,
    Future<void> Function()? onProgress,
  }) {
    final active = _activeRun;
    if (active != null) return active;
    final run = _download(
      bookId: bookId,
      authUserId: authUserId,
      replaceExisting: replaceExisting,
      onProgress: onProgress,
    );
    _activeRun = run;
    return run.whenComplete(() => _activeRun = null);
  }

  Future<void> prepareSecondary(String bookId) =>
      repository.prepareSecondary(bookId);

  Future<void> prepareReconnect(String bookId) async {
    await repository.cancelInitialization(
      bookId,
      InitialSyncDirection.download,
    );
    await repository.prepareSecondary(bookId);
  }

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
      await _logDiagnostic(bookId, error);
      return InitialSyncResult(
        success: false,
        message: error.safeMessage,
        diagnosticMessage: error.diagnosticMessage,
      );
    } catch (caught) {
      final error = InitialSyncException(
        InitialSyncErrorCode.unavailable,
        'Initial upload stopped safely and can be resumed.',
        phase: 'upload',
        exceptionClass: caught.runtimeType.toString(),
      );
      await _recordFailureIfStarted(bookId, error);
      await _logDiagnostic(bookId, error);
      return InitialSyncResult(
        success: false,
        message: 'Initial upload stopped safely and can be resumed.',
        diagnosticMessage: error.diagnosticMessage,
      );
    }
  }

  Future<InitialSyncResult> _download({
    required String bookId,
    required String? authUserId,
    required bool replaceExisting,
    Future<void> Function()? onProgress,
  }) async {
    String? activeEntity;
    String? lastCommittedCursor;
    try {
      _requireCloud();
      if (!replaceExisting && await repository.targetHasFinancialData(bookId)) {
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
        activeEntity = entityType;
        if (resumeEntity != null &&
            initialSyncEntityOrder.indexOf(entityType) <
                initialSyncEntityOrder.indexOf(resumeEntity)) {
          continue;
        }
        var after = entityType == resumeEntity
            ? cursor?.lastProcessedCursor
            : null;
        while (true) {
          InitialSyncBatch batch;
          try {
            batch = await transport.downloadBatch(
              sessionId: sessionId,
              entityType: entityType,
              afterEntityId: after,
              limit: 100,
            );
          } on InitialSyncException catch (error) {
            throw InitialSyncException(
              error.code,
              error.safeMessage,
              entityType: error.entityType ?? entityType,
              recordId: error.recordId,
              phase: error.phase ?? 'fetch/decode',
              exceptionClass: error.exceptionClass,
              lastCommittedCursor: after,
              committedRecords: cursor?.downloadedCount ?? 0,
            );
          }
          await repository.stageDownloadBatch(bookId, batch);
          await onProgress?.call();
          after = batch.nextCursor;
          lastCommittedCursor = after;
          if (batch.complete) break;
        }
      }
      final alreadyMatched = await repository.activateDownload(
        bookId: bookId,
        manifest: manifest,
        authUserId: authUserId,
        replaceExisting: replaceExisting,
      );
      await _logSuccessDiagnostic(bookId);
      return InitialSyncResult(
        success: true,
        message: alreadyMatched
            ? 'Local data already matched the hosted household. Cloud sharing was reattached.'
            : 'Shared household downloaded and activated.',
        manifest: manifest,
        finalSequence: manifest.snapshotSequence,
      );
    } on InitialSyncException catch (error) {
      final detailed = await _withCommittedState(bookId, error);
      await _recordFailureIfStarted(bookId, detailed);
      await _logDiagnostic(bookId, detailed);
      return InitialSyncResult(
        success: false,
        message: detailed.safeMessage,
        diagnosticMessage: detailed.diagnosticMessage,
      );
    } catch (caught) {
      final error = await _withCommittedState(
        bookId,
        InitialSyncException(
          InitialSyncErrorCode.unavailable,
          'Initial download stopped safely and can be resumed.',
          entityType: activeEntity,
          phase: 'download',
          exceptionClass: caught.runtimeType.toString(),
          lastCommittedCursor: lastCommittedCursor,
        ),
      );
      await _recordFailureIfStarted(bookId, error);
      await _logDiagnostic(bookId, error);
      return InitialSyncResult(
        success: false,
        message: 'Initial download stopped safely and can be resumed.',
        diagnosticMessage: error.diagnosticMessage,
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
      await repository.recordFailure(bookId, error: error);
    }
  }

  Future<InitialSyncException> _withCommittedState(
    String bookId,
    InitialSyncException error,
  ) async {
    final cursor = await repository.getCursor(bookId);
    return InitialSyncException(
      error.code,
      error.safeMessage,
      entityType: error.entityType,
      recordId: error.recordId,
      phase: error.phase,
      exceptionClass: error.exceptionClass,
      lastCommittedCursor:
          error.lastCommittedCursor ?? cursor?.lastProcessedCursor,
      committedRecords: error.committedRecords ?? cursor?.downloadedCount ?? 0,
    );
  }

  Future<void> _logDiagnostic(String bookId, InitialSyncException error) async {
    if (!kDebugMode) return;
    final summary = await repository.getDiagnosticSummary(bookId);
    debugPrint('${error.diagnosticMessage} counts=${summary.toJson()}');
  }

  Future<void> _logSuccessDiagnostic(String bookId) async {
    if (!kDebugMode) return;
    final summary = await repository.getDiagnosticSummary(bookId);
    debugPrint('Initial sync complete counts=${summary.toJson()}');
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
