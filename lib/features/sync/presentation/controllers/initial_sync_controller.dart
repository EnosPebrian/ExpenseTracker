import 'package:flutter/foundation.dart';

import '../../../master_data/domain/entities/financial_book.dart';
import '../../domain/cloud_sync_state_classifier.dart';
import '../../domain/initial_sync_coordinator.dart';
import '../../domain/initial_sync_models.dart';
import '../../domain/sync_models.dart';

class InitialSyncController extends ChangeNotifier {
  InitialSyncController({
    required this.coordinator,
    this.onReady,
    this._classifier = const CloudSyncStateClassifier(),
  });

  final InitialSyncCoordinator coordinator;
  final Future<void> Function(String bookId, InitialSyncDirection direction)?
  onReady;
  final CloudSyncStateClassifier _classifier;

  FinancialBook? primaryBook;
  bool primaryIsOwner = false;
  String? secondaryBookId;
  String? secondaryRole;
  String? secondaryMemberId;
  String? authUserId;
  List<String> hostedBookIds = const [];
  Map<String, String> hostedRoles = const {};
  Map<String, String?> hostedMemberIds = const {};
  final Map<String, InitialSyncManifest> hostedManifests = {};
  final Set<String> failedManifestBookIds = {};
  InitialSyncManifest? primaryRemoteManifest;
  InitialSyncManifest? secondaryRemoteManifest;
  SyncCursor? primaryCursor;
  SyncCursor? secondaryCursor;
  InitialSyncResult? lastResult;
  String? error;
  bool busy = false;
  bool cloudConfigured = true;
  bool remoteStateLoaded = false;
  String? remoteStateError;
  int _refreshGeneration = 0;
  CloudSyncDecision decision = const CloudSyncDecision(
    CloudSyncClassification.remoteStateChecking,
    reason: 'controller-created',
  );

  Map<String, InitialSyncManifest> get reconnectManifests => {
    for (final entry in hostedManifests.entries)
      if (entry.value.remoteInitializationComplete) entry.key: entry.value,
  };

  Map<String, InitialSyncManifest> get additionalDownloadManifests => {
    for (final entry in hostedManifests.entries)
      if (entry.key != primaryBook?.id &&
          entry.value.remoteInitializationComplete)
        entry.key: entry.value,
  };

  bool get canUpload =>
      decision.classification ==
          CloudSyncClassification.genuinePrimaryUploadRequired &&
      primaryBook?.remoteLinkedAt != null &&
      primaryIsOwner &&
      (primaryCursor?.initializationState ==
              SyncInitializationState.primaryUploadRequired ||
          _resumable(primaryCursor, InitialSyncDirection.upload));

  bool get canDownload =>
      decision.classification ==
          CloudSyncClassification.downloadAdditionalHostedHousehold &&
      secondaryBookId != null &&
      secondaryRemoteManifest?.remoteInitializationComplete == true &&
      (secondaryCursor == null ||
          secondaryCursor?.initializationState ==
              SyncInitializationState.secondaryDownloadRequired ||
          _resumable(secondaryCursor, InitialSyncDirection.download));

