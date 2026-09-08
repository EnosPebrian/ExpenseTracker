import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/master_data/system_category.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_recovery_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_recovery_service.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/health/domain/health_check_models.dart';
import 'package:pilgrim_tracker/features/health/domain/system_tithe_health_check.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/reports/domain/financial_statement.dart';
import 'package:pilgrim_tracker/features/reports/domain/financial_statement_generator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

import 'support/beta06_fixture.dart';

const sourceBook = 'a2000000-0000-0000-0000-000000000001';

Transaction transaction({
  required String id,
  required TransactionType type,
  required int amount,
  String category = 'Salary',
  String? categoryId,
}) => Transaction(
  id: id,
  bookId: sourceBook,
  title: id,
  category: category,
  categoryId: categoryId,
  account: 'Cash',
  date: DateTime(2026, 9, 5),
  amount: amount,
  type: type,
);

FinancialStatement statement(FinancialStatementType type) {
  final titheId = SystemCategoryIds.tithe(sourceBook);
  return const FinancialStatementGenerator().generate(
    type: type,
    scope: FinancialStatementScope.household,
    selectedPeriod: DateTime(2026, 9),
    book: FinancialBook(id: sourceBook, name: 'Household'),
    accounts: [
      Account(
        id: 'cash',
        bookId: sourceBook,
        name: 'Cash',
        accountType: AccountType.cash,
      ),
    ],
    transactions: [
      transaction(id: 'income', type: TransactionType.income, amount: 10000),
      transaction(
        id: 'groceries',
        type: TransactionType.expense,
        amount: 2000,
        category: 'Groceries',
        categoryId: 'groceries',
      ),
      transaction(
        id: 'tithe',
        type: TransactionType.expense,
        amount: 500,
        category: 'Old tithe snapshot',
        categoryId: titheId,
      ),
    ],
    transferLinks: const [],
    budgets: const [],
    categoryNamesById: const {},
  );
}

Map<String, Object?> systemCategory({String bookId = sourceBook}) => {
  'id': SystemCategoryIds.tithe(bookId),
  'book_id': bookId,
  'name': 'Tithe',
  'category_type': 'expense',
  'created_at': 1,
  'updated_at': 1,
  'deleted_at': null,
  'version': 1,
};

