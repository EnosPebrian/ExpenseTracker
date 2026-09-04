import '../../../core/database/local_store.dart';
import '../domain/entities/transaction_import_rule.dart';

class LocalTransactionImportRuleRepository {
  const LocalTransactionImportRuleRepository(this.store);

  final LocalStore store;

  Future<List<TransactionImportRule>> getAll({
    required String bookId,
    bool includeDeleted = false,
    bool activeOnly = false,
  }) async => (await store.getTransactionImportRules(
    bookId: bookId,
    includeDeleted: includeDeleted,
    activeOnly: activeOnly,
  )).map(TransactionImportRule.fromRecord).toList();

  Future<TransactionImportRule> save(TransactionImportRule rule) async =>
      TransactionImportRule.fromRecord(
        await store.upsertTransactionImportRule(rule.toRecord()),
      );

  Future<TransactionImportRule> setEnabled(
    TransactionImportRule rule,
    bool enabled,
  ) => save(
    rule.copyWith(
      enabled: enabled,
      updatedAt: DateTime.now(),
      version: rule.version + 1,
      syncStatus: 'pending',
    ),
  );

  Future<void> delete(TransactionImportRule rule) =>
      store.softDeleteTransactionImportRule(
        rule.id,
        DateTime.now().millisecondsSinceEpoch,
      );
}
