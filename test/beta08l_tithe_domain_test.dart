import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/master_data/system_category.dart';
import 'package:pilgrim_tracker/features/tithe/domain/tithe_summary.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/internal_transfer_link.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

const bookA = 'a2000000-0000-0000-0000-000000000001';
const bookB = 'b2000000-0000-0000-0000-000000000001';

Transaction entry({
  String? id,
  String bookId = bookA,
  TransactionType type = TransactionType.income,
  int amount = 1000,
  DateTime? date,
  String? categoryId,
  String category = 'Income',
  String account = 'Cash',
  DateTime? deletedAt,
  String title = 'Entry',
}) => Transaction(
  id: id,
  bookId: bookId,
  title: title,
  category: category,
  categoryId: categoryId,
  account: account,
  date: date ?? DateTime(2026, 1, 10),
  amount: amount,
  type: type,
  deletedAt: deletedAt,
);

Transaction payment({
  String? id,
  String bookId = bookA,
  int amount = 100,
  DateTime? date,
  String? categoryId,
  String category = 'Tithe',
  TransactionType type = TransactionType.expense,
  DateTime? deletedAt,
}) => entry(
  id: id,
  bookId: bookId,
  type: type,
  amount: amount,
  date: date,
  categoryId: categoryId ?? SystemCategoryIds.tithe(bookId),
  category: category,
  deletedAt: deletedAt,
  title: 'Tithe payment',
);

TitheSummary summary(
  Iterable<Transaction> transactions, {
  DateTime? asOf,
  Iterable<InternalTransferLink> links = const [],
  Map<String, String>? accountCurrencyByName,
  int limit = 8,
}) => TitheSummaryCalculator().calculate(
  bookId: bookA,
  currencyCode: 'IDR',
  transactions: transactions,
  transferLinks: links,
  asOf: asOf ?? DateTime(2026, 2, 20),
  accountCurrencyByName: accountCurrencyByName,
  recentPaymentLimit: limit,
);

