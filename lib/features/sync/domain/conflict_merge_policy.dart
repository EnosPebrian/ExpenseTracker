import 'package:flutter/foundation.dart';
import '../../../core/master_data/system_category.dart';
import 'sync_models.dart';

class ConflictMergePolicy {
  const ConflictMergePolicy._();

  static bool coordinated(SyncConflict conflict) {
    if (conflict.entityType != 'transactions') return false;
    return [conflict.localPayload, conflict.serverPayload].any(
      (row) =>
          row != null &&
          (row['related_transaction_id'] != null ||
              row['asset_definition_id'] != null ||
              row['brokerage_account_id'] != null ||
              row['brokerage_activity_type'] != null ||
              const {
                'asset',
                'investment',
                'transfer',
              }.contains(row['transaction_type']) ||
              SystemCategoryIds.isTithe(
                bookId: conflict.bookId,
                categoryId: row['category_id'] as String?,
              )),
    );
  }

  static Set<String> fields(SyncConflict conflict) {
    if (coordinated(conflict) ||
        conflict.localPayload == null ||
        conflict.serverPayload == null ||
        conflict.localPayload?['deleted_at'] != null ||
        conflict.serverPayload?['deleted_at'] != null) {
      return {};
    }
    final allowed = switch (conflict.entityType) {
      'transactions' => const {
        'transaction_date',
        'title',
        'amount',
        'category',
        'account',
        'project_id',
        'reference',
        'note',
      },
      'monthly_category_budgets' => const {'limit_minor', 'note'},
      'accounts' => const {'name'},
      'categories' => const {'name'},
      'projects' => const {'name', 'status'},
      'household_members' => const {'display_name'},
      _ => const <String>{},
    };
    return allowed
        .where(
          (field) =>
              conflict.localPayload?[field] != conflict.serverPayload?[field] ||
              (field == 'category' &&
                  conflict.localPayload?['category_id'] !=
                      conflict.serverPayload?['category_id']),
        )
        .toSet();
  }

  static void validateTransaction(
    SyncConflict conflict,
    Map<String, Object?>? payload,
  ) {
    if (payload == null) throw StateError('Choose a resolution first.');
    if (coordinated(conflict)) {
      if (!mapEquals(payload, conflict.localPayload) &&
          !mapEquals(payload, conflict.serverPayload)) {
        throw StateError(
          'Linked financial records must be resolved as a whole.',
        );
      }
      return;
    }
    final server = conflict.serverPayload ?? {};
    final local = conflict.localPayload ?? {};
    final chosenMoney = (payload['amount'], payload['account']);
    if (chosenMoney != (local['amount'], local['account']) &&
        chosenMoney != (server['amount'], server['account'])) {
      throw StateError(
        'Choose amount and account from the same version to avoid changing currency meaning.',
      );
    }
    const allowed = {
      'transaction_date',
      'title',
      'amount',
      'category',
      'category_id',
      'account',
      'project_id',
      'reference',
      'note',
    };
    for (final field in {...server.keys, ...payload.keys}) {
      if (!allowed.contains(field) && payload[field] != server[field]) {
        throw StateError('Identity and financial structure cannot be merged.');
      }
    }
    if (payload.containsKey('amount') &&
        (payload['amount'] is! int || (payload['amount'] as int) <= 0)) {
      throw StateError('The transaction amount must be a positive integer.');
    }
  }
}
