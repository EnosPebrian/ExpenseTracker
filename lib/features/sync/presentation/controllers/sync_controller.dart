import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../master_data/domain/entities/financial_book.dart';
import '../../domain/sync_coordinator.dart';
import '../../domain/sync_models.dart';

class SyncController extends ChangeNotifier {
  SyncController(this.coordinator);

  final SyncCoordinator coordinator;
  FinancialBook? _book;
  SyncRunResult result = const SyncRunResult(status: SyncStatus.localOnly);
  bool busy = false;
  Timer? _debounce;

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
    _book = book;
    result = await coordinator.inspect(book);
    notifyListeners();
    if (runWhenReady && canSync) await syncNow();
  }

  Future<void> refresh() async {
    result = await coordinator.inspect(_book);
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (busy || !canSync) return;
    busy = true;
    result = SyncRunResult(
      status: SyncStatus.syncing,
      pendingCount: result.pendingCount,
    );
    notifyListeners();
    try {
      result = await coordinator.synchronize(_book);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
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
    super.dispose();
  }
}
