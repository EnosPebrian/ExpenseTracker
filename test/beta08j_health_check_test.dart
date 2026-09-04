import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/health/domain/health_check_models.dart';
import 'package:pilgrim_tracker/features/health/domain/health_check_service.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/import_review_draft.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/import_review_session.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/internal_transfer_link.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_import_rule.dart';

void main() {
  group('BETA-08J read-only health checks', () {
    test('healthy household reports Healthy with stable codes', () async {
      final report = await _run(_healthySnapshot());

      expect(report.overallStatus, HealthCheckOverallStatus.healthy);
      expect(
        report.sections
            .expand((section) => section.checks)
            .map((item) => item.code),
        containsAll([
          'database.schema_version',
          'transactions.invalid_reference',
          'transfers.canonical_integrity',
          'inbox.deferred_identity',
          'sync.pending_outbox',
          'backup.status',
        ]),
      );
    });

    test(
      'broken canonical transfer is critical and never mutates input',
      () async {
        final snapshot = _healthySnapshot();
        final originalTransactions = snapshot.rows('transactions').length;
        final records = _copyRecords(snapshot);
        records['transfer_links'] = [
          {
            ...records['transfer_links']!.single,
            'incoming_transaction_id': 'missing-leg',
          },
        ];

        final report = await _run(_replace(snapshot, records: records));

        expect(report.overallStatus, HealthCheckOverallStatus.critical);
        expect(
          _item(report, 'transfers.canonical_integrity').status,
          HealthCheckItemStatus.error,
        );
        expect(snapshot.rows('transactions'), hasLength(originalTransactions));
      },
    );

    test(
      'valid unresolved draft is healthy and pending is informational',
      () async {
        final snapshot = _withPendingDraft(_healthySnapshot());
        final report = await _run(snapshot);

        expect(
          _item(report, 'inbox.deferred_identity').status,
          HealthCheckItemStatus.healthy,
        );
        expect(
          _item(report, 'inbox.pending_sessions').status,
          HealthCheckItemStatus.info,
        );
        expect(report.overallStatus, HealthCheckOverallStatus.healthy);
      },
    );

    test('one-sided deferred identity binding is critical', () async {
      final snapshot = _withPendingDraft(_healthySnapshot());
      final draft = {
        ...snapshot.importDrafts.single,
        'deterministic_transaction_id': 'final-id',
      };
      final report = await _run(_replace(snapshot, importDrafts: [draft]));

      expect(
        _item(report, 'inbox.deferred_identity').status,
        HealthCheckItemStatus.error,
      );
      expect(report.overallStatus, HealthCheckOverallStatus.critical);
    });

    test('inverse deferred identity binding is critical', () async {
      final snapshot = _withPendingDraft(_healthySnapshot());
      final draft = {
        ...snapshot.importDrafts.single,
        'deterministic_transaction_account_id': 'account-a',
      };
      final report = await _run(_replace(snapshot, importDrafts: [draft]));

      expect(
        _item(report, 'inbox.deferred_identity').status,
        HealthCheckItemStatus.error,
      );
    });

    test('completed included unresolved draft is critical', () async {
      final snapshot = _withPendingDraft(_healthySnapshot());
      final session = {
        ...snapshot.importSessions.single,
        'state': 'completed',
        'completed_at': DateTime(2026, 9, 1).millisecondsSinceEpoch,
      };
      final report = await _run(_replace(snapshot, importSessions: [session]));

      expect(
        _item(report, 'inbox.deferred_identity').status,
        HealthCheckItemStatus.error,
      );
    });

    test(
      'local-only mode is healthy and cloud unavailable is only attention',
      () async {
        final localReport = await _run(_healthySnapshot());
        expect(
          _item(localReport, 'sync.mode').status,
          HealthCheckItemStatus.healthy,
        );

        final unavailable = _replace(
          _healthySnapshot(),
          sync: const HealthSyncSnapshot(
            cloudState: HealthCloudState.unavailable,
            pendingOutboxCount: 0,
            failedOutboxCount: 0,
            unresolvedConflictCount: 0,
          ),
        );
        final unavailableReport = await _run(unavailable);
        expect(
          unavailableReport.overallStatus,
          HealthCheckOverallStatus.attentionNeeded,
        );
        expect(
          _item(unavailableReport, 'transactions.invalid_reference').status,
          HealthCheckItemStatus.healthy,
        );
      },
    );

    test(
      'pending, failed, and conflicting sync work stays non-critical',
      () async {
        final report = await _run(
          _replace(
            _healthySnapshot(),
            sync: const HealthSyncSnapshot(
              cloudState: HealthCloudState.pending,
              pendingOutboxCount: 3,
              failedOutboxCount: 1,
              unresolvedConflictCount: 2,
            ),
          ),
        );

        expect(report.overallStatus, HealthCheckOverallStatus.attentionNeeded);
        expect(
          _item(report, 'sync.pending_outbox').status,
          HealthCheckItemStatus.warning,
        );
        expect(
          _item(report, 'sync.failed_outbox').status,
          HealthCheckItemStatus.warning,
        );
        expect(
          _item(report, 'sync.unresolved_conflicts').status,
          HealthCheckItemStatus.warning,
        );
      },
    );

    test('archived historical references remain valid', () async {
      final snapshot = _healthySnapshot();
      final records = _copyRecords(snapshot);
      records['accounts'] = [
        {
          ...records['accounts']!.first,
          'deleted_at': DateTime(2026, 8, 1).millisecondsSinceEpoch,
        },
        records['accounts']![1],
      ];
      final report = await _run(_replace(snapshot, records: records));

      expect(
        _item(report, 'transactions.invalid_reference').status,
        HealthCheckItemStatus.healthy,
      );
    });

    test('missing and cross-household references are critical', () async {
      final snapshot = _healthySnapshot();
      final records = _copyRecords(snapshot);
      records['transactions'] = [
        {...records['transactions']!.first, 'account': 'Missing account'},
        ...records['transactions']!.skip(1),
      ];
      records['budgets'] = [_budgetRecord(bookId: 'other-book')];

      final report = await _run(_replace(snapshot, records: records));
      expect(
        _item(report, 'transactions.invalid_reference').status,
        HealthCheckItemStatus.error,
      );
      expect(report.overallStatus, HealthCheckOverallStatus.critical);
    });

    test('invalid active rule and duplicate budget key are detected', () async {
      final snapshot = _healthySnapshot();
      final records = _copyRecords(snapshot);
      records['transaction_import_rules'] = [
        TransactionImportRule(
          id: 'rule-a',
          bookId: 'book-a',
          name: 'Bad rule',
          transactionType: TransactionImportRuleType.expense,
          matchField: TransactionImportRuleMatchField.description,
          operator: TransactionImportRuleOperator.contains,
          pattern: 'market',
          categoryId: 'missing-category',
        ).toRecord(),
      ];
      records['budgets'] = [
        _budgetRecord(),
        {..._budgetRecord(), 'id': 'budget-b'},
      ];

      final report = await _run(_replace(snapshot, records: records));
      expect(
        _item(report, 'rules.reference_integrity').status,
        HealthCheckItemStatus.error,
      );
      expect(
        _item(report, 'budgets.reference_integrity').status,
        HealthCheckItemStatus.error,
      );
    });

    test(
      'backup status is truthful without claiming a backup exists',
      () async {
        final report = await _run(_healthySnapshot());
        final status = _item(report, 'backup.status');

        expect(status.status, HealthCheckItemStatus.info);
        expect(status.summary, contains('not tracked'));
        expect(
          status.summary.toLowerCase(),
          isNot(contains('no backup exists')),
        );
      },
    );

    test('privacy-safe summary excludes financial and identity data', () async {
      final report = await _run(_healthySnapshot());
      final summary = report.privacySafeSummary();

      expect(summary, contains('Overall: Healthy'));
      expect(summary, isNot(contains('Private merchant')));
      expect(summary, isNot(contains('987654')));
      expect(summary, isNot(contains('tx-out')));
      expect(summary, isNot(contains('source-fingerprint-secret')));
    });

    test(
      'large household completes with linear-style snapshot traversal',
      () async {
        final snapshot = _healthySnapshot();
        final records = _copyRecords(snapshot);
        final base = records['transactions']!.first;
        records['transactions'] = List.generate(5000, (index) {
          return {
            ...base,
            'id': 'bulk-$index',
            'title': 'Private merchant $index',
            'transaction_date': DateTime(
              2026,
              8,
              1,
            ).add(Duration(minutes: index)).millisecondsSinceEpoch,
          };
        });

        final report = await _run(_replace(snapshot, records: records));
        expect(report.sections, isNotEmpty);
        expect(
          _item(report, 'transactions.duplicate_identity').status,
          HealthCheckItemStatus.healthy,
        );
      },
    );

    test('data source failure becomes a read-only critical report', () async {
      final report = await HealthCheckService(
        dataSource: _ThrowingSource(),
        now: () => DateTime(2026, 9, 1),
      ).run();

      expect(report.overallStatus, HealthCheckOverallStatus.critical);
      expect(
        _item(report, 'database.open').status,
        HealthCheckItemStatus.error,
      );
    });
  });
}