  bool get canReconnect => decision.isReconnect;

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
    List<String> hostedBookIds = const [],
    Map<String, String> hostedRoles = const {},
    Map<String, String?> hostedMemberIds = const {},
    bool cloudConfigured = true,
    bool remoteStateLoaded = true,
    String? remoteStateError,
  }) async {
    this.primaryBook = primaryBook;
    this.primaryIsOwner = primaryIsOwner;
    this.secondaryBookId = secondaryBookId;
    this.secondaryRole = secondaryRole;
    this.secondaryMemberId = secondaryMemberId;
    this.authUserId = authUserId;
    this.hostedBookIds = List.unmodifiable(hostedBookIds);
    this.hostedRoles = Map.unmodifiable(hostedRoles);
    this.hostedMemberIds = Map.unmodifiable(hostedMemberIds);
    this.cloudConfigured = cloudConfigured;
    this.remoteStateLoaded = remoteStateLoaded;
    this.remoteStateError = remoteStateError;
    await refresh();
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    hostedManifests.clear();
    failedManifestBookIds.clear();
    decision = _classify();
    notifyListeners();
    if (!cloudConfigured ||
        !remoteStateLoaded ||
        authUserId == null ||
        remoteStateError != null ||
        hostedBookIds.isEmpty) {
      _debugDecision();
      return;
    }
    for (final bookId in hostedBookIds) {
      final manifest = await _inspectSafely(bookId);
      if (generation != _refreshGeneration) return;
      if (manifest != null) {
        hostedManifests[bookId] = manifest;
      } else {
        failedManifestBookIds.add(bookId);
      }
    }
    final primaryId = primaryBook?.id;
    if (primaryId != null) {
      primaryCursor = await coordinator.repository.getCursor(primaryId);
      if (generation != _refreshGeneration) return;
      primaryRemoteManifest = hostedManifests[primaryId];
    }
    final availableAdditional = additionalDownloadManifests.keys.toList();
    if (secondaryBookId == primaryId ||
        !availableAdditional.contains(secondaryBookId)) {
      secondaryBookId = availableAdditional.isEmpty
          ? null
          : availableAdditional.first;
    }
    final secondaryId = secondaryBookId;
    if (secondaryId != null) {
      secondaryRole =
          hostedRoles[secondaryId] ?? hostedManifests[secondaryId]?.memberRole;
      secondaryMemberId =
          hostedMemberIds[secondaryId] ??
          hostedManifests[secondaryId]?.householdMemberId;
      secondaryCursor = await coordinator.repository.getCursor(secondaryId);
      if (generation != _refreshGeneration) return;
      secondaryRemoteManifest = hostedManifests[secondaryId];
    }
    decision = _classify();
    _debugDecision();
    notifyListeners();
  }

  Future<void> selectSecondaryBook(String bookId) async {
    if (busy || !additionalDownloadManifests.containsKey(bookId)) return;
    secondaryBookId = bookId;
    secondaryRole = hostedRoles[bookId] ?? hostedManifests[bookId]?.memberRole;
    secondaryMemberId =
        hostedMemberIds[bookId] ?? hostedManifests[bookId]?.householdMemberId;
    secondaryRemoteManifest = hostedManifests[bookId];
    secondaryCursor = await coordinator.repository.getCursor(bookId);
    decision = _classify();
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

  Future<void> reconnect(String bookId) async {
    if (busy || !canReconnect || !reconnectManifests.containsKey(bookId)) {
      return;
    }
    final replaceExisting = primaryBook?.id == bookId;
    await coordinator.prepareReconnect(bookId);
    await _run(
      bookId,
      InitialSyncDirection.download,
      () => coordinator.download(
        bookId: bookId,
        authUserId: authUserId,
        replaceExisting: replaceExisting,
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

  CloudSyncDecision _classify() => _classifier.classify(
    cloudConfigured: cloudConfigured,
    remoteStateLoaded: remoteStateLoaded,
    authenticated: authUserId != null,
    localBook: primaryBook,
    matchingMembershipIsOwner: primaryIsOwner,
    hostedBookIds: hostedBookIds,
    remoteManifests: hostedManifests,
    failedManifestBookIds: failedManifestBookIds,
    localCursor: primaryCursor,
    preferredAdditionalBookId: secondaryBookId,
    remoteStateError: remoteStateError,
  );

  void _debugDecision() {
    if (!kDebugMode) return;
    final localBook = primaryBook;
    final manifest = localBook == null ? null : hostedManifests[localBook.id];
    debugPrint(
      'cloud-state: localBook=${localBook == null ? 'missing' : 'present'} '
      'auth=${authUserId == null ? 'no' : 'yes'} '
      'membership=${hostedBookIds.isEmpty ? 'missing' : 'active'} '
      'remoteInitialized=${manifest == null
          ? 'unknown'
          : manifest.remoteInitializationComplete
          ? 'yes'
          : 'no'} '
      'sameBook=${localBook != null && hostedBookIds.contains(localBook.id) ? 'yes' : 'no'} '
      'initialReady=${primaryCursor?.initializationState == SyncInitializationState.ready ? 'yes' : 'no'} '
      'cursor=${primaryCursor == null ? 'missing' : 'present'} '
      'classification=${decision.classification.name} '
      'reason=${decision.reason}',
    );
  }

  static bool _resumable(SyncCursor? cursor, InitialSyncDirection direction) =>
      cursor?.initializationDirection == direction.name &&
      (cursor?.initializationState == SyncInitializationState.uploading ||
          cursor?.initializationState == SyncInitializationState.downloading ||
          cursor?.initializationState == SyncInitializationState.failed);
}
