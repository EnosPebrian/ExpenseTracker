import 'package:flutter/foundation.dart';

import '../../domain/restore_lifecycle_service.dart';

typedef RestoreCloudBootstrap =
    Future<void> Function(RestoreLifecycleClone clone);

class RestoreLifecycleController extends ChangeNotifier {
  RestoreLifecycleController({
    required this.service,
    required this.bootstrapCloud,
  });

  final RestoreLifecycleService service;
  final RestoreCloudBootstrap bootstrapCloud;

  RestoreLifecyclePreview? preview;
  RestoreLifecycleClone? createdClone;
  String? error;
  String? message;
  bool busy = false;
  bool keepLocalSelected = false;

  bool appliesTo(String bookId) =>
      preview?.sourceBookId == bookId || createdClone?.book.id == bookId;

  Future<void> load(String bookId) async {
    preview = null;
    createdClone = null;
    error = null;
    message = null;
    keepLocalSelected = false;
    try {
      preview = await service.preview(bookId);
    } catch (_) {
      // A normal local or already-synchronized household has no restore panel.
    }
    notifyListeners();
  }

  void keepLocalOnly() {
    keepLocalSelected = true;
    error = null;
    message = 'This restored household will remain local-only.';
    notifyListeners();
  }

  Future<void> createNewSharedHousehold(String proposedName) async {
    final source = preview;
    if (busy || source == null) return;
    busy = true;
    error = null;
    message = null;
    notifyListeners();
    try {
      final clone = await service.cloneForNewSharedHousehold(
        sourceBookId: source.sourceBookId,
        proposedName: proposedName,
      );
      createdClone = clone;
      await bootstrapCloud(clone);
      message = '${clone.book.name} is now a synchronized shared household.';
    } catch (caught) {
      error = caught.toString();
      message =
          'Cloud setup did not complete. The original restored household remains unchanged.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