Future<HealthCheckReport> _run(HealthCheckSnapshot snapshot) =>
    HealthCheckService(
      dataSource: _FakeSource(snapshot),
      now: () => DateTime(2026, 9, 1, 8, 15),
    ).run();

HealthCheckSnapshot _healthySnapshot() {
  final created = DateTime(2026, 1, 1);
  final accountA = Account(
    id: 'account-a',
    bookId: 'book-a',
    name: 'Cash',
    accountType: AccountType.cash,
    openingBalance: 100000,
    openingBalanceDate: created,
    createdAt: created,
    updatedAt: created,
  );
  final accountB = Account(
    id: 'account-b',
    bookId: 'book-a',
    name: 'Bank',
    accountType: AccountType.bank,
    openingBalance: 200000,
    openingBalanceDate: created,
    createdAt: created,
    updatedAt: created,
  );
  final outgoing = Transaction(
    id: 'tx-out',
    bookId: 'book-a',
    enteredByMemberId: 'member-a',
    title: 'Private merchant',
    category: 'Groceries',
    account: 'Cash',
    date: DateTime(2026, 9, 1),
    amount: 987654,
    type: TransactionType.expense,
    createdAt: created,
    updatedAt: created,
  );
  final incoming = Transaction(
    id: 'tx-in',
    bookId: 'book-a',
    enteredByMemberId: 'member-a',
    title: 'Internal transfer received',
    category: 'Salary',
    account: 'Bank',
    date: DateTime(2026, 9, 1),
    amount: 987654,
    type: TransactionType.income,
    createdAt: created,
    updatedAt: created,
  );
  final link = InternalTransferLink(
    id: 'link-a',
    bookId: 'book-a',
    outgoingTransactionId: outgoing.id,
    incomingTransactionId: incoming.id,
    sourceAccountId: accountA.id,
    destinationAccountId: accountB.id,
    currencyCode: 'IDR',
    amount: outgoing.amount,
    createdAt: created,
    updatedAt: created,
  );
  return HealthCheckSnapshot(
    schemaVersion: 25,
    expectedSchemaVersion: 25,
    bookId: 'book-a',
    backupFormatVersion: 4,
    sync: const HealthSyncSnapshot(
      cloudState: HealthCloudState.localOnly,
      pendingOutboxCount: 0,
      failedOutboxCount: 0,
      unresolvedConflictCount: 0,
    ),
    localSession: const {'active_book_id': 'book-a'},
    records: {
      'household': [
        {'id': 'book-a', 'base_currency_code': 'IDR', 'deleted_at': null},
      ],
      'members': [
        {'id': 'member-a', 'book_id': 'book-a', 'deleted_at': null},
      ],
      'accounts': [accountA.toRecord(), accountB.toRecord()],
      'categories': [
        {
          'id': 'category-expense',
          'book_id': 'book-a',
          'name': 'Groceries',
          'category_type': 'expense',
          'deleted_at': null,
        },
        {
          'id': 'category-income',
          'book_id': 'book-a',
          'name': 'Salary',
          'category_type': 'income',
          'deleted_at': null,
        },
      ],
      'projects': const [],
      'transactions': [outgoing.toRecord(), incoming.toRecord()],
      'transfer_links': [link.toRecord()],
      'asset_definitions': const [],
      'budgets': const [],
      'transaction_import_rules': const [],
      'manual_market_prices': const [],
    },
    importSessions: const [],
    importDrafts: const [],
  );
}

