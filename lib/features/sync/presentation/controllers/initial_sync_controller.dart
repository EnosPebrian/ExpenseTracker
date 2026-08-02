import 'package:flutter/foundation.dart';

import '../../../master_data/domain/entities/financial_book.dart';
import '../../domain/initial_sync_coordinator.dart';
import '../../domain/initial_sync_models.dart';
import '../../domain/sync_models.dart';

class InitialSyncController extends ChangeNotifier {
  InitialSyncController({required this.coordinator, this.onReady});

  final InitialSyncCoordinator coordinator;
  final Future<void> Function(String bookId, InitialSyncDirection direction)?
  onReady;

  FinancialBook? primaryBook;
  bool primaryIsOwner = false;
  String? secondaryBookId;
  String? secondaryRole;
  String? secondaryMemberId;
  String? authUserId;
  InitialSyncManifest? primaryRemoteManifest;
  InitialSyncManifest? secondaryRemoteManifest;
  SyncCursor? primaryCursor;
  SyncCursor? secondaryCursor;
  InitialSyncResult? lastResult;
  String? error;
  bool busy = false;

  bool get canUpload =>
      primaryBook?.remoteLinkedAt != null &&
      primaryIsOwner &&
      (primaryCursor?.initializationState ==
              SyncInitializationState.primaryUploadRequired ||
          _resumable(primaryCursor, InitialSyncDirection.upload));

  bool get canDownload =>
      secondaryBookId != null &&
      secondaryRemoteManifest?.remoteInitializationComplete == true &&
      (secondaryCursor == null ||
          secondaryCursor?.initializationState ==
              SyncInitializationState.secondaryDownloadRequired ||
          _resumable(secondaryCursor, InitialSyncDirection.download));

  int get uploadedCount => primaryCursor?.uploadedCount ?? 0;
  int get downloadedCount =>
      secondaryCursor?.initializationState == SyncInitializationState.ready
      ? secondaryCursor?.downloadedCount ?? 0
      : 0;
  int get fetchedCount => secondaryCursor?.initialSyncDiagnostic?.decoded ?? 0;

  Future<void> setContext({
    required FinancialBook? primaryBook,
    required bool primaryIsOwner,
    String? secondaryBookId,
    String? secondaryRole,
    String? secondaryMemberId,
    String? authUserId,
  }) async {
    this.primaryBook = primaryBook;
    this.primaryIsOwner = primaryIsOwner;
    this.secondaryBookId = secondaryBookId;
    this.secondaryRole = secondaryRole;
    this.secondaryMemberId = secondaryMemberId;
    this.authUserId = authUserId;
    await refresh();
  }

  Future<void> refresh() async {
    final primaryId = primaryBook?.id;
    if (primaryId != null) {
      primaryCursor = await coordinator.repository.getCursor(primaryId);
      primaryRemoteManifest = await _inspectSafely(primaryId);
    }
    final secondaryId = secondaryBookId;
    if (secondaryId != null) {
      secondaryCursor = await coordinator.repository.getCursor(secondaryId);
      secondaryRemoteManifest = await _inspectSafely(secondaryId);
    }
    notifyListeners();
  }

  Future<void> upload({required bool confirmed}) async {
    final book = primaryBook;
    if (book == null || busy) return;
    await _run(
      book.id,
      InitialSyncDirection.upload,
      () => coordinator.upload(
        bookId: book.id,
        isOwner: primaryIsOwner,
        ownerConfirmed: confirmed,
        onProgress: _refreshProgress,
      ),
    );
  }

  Future<void> download() async {
    final bookId = secondaryBookId;
    if (bookId == null || busy) return;
    await coordinator.prepareSecondary(bookId);
    await _run(
      bookId,
      InitialSyncDirection.download,
      () => coordinator.download(
        bookId: bookId,
        authUserId: authUserId,
        onProgress: _refreshProgress,
      ),
    );
  }

  Future<void> cancel(String bookId) async {
    if (busy) return;
    await coordinator.cancel(bookId);
    lastResult = null;
    error = null;
    await refresh();
  }

  Future<void> _run(
    String bookId,
    InitialSyncDirection direction,
    Future<InitialSyncResult> Function() operation,
  ) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      lastResult = await operation();
      if (lastResult!.success) {
        await onReady?.call(bookId, direction);
      } else {
        error = lastResult!.message;
      }
    } finally {
      busy = false;
      await refresh();
    }
  }

  Future<void> _refreshProgress() async {
    final primaryId = primaryBook?.id;
    final secondaryId = secondaryBookId;
    if (primaryId != null) {
      primaryCursor = await coordinator.repository.getCursor(primaryId);
    }
    if (secondaryId != null) {
      secondaryCursor = await coordinator.repository.getCursor(secondaryId);
    }
    notifyListeners();
  }

  Future<InitialSyncManifest?> _inspectSafely(String bookId) async {
    try {
      return await coordinator.inspectRemote(bookId);
    } catch (_) {
      return null;
    }
  }

  static bool _resumable(SyncCursor? cursor, InitialSyncDirection direction) =>
      cursor?.initializationDirection == direction.name &&
      (cursor?.initializationState == SyncInitializationState.uploading ||
          cursor?.initializationState == SyncInitializationState.downloading ||
          cursor?.initializationState == SyncInitializationState.failed);
}
