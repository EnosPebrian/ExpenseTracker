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
    if (type == ConflictResolutionType.manualMerge &&
        conflict.entityType == 'monthly_category_budgets') {
      _validateBudgetMerge(conflict, mergedPayload);
    }
    if (type == ConflictResolutionType.manualMerge &&
        conflict.entityType == 'transaction_import_rules') {
      _validateImportRuleMerge(conflict, mergedPayload);
    }
    if (type == ConflictResolutionType.manualMerge &&
        conflict.entityType == 'import_review_sessions') {
      _validateImportReviewSessionMerge(conflict, mergedPayload);
    }
    if (type == ConflictResolutionType.manualMerge &&
        conflict.entityType == 'import_review_drafts') {
      _validateImportReviewDraftMerge(conflict, mergedPayload);
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
    'monthly_category_budgets',
    'transaction_import_rules',
    'import_review_sessions',
    'import_review_drafts',
  };

  static void _validateImportReviewSessionMerge(
    SyncConflict conflict,
    Map<String, Object?>? mergedPayload,
  ) {
    final shared = conflict.serverPayload;
    if (mergedPayload == null || shared == null) {
      throw StateError('A discarded import session cannot be merged.');
    }
    for (final field in const {
      'id',
      'book_id',
      'source_type',
      'source_fingerprint',
      'created_at',
      'deleted_at',
    }) {
      if (mergedPayload[field] != shared[field]) {
        throw StateError('Import session identity cannot be merged.');
      }
    }
    if (const {'completed', 'discarded'}.contains(shared['state']) &&
        mergedPayload['state'] != shared['state']) {
      throw StateError('A terminal import session cannot be reopened.');
    }
  }

  static void _validateImportReviewDraftMerge(
    SyncConflict conflict,
    Map<String, Object?>? mergedPayload,
  ) {
    final shared = conflict.serverPayload;
    final local = conflict.localPayload;
    if (mergedPayload == null || shared == null || local == null) {
      throw StateError('A discarded import draft cannot be merged.');
    }
    for (final field in const {
      'id',
      'session_id',
      'book_id',
      'source_row_identity',
      'source_row_key',
      'created_at',
      'deleted_at',
    }) {
      if (mergedPayload[field] != shared[field]) {
        throw StateError('Import draft identity cannot be merged.');
      }
    }
    final transactionId = mergedPayload['deterministic_transaction_id'];
    final identityAccount =
        mergedPayload['deterministic_transaction_account_id'];
    if ((transactionId == null) != (identityAccount == null)) {
      throw StateError(
        'Import transaction identity and account binding must be resolved together.',
      );
    }
    final localPair = (
      local['deterministic_transaction_id'],
      local['deterministic_transaction_account_id'],
    );
    final serverPair = (
      shared['deterministic_transaction_id'],
      shared['deterministic_transaction_account_id'],
    );
    if ((transactionId, identityAccount) != localPair &&
        (transactionId, identityAccount) != serverPair) {
      throw StateError(
        'Resolve the import transaction identity and account binding as one state.',
      );
    }
  }

  static void _validateImportRuleMerge(
    SyncConflict conflict,
    Map<String, Object?>? mergedPayload,
  ) {
    if (mergedPayload == null || conflict.serverPayload == null) {
      throw StateError(
        'A deleted import rule cannot be merged field by field.',
      );
    }
    for (final field in const {'id', 'book_id', 'created_at', 'deleted_at'}) {
      if (mergedPayload[field] != conflict.serverPayload![field]) {
        throw StateError(
          'Import rule identity and lifecycle fields cannot be merged.',
        );
      }
    }
  }

  static void _validateBudgetMerge(
    SyncConflict conflict,
    Map<String, Object?>? mergedPayload,
  ) {
    if (mergedPayload == null) {
      throw StateError('Choose the budget amount and note before merging.');
    }
    final shared = conflict.serverPayload;
    if (shared == null) {
      throw StateError('A deleted budget cannot be merged field by field.');
    }
    for (final field in const {
      'id',
      'book_id',
      'category_id',
      'month_start',
      'currency_code',
      'created_at',
      'deleted_at',
    }) {
      if (mergedPayload[field] != shared[field]) {
        throw StateError(
          'Budget identity and lifecycle fields cannot be merged.',
        );
      }
    }
    final amount = mergedPayload['limit_minor'];
    final note = mergedPayload['note'];
    if (amount is! num || amount.toInt() <= 0) {
      throw StateError('A merged budget amount must be positive.');
    }
    if (note is String && note.length > 120) {
      throw StateError('A merged budget note cannot exceed 120 characters.');
    }
  }
}