HealthCheckSnapshot _withPendingDraft(HealthCheckSnapshot snapshot) {
  final session = ImportReviewSession(
    id: 'session-a',
    bookId: 'book-a',
    sourceType: ImportReviewSourceType.csv,
    title: 'Saved import',
    sourceFingerprint: 'source-fingerprint-secret',
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );
  final draft = ImportReviewDraft(
    id: 'draft-a',
    sessionId: session.id,
    bookId: 'book-a',
    sourceRowIdentity: 'row-fingerprint-secret',
    sourceRowKey: 'row-1',
    sourceIndex: 0,
    transactionDate: DateTime(2026, 9, 1),
    description: 'Private source description',
    amountMinor: 12345,
    currencyCode: 'IDR',
    transactionType: TransactionType.expense,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );
  return _replace(
    snapshot,
    importSessions: [session.toRecord()],
    importDrafts: [draft.toRecord()],
  );
}

Map<String, Object?> _budgetRecord({String bookId = 'book-a'}) => {
  'id': 'budget-a',
  'book_id': bookId,
  'category_id': 'category-expense',
  'month_start': '2026-09-01',
  'limit_minor': 100000,
  'currency_code': 'IDR',
  'note': null,
  'created_at': DateTime(2026, 9, 1).millisecondsSinceEpoch,
  'updated_at': DateTime(2026, 9, 1).millisecondsSinceEpoch,
  'deleted_at': null,
  'version': 1,
  'device_id': 'test',
  'sync_status': 'local_only',
};