void main() {
  group('BETA-08L reports', () {
    test('monthly statement shows Due Paid and Balance', () {
      final result = statement(FinancialStatementType.monthly);
      final summary = result.currencySummaries.single;
      expect(summary.titheDue, 1300);
      expect(summary.tithePaid, 500);
      expect(summary.titheBalance, 800);
    });
    test('annual statement shows Due Paid and Balance', () {
      final result = statement(FinancialStatementType.annual);
      final summary = result.currencySummaries.single;
      expect(summary.titheDue, 1300);
      expect(summary.tithePaid, 500);
      expect(summary.titheBalance, 800);
    });
    test('Tithe Paid is not added twice to household expense', () {
      expect(
        statement(
          FinancialStatementType.monthly,
        ).currencySummaries.single.expense,
        2500,
      );
    });
  });

  group('BETA-08L health', () {
    const health = SystemTitheHealthCheck();
    test('valid canonical category is healthy', () {
      expect(
        health
            .evaluate(bookId: sourceBook, categories: [systemCategory()])
            .status,
        HealthCheckItemStatus.healthy,
      );
    });
    test('missing canonical category uses stable diagnostic code', () {
      expect(
        health.evaluate(bookId: sourceBook, categories: const []).code,
        'system_category_tithe_missing',
      );
    });
    test('malformed canonical category uses stable diagnostic code', () {
      expect(
        health
            .evaluate(
              bookId: sourceBook,
              categories: [
                {...systemCategory(), 'category_type': 'income'},
              ],
            )
            .code,
        'system_category_tithe_invalid',
      );
    });
    test('custom Tithe is not diagnosed as malformed canonical data', () {
      expect(
        health
            .evaluate(
              bookId: sourceBook,
              categories: [
                {...systemCategory(), 'id': 'custom'},
              ],
            )
            .code,
        'system_category_tithe_missing',
      );
    });
  });

  group('BETA-08L backup identity', () {
    test('v5-style exact restore preserves canonical ID', () {
      final source = beta06Snapshot(bookId: sourceBook);
      source['categories']!.add(systemCategory());
      final prepared = HouseholdBackupIntegrity.prepareForRestore(source);
      expect(
        prepared['categories']!.any(
          (row) => row['id'] == SystemCategoryIds.tithe(sourceBook),
        ),
        isTrue,
      );
    });
    test(
      'clone remaps System Tithe and payment to destination canonical ID',
      () {
        final source = beta06Snapshot(bookId: sourceBook);
        final titheId = SystemCategoryIds.tithe(sourceBook);
        source['categories']!.add(systemCategory());
        source['transactions']!.add({
          ...source['transactions']!.last,
          'id': 'tithe-payment',
          'category': 'Tithe',
          'category_id': titheId,
          'transaction_type': 'expense',
        });
        final clone = HouseholdBackupIntegrity.prepareForRestore(
          source,
          remapAsCopy: true,
        );
        final destinationBook = clone['household']!.single['id'] as String;
        final destinationTithe = SystemCategoryIds.tithe(destinationBook);
        expect(
          clone['categories']!.where((row) => row['id'] == destinationTithe),
          hasLength(1),
        );
        expect(
          clone['transactions']!.where(
            (row) => row['category_id'] == destinationTithe,
          ),
          hasLength(1),
        );
      },
    );
    test('selective household remap maps only source canonical identity', () {
      expect(
        SystemCategoryIds.remapForHousehold(
          sourceBookId: sourceBook,
          destinationBookId: '11111111-1111-1111-1111-111111111111',
          categoryId: SystemCategoryIds.tithe(sourceBook),
        ),
        SystemCategoryIds.tithe('11111111-1111-1111-1111-111111111111'),
      );
      expect(
        SystemCategoryIds.remapForHousehold(
          sourceBookId: sourceBook,
          destinationBookId: '11111111-1111-1111-1111-111111111111',
          categoryId: 'custom',
        ),
        'custom',
      );
      expect(
        SystemCategoryIds.remapForHousehold(
          sourceBookId: 'legacy-book',
          destinationBookId: 'legacy-copy',
          categoryId: 'legacy-category',
        ),
        'legacy-category',
      );
    });
    test(
      'cross-household selective recovery atomically remaps a System Tithe payment',
      () async {
        const destinationBook = '11111111-1111-1111-1111-111111111111';
        final source = beta06Snapshot(bookId: sourceBook);
        final sourceTithe = SystemCategoryIds.tithe(sourceBook);
        source['categories']!.add(systemCategory());
        source['transactions']!.add({
          ...source['transactions']!.last,
          'id': 'cross-household-tithe-payment',
          'book_id': sourceBook,
          'title': 'Recovered tithe payment',
          'amount': 765432,
          'category': 'Tithe',
          'category_id': sourceTithe,
          'project_id': null,
          'asset_definition_id': null,
          'related_transaction_id': null,
          'transaction_type': 'expense',
        });
        final destination = beta06Snapshot(bookId: destinationBook);
        final store = _RecoveryStore(destination);
        final service = BackupRecoveryService(store: store);
        final preview = await service.analyze(
          backup: _decoded(source),
          activeBookId: destinationBook,
        );
        final payment = preview.candidates.singleWhere(
          (candidate) => candidate.id == 'cross-household-tithe-payment',
        );
        expect(payment.selectable, isTrue);
        expect(payment.record['book_id'], destinationBook);
        expect(
          payment.record['category_id'],
          SystemCategoryIds.tithe(destinationBook),
        );
        expect(payment.record['entered_by_member_id'], isNull);

        await service.recover(preview: preview, selectedKeys: {payment.key});
        expect(store.commits, 1);
        expect(
          store.snapshot['categories']!.where(
            (row) => row['id'] == SystemCategoryIds.tithe(destinationBook),
          ),
          hasLength(1),
        );
        expect(
          store.snapshot['transactions']!.singleWhere(
            (row) => row['id'] == 'cross-household-tithe-payment',
          )['category_id'],
          SystemCategoryIds.tithe(destinationBook),
        );
      },
    );
  });
}

DecodedBackup _decoded(Map<String, List<Map<String, Object?>>> snapshot) {
  final household = snapshot['household']!.single;
  return DecodedBackup(
    manifest: PortableBackupManifest(
      formatVersion: portableBackupFormatVersion,
      applicationVersion: 'test',
      databaseSchemaVersion: 26,
      exportedAt: DateTime(2026, 9, 8),
      bookId: household['id'] as String,
      bookName: household['name'] as String,
      baseCurrencyCode: household['base_currency_code'] as String,
      entityCounts: {
        for (final entry in snapshot.entries) entry.key: entry.value.length,
      },
      contentChecksum: 'test',
      encryptionMetadata: const {},
      financialSummary: const {},
      deletedStateCounts: const {},
    ),
    snapshot: snapshot,
  );
}

Map<String, List<Map<String, Object?>>> _copy(
  Map<String, List<Map<String, Object?>>> source,
) => {
  for (final entry in source.entries)
    entry.key: entry.value.map(Map<String, Object?>.of).toList(),
};

class _RecoveryStore implements BackupRecoveryStore {
  _RecoveryStore(Map<String, List<Map<String, Object?>>> snapshot)
    : snapshot = _copy(snapshot);

  Map<String, List<Map<String, Object?>>> snapshot;
  int commits = 0;

  @override
  Future<int> commitRecovery(
    String bookId,
    Map<String, List<Map<String, Object?>>> records, {
    required bool enqueueSync,
  }) async {
    final next = _copy(snapshot);
    for (final entry in records.entries) {
      next.putIfAbsent(entry.key, () => []).addAll(entry.value.map(Map.of));
    }
    snapshot = next;
    commits++;
    return 0;
  }

  @override
  Future<BackupRecoveryCloudState> recoveryCloudState(String bookId) async =>
      const BackupRecoveryCloudState(linked: false, ready: true);

  @override
  Future<Map<String, List<Map<String, Object?>>>> recoverySnapshot(
    String bookId,
  ) async => _copy(snapshot);
}
