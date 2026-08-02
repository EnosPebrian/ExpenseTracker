import 'package:uuid/uuid.dart';

import 'sync_models.dart';
import 'sync_repository.dart';
import 'sync_transport.dart';

class ConflictResolutionService {
  ConflictResolutionService({
    required this.repository,
    required this.transport,
  });
  final SyncConflictRepository repository;
  final ConflictResolutionTransport transport;

  Future<List<SyncConflict>> load(String bookId) =>
      repository.conflicts(bookId);

  Future<void> resolve(
    SyncConflict conflict,
    ConflictResolutionType type, {
    Map<String, Object?>? mergedPayload,
  }) async {
    if (type == ConflictResolutionType.manualMerge &&
        !_manualMergeEntities.contains(conflict.entityType)) {
      throw StateError(
        'This linked financial conflict must be resolved as a whole.',
      );
    }
    final operationId = const Uuid().v4();
    if (!await repository.beginResolution(conflict.id, operationId)) {
      throw StateError('This conflict has already been resolved.');
    }
    try {
      final chosen =
          type == ConflictResolutionType.keepServer ||
              type == ConflictResolutionType.keepDeleted
          ? conflict.serverPayload
          : (mergedPayload ?? conflict.localPayload);
      final result = await transport.resolveConflict(
        conflict: conflict,
        resolutionOperationId: operationId,
        resolutionType: type,
        resolvedPayload: chosen,
      );
      if (result.status == 'staleResolution') {
        throw StateError(
          'This conflict changed again. Refresh and review the latest version.',
        );
      }
      if (result.status != 'resolved' && result.status != 'alreadyResolved') {
        throw StateError('The conflict could not be resolved safely.');
      }
      final canonical = result.canonicalPayload;
      if (canonical == null) {
        throw StateError('The server did not return the resolved record.');
      }
      await repository.completeResolution(
        conflict.id,
        resolution: type.name,
        canonicalPayload: canonical,
        serverSequence: result.serverSequence ?? 0,
      );
    } catch (_) {
      await repository.failResolution(conflict.id);
      rethrow;
    }
  }

  static const _manualMergeEntities = {
    'accounts',
    'transactions',
    'projects',
    'categories',
    'household_members',
    'asset_definitions',
  };
}
