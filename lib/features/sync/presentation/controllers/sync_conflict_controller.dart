import 'package:flutter/foundation.dart';

import '../../domain/conflict_resolution_service.dart';
import '../../domain/sync_models.dart';

class SyncConflictController extends ChangeNotifier {
  SyncConflictController({required this.service, this.afterResolution});
  final ConflictResolutionService service;
  final Future<void> Function()? afterResolution;
  String? _bookId;
  List<SyncConflict> conflicts = const [];
  bool loading = false;
  String? resolvingId;
  String? error;

  int get count => conflicts.length;
  Future<void> setBook(String? bookId) async {
    _bookId = bookId;
    await load();
  }

  Future<void> load() async {
    if (_bookId == null) {
      conflicts = const [];
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      conflicts = await service.load(_bookId!);
    } catch (_) {
      error = 'Conflicts could not be loaded.';
    }
    loading = false;
    notifyListeners();
  }

  Future<bool> resolve(
    SyncConflict conflict,
    ConflictResolutionType type, {
    Map<String, Object?>? mergedPayload,
  }) async {
    resolvingId = conflict.id;
    error = null;
    notifyListeners();
    try {
      await service.resolve(conflict, type, mergedPayload: mergedPayload);
      resolvingId = null;
      await load();
      await afterResolution?.call();
      return true;
    } on StateError catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Resolution failed. Your conflict is still saved.';
    }
    resolvingId = null;
    notifyListeners();
    return false;
  }
}
