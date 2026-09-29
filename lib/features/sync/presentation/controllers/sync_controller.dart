import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../master_data/domain/entities/financial_book.dart';
import '../../domain/sync_coordinator.dart';
import '../../domain/sync_models.dart';
import '../../domain/sync_transport.dart';
import '../../domain/sync_repository.dart';

class SyncController extends ChangeNotifier {
  SyncController(this.coordinator, {this.onRemoteDataApplied});

  final SyncCoordinator coordinator;
  final Future<void> Function()? onRemoteDataApplied;
  FinancialBook? _book;
  SyncRunResult result = const SyncRunResult(status: SyncStatus.localOnly);
  bool busy = false;
  Timer? _debounce;
  bool _rerunRequested = false;
  bool realtimeConnected = false;
  DateTime? lastSuccessfulSyncAt;
  int failedCount = 0;
  int conflictCount = 0;
  int? remoteCursor;
  Map<String, String> transactionStates = const {};
  DateTime? get lastSuccessfulPushAt => coordinator.lastSuccessfulPushAt;
  DateTime? get lastSuccessfulPullAt => coordinator.lastSuccessfulPullAt;

  Future<void> _diagnostics() async {
    final book = _book;
    if (book == null) {
      transactionStates = const {};
      return;
    }
    conflictCount = await coordinator.repository.unresolvedConflictCount(
      book.id,
    );
    remoteCursor = (await coordinator.repository.getCursor(
      book.id,
    ))?.lastServerSequence;
    final repository = coordinator.repository;
    transactionStates = repository is SyncEntityDiagnosticsRepository
        ? await (repository as SyncEntityDiagnosticsRepository)
              .transactionSyncStates(book.id)
        : const {};
    if (repository is SyncDiagnosticsRepository) {
      final counts = await (repository as SyncDiagnosticsRepository)
          .outboxStatusCounts(book.id);
      failedCount =
          (counts['retry'] ?? 0) +
          ((counts['conflict'] ?? 0) - conflictCount).clamp(0, 1 << 30);
    }
  }

  SyncStatus get status => result.status;
  int get pendingCount => result.pendingCount;

  bool get canSync =>
      _book?.remoteLinkedAt != null &&
      switch (status) {
        SyncStatus.primaryUploadRequired ||
        SyncStatus.secondaryDownloadRequired ||
        SyncStatus.initializing ||
        SyncStatus.initializationFailed ||
        SyncStatus.notConfigured ||
        SyncStatus.signedOut ||
        SyncStatus.localOnly => false,
        _ => true,
      };

  Future<void> setBook(FinancialBook? book, {bool runWhenReady = true}) async {
    final wakeup = coordinator.transport is SyncWakeupTransport
        ? coordinator.transport as SyncWakeupTransport
        : null;
    await wakeup?.unsubscribeFromBookChanges();
    realtimeConnected = false;
    _book = book;
    result = await coordinator.inspect(book);
    lastSuccessfulSyncAt = null;
    await _diagnostics();
    if (book != null &&
        result.status != SyncStatus.signedOut &&
        canSync &&
        wakeup != null) {
      try {
        await wakeup.subscribeToBookChanges(book.id, scheduleSync);
        realtimeConnected = true;
      } catch (_) {
        realtimeConnected = false;
      }
    }
    notifyListeners();
    if (runWhenReady && canSync) await syncNow();
  }

  Future<void> refresh() async {
    result = await coordinator.inspect(_book);
    await _diagnostics();
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (!canSync) return;
    if (busy) {
      _rerunRequested = true;
      return;
    }
    do {
      _rerunRequested = false;
      busy = true;
      result = SyncRunResult(
        status: SyncStatus.syncing,
        pendingCount: result.pendingCount,
      );
      notifyListeners();
      try {
        result = await coordinator.synchronize(_book);
        if (result.pulledCount > 0) {
          await onRemoteDataApplied?.call();
        }
        await _diagnostics();
        if (result.status == SyncStatus.synced) {
          lastSuccessfulSyncAt = DateTime.now();
        }
      } finally {
        busy = false;
        notifyListeners();
      }
    } while (_rerunRequested && canSync);
  }

  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      if (busy) {
        _rerunRequested = true;
        return;
      }
      await refresh();
      if (canSync) await syncNow();
    });
  }

  void onResume() {
    if (canSync) scheduleSync();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final wakeup = coordinator.transport is SyncWakeupTransport
        ? coordinator.transport as SyncWakeupTransport
        : null;
    wakeup?.unsubscribeFromBookChanges();
    super.dispose();
  }
}