void main() {
  group('BETA-08L system identity', () {
    test('PostgreSQL golden vector 1', () {
      expect(
        SystemCategoryIds.tithe('00000000-0000-0000-0000-000000000000'),
        '974e8a60-8e63-5615-a4fd-b8acb4ecfec5',
      );
    });
    test('PostgreSQL golden vector 2', () {
      expect(
        SystemCategoryIds.tithe('11111111-1111-1111-1111-111111111111'),
        '2a753de7-0888-5d83-ab12-de274b13c6f0',
      );
    });
    test('PostgreSQL golden vector 3', () {
      expect(
        SystemCategoryIds.tithe(bookA),
        '2daf63af-1d0b-539b-be96-174948bb8ed0',
      );
    });
    test('same household is deterministic', () {
      expect(SystemCategoryIds.tithe(bookA), SystemCategoryIds.tithe(bookA));
    });
    test('different households differ', () {
      expect(
        SystemCategoryIds.tithe(bookA),
        isNot(SystemCategoryIds.tithe(bookB)),
      );
    });
    test('display text is not identity input', () {
      expect(
        SystemCategoryDefinition.tithe.identityName,
        'system-category:tithe',
      );
    });
    test('canonical semantic shape is expense Tithe', () {
      expect(SystemCategoryDefinition.tithe.name, 'Tithe');
      expect(SystemCategoryDefinition.tithe.categoryType, 'expense');
    });
    test('rename protection rejects canonical ID', () {
      expect(
        () => SystemCategoryProtection.rejectMutation(
          bookId: bookA,
          categoryId: SystemCategoryIds.tithe(bookA),
          mutation: SystemCategoryMutation.rename,
        ),
        throwsA(isA<SystemCategoryIntegrityException>()),
      );
    });
    test('delete protection rejects canonical ID', () {
      expect(
        () => SystemCategoryProtection.rejectMutation(
          bookId: bookA,
          categoryId: SystemCategoryIds.tithe(bookA),
          mutation: SystemCategoryMutation.delete,
        ),
        throwsA(isA<SystemCategoryIntegrityException>()),
      );
    });
    test('archive protection rejects canonical ID', () {
      expect(
        () => SystemCategoryProtection.rejectMutation(
          bookId: bookA,
          categoryId: SystemCategoryIds.tithe(bookA),
          mutation: SystemCategoryMutation.archive,
        ),
        throwsA(isA<SystemCategoryIntegrityException>()),
      );
    });
    test('type protection rejects canonical ID', () {
      expect(
        () => SystemCategoryProtection.rejectMutation(
          bookId: bookA,
          categoryId: SystemCategoryIds.tithe(bookA),
          mutation: SystemCategoryMutation.changeType,
        ),
        throwsA(isA<SystemCategoryIntegrityException>()),
      );
    });
    test('custom ID remains mutable even when named Tithe', () {
      expect(
        () => SystemCategoryProtection.rejectMutation(
          bookId: bookA,
          categoryId: 'custom-tithe',
          mutation: SystemCategoryMutation.rename,
        ),
        returnsNormally,
      );
    });
  });

  group('BETA-08L tithe calculation', () {
    test('empty household has a clean zero summary', () {
      final result = summary(const []);
      expect(result.cumulative.due, 0);
      expect(result.cumulative.paid, 0);
    });
    test('Due uses the existing TithePolicy', () {
      expect(summary([entry(amount: 10000)]).cumulative.due, 1300);
    });
    test('partial payment remains outstanding', () {
      final result = summary([entry(amount: 10000), payment(amount: 700)]);
      expect(result.cumulative.balance, 600);
      expect(result.cumulative.isOutstanding, isTrue);
    });
    test('full payment is fully paid', () {
      expect(
        summary([
          entry(amount: 10000),
          payment(amount: 1300),
        ]).cumulative.balance,
        0,
      );
    });
    test('overpayment becomes advance without clamping', () {
      final result = summary([entry(amount: 10000), payment(amount: 1500)]);
      expect(result.cumulative.balance, -200);
      expect(result.cumulative.isAdvance, isTrue);
    });
    test('multi-month balance carries forward', () {
      final result = summary([
        entry(amount: 10000, date: DateTime(2026, 1, 3)),
        payment(amount: 700, date: DateTime(2026, 1, 5)),
        entry(amount: 5000, date: DateTime(2026, 2, 3)),
        payment(amount: 600, date: DateTime(2026, 2, 5)),
      ]);
      expect(result.cumulative.due, 1950);
      expect(result.cumulative.paid, 1300);
      expect(result.cumulative.balance, 650);
    });
    test('payment date determines its month', () {
      final result = summary([
        entry(amount: 10000, date: DateTime(2026, 1, 3)),
        payment(amount: 1300, date: DateTime(2026, 2, 5)),
      ]);
      expect(result.currentMonth.paid, 1300);
      expect(result.currentMonth.due, 0);
    });
    test('payment expense creates no additional Due', () {
      final result = summary([entry(amount: 10000), payment(amount: 1300)]);
      expect(result.cumulative.due, 1300);
    });
    test('canonical ID counts despite an old display snapshot', () {
      expect(payment(category: 'Old snapshot').categoryId, isNotNull);
      expect(summary([payment(category: 'Old snapshot')]).cumulative.paid, 100);
    });
    test('Tithe text with wrong ID does not count', () {
      expect(summary([payment(categoryId: 'custom')]).cumulative.paid, 0);
    });
    test('Tithe text with null ID does not count', () {
      final row = entry(
        type: TransactionType.expense,
        category: 'Tithe',
        categoryId: null,
      );
      expect(summary([row]).cumulative.paid, 0);
    });
    test('custom same-name category does not count', () {
      expect(summary([payment(categoryId: 'random-id')]).cumulative.paid, 0);
    });
    test('canonical transfer leg does not count', () {
      final row = payment(id: 'out');
      final link = InternalTransferLink(
        bookId: bookA,
        outgoingTransactionId: 'out',
        incomingTransactionId: 'in',
        sourceAccountId: 'a',
        destinationAccountId: 'b',
        currencyCode: 'IDR',
        amount: row.amount,
      );
      expect(summary([row], links: [link]).cumulative.paid, 0);
    });
    test('deleted payment does not count', () {
      expect(
        summary([payment(deletedAt: DateTime(2026, 2, 1))]).cumulative.paid,
        0,
      );
    });
    test('non-expense canonical transaction does not count as Paid', () {
      expect(
        summary([payment(type: TransactionType.income)]).cumulative.paid,
        0,
      );
    });
    test('invalid zero transaction does not count', () {
      expect(summary([payment(amount: 0)]).cumulative.paid, 0);
    });
    test('invalid blank-title transaction does not count', () {
      final row = entry(
        type: TransactionType.expense,
        categoryId: SystemCategoryIds.tithe(bookA),
        title: ' ',
      );
      expect(summary([row]).cumulative.paid, 0);
    });
    test('payment count tracks ordinary matching transactions', () {
      expect(
        summary([payment(), payment(id: 'two')]).cumulative.paymentCount,
        2,
      );
    });
    test('recent payments are newest first', () {
      final result = summary([
        payment(id: 'old', date: DateTime(2026, 1, 1)),
        payment(id: 'new', date: DateTime(2026, 2, 1)),
      ]);
      expect(result.recentPayments.map((item) => item.id), ['new', 'old']);
    });
    test('recent payment list is bounded', () {
      final result = summary([
        payment(id: 'one'),
        payment(id: 'two'),
      ], limit: 1);
      expect(result.recentPayments, hasLength(1));
    });
    test('year to date excludes prior year', () {
      final result = summary([
        entry(amount: 1000, date: DateTime(2025, 12, 1)),
        entry(amount: 1000, date: DateTime(2026, 1, 1)),
      ]);
      expect(result.yearToDate.due, 130);
      expect(result.cumulative.due, 260);
    });
    test('payment amount edit recomputes Paid', () {
      final original = payment(amount: 100);
      expect(summary([original.copyWith(amount: 250)]).cumulative.paid, 250);
    });
    test('payment date edit recomputes its period', () {
      final original = payment(date: DateTime(2026, 1, 1));
      final result = summary([original.copyWith(date: DateTime(2026, 2, 1))]);
      expect(result.currentMonth.paid, 100);
    });
    test('category edit away from canonical removes Paid', () {
      expect(
        summary([payment().copyWith(categoryId: 'other')]).cumulative.paid,
        0,
      );
    });
    test('category edit into canonical adds Paid', () {
      final original = entry(
        type: TransactionType.expense,
        categoryId: 'other',
      );
      expect(
        summary([
          original.copyWith(categoryId: SystemCategoryIds.tithe(bookA)),
        ]).cumulative.paid,
        1000,
      );
    });
    test('other household canonical ID does not count', () {
      expect(summary([payment(bookId: bookB)]).cumulative.paid, 0);
    });

    test('base-currency summary excludes a foreign-currency account', () {
      final result = summary(
        [
          entry(amount: 10000),
          entry(id: 'usd-income', amount: 10000, account: 'USD Wallet'),
        ],
        accountCurrencyByName: const {'Cash': 'IDR', 'USD Wallet': 'USD'},
      );
      expect(result.cumulative.due, 1300);
    });
    test('policy transition uses each month effective rate', () {
      final result = summary([
        entry(amount: 1000, date: DateTime(2026, 12, 1)),
        entry(amount: 1000, date: DateTime(2027, 1, 1)),
      ], asOf: DateTime(2027, 1, 20));
      expect(result.cumulative.due, 280);
    });
    test('forPeriod monthly matches current policy calculation', () {
      final result = TitheSummaryCalculator().forPeriod(
        bookId: bookA,
        transactions: [entry(amount: 10000)],
        transferLinks: const [],
        start: DateTime(2026, 1),
        endExclusive: DateTime(2026, 2),
      );
      expect(result.due, 1300);
    });
  });
}