Map<String, List<Map<String, Object?>>> _copyRecords(
  HealthCheckSnapshot snapshot,
) => {
  for (final entry in snapshot.records.entries)
    entry.key: entry.value.map(Map<String, Object?>.of).toList(),
};

HealthCheckSnapshot _replace(
  HealthCheckSnapshot source, {
  Map<String, List<Map<String, Object?>>>? records,
  List<Map<String, Object?>>? importSessions,
  List<Map<String, Object?>>? importDrafts,
  HealthSyncSnapshot? sync,
}) => HealthCheckSnapshot(
  schemaVersion: source.schemaVersion,
  expectedSchemaVersion: source.expectedSchemaVersion,
  bookId: source.bookId,
  backupFormatVersion: source.backupFormatVersion,
  sync: sync ?? source.sync,
  localSession: source.localSession,
  records: records ?? source.records,
  importSessions: importSessions ?? source.importSessions,
  importDrafts: importDrafts ?? source.importDrafts,
);

HealthCheckItem _item(HealthCheckReport report, String code) => report.sections
    .expand((section) => section.checks)
    .singleWhere((item) => item.code == code);

class _FakeSource implements HealthCheckDataSource {
  const _FakeSource(this.snapshot);
  final HealthCheckSnapshot snapshot;
  @override
  Future<HealthCheckSnapshot> load() async => snapshot;
}

class _ThrowingSource implements HealthCheckDataSource {
  @override
  Future<HealthCheckSnapshot> load() async => throw StateError('broken');
}
