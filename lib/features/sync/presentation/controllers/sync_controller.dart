import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../master_data/domain/entities/financial_book.dart';
import '../../domain/sync_coordinator.dart';
import '../../domain/sync_models.dart';
import '../../domain/sync_transport.dart';

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
    final cursor = book == null
        ? null
        : await coordinator.repository.getCursor(book.id);
    lastSuccessfulSyncAt = _showsSuccessfulHistory(result.status)
        ? cursor?.updatedAt
        : null;
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
    final book = _book;
    final cursor = book == null
        ? null
        : await coordinator.repository.getCursor(book.id);
    lastSuccessfulSyncAt = _showsSuccessfulHistory(result.status)
        ? cursor?.updatedAt
        : null;
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
        if (result.status == SyncStatus.synced ||
            result.status == SyncStatus.conflict) {
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

  static bool _showsSuccessfulHistory(SyncStatus status) => switch (status) {
    SyncStatus.synced ||
    SyncStatus.pending ||
    SyncStatus.syncing ||
    SyncStatus.offline ||
    SyncStatus.retryScheduled ||
    SyncStatus.conflict => true,
    _ => false,
  };

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
