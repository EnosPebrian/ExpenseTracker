import '../../../core/master_data/system_category.dart';
import '../../transactions/domain/entities/internal_transfer_link.dart';
import '../../transactions/domain/entities/transaction.dart';
import 'tithe_policy.dart';

class TithePeriodSummary {
  const TithePeriodSummary({
    required this.due,
    required this.paid,
    required this.paymentCount,
  });

  final int due;
  final int paid;
  final int paymentCount;

  int get balance => due - paid;
  bool get isOutstanding => balance > 0;
  bool get isAdvance => balance < 0;
}

class TitheSummary {
  TitheSummary({
    required this.bookId,
    required this.currencyCode,
    required this.asOf,
    required this.currentMonth,
    required this.yearToDate,
    required this.cumulative,
    required List<Transaction> recentPayments,
  }) : recentPayments = List.unmodifiable(recentPayments);

  final String bookId;
  final String currencyCode;
  final DateTime asOf;
  final TithePeriodSummary currentMonth;
  final TithePeriodSummary yearToDate;
  final TithePeriodSummary cumulative;
  final List<Transaction> recentPayments;
}

class TitheSummaryCalculator {
  TitheSummaryCalculator({TithePolicy? policy})
    : policy = policy ?? TithePolicy.defaultPolicy;

  final TithePolicy policy;

  TitheSummary calculate({
    required String bookId,
    required String currencyCode,
    required Iterable<Transaction> transactions,
    required Iterable<InternalTransferLink> transferLinks,
    required DateTime asOf,
    Map<String, String>? accountCurrencyByName,
    int recentPaymentLimit = 8,
  }) {
    final monthStart = DateTime(asOf.year, asOf.month);
    final nextMonth = DateTime(asOf.year, asOf.month + 1);
    final yearStart = DateTime(asOf.year);
    final nextYear = DateTime(asOf.year + 1);
    final pairedIds = {
      for (final link in transferLinks)
        if (link.deletedAt == null) ...link.transactionIds,
    };
    final live = transactions
        .where((transaction) => transaction.deletedAt == null)
        .where((transaction) => transaction.bookId == bookId)
        .where((transaction) => !pairedIds.contains(transaction.id))
        .where(
          (transaction) =>
              accountCurrencyByName == null ||
              (accountCurrencyByName[transaction.account] ?? currencyCode) ==
                  currencyCode,
        )
        .where(_isValidFinancialRecord)
        .toList(growable: false);
    final paymentId = SystemCategoryIds.tryTithe(bookId);
    final payments =
        live
            .where(
              (transaction) =>
                  paymentId != null &&
                  transaction.type == TransactionType.expense &&
                  transaction.categoryId == paymentId,
            )
            .toList()
          ..sort((left, right) => right.date.compareTo(left.date));

    TithePeriodSummary summarize(DateTime? start, DateTime end) {
      final scoped = live.where(
        (transaction) =>
            (start == null || !transaction.date.isBefore(start)) &&
            transaction.date.isBefore(end),
      );
      final incomeByMonth = <(int, int), int>{};
      for (final transaction in scoped) {
        if (transaction.type != TransactionType.income) continue;
        final key = (transaction.date.year, transaction.date.month);
        incomeByMonth[key] = (incomeByMonth[key] ?? 0) + transaction.amount;
      }
      final due = incomeByMonth.entries.fold<int>(0, (total, entry) {
        final month = DateTime(entry.key.$1, entry.key.$2);
        return total + (entry.value * policy.rateFor(month)).round();
      });
      final periodPayments = payments.where(
        (transaction) =>
            (start == null || !transaction.date.isBefore(start)) &&
            transaction.date.isBefore(end),
      );
      return TithePeriodSummary(
        due: due,
        paid: periodPayments.fold(0, (total, item) => total + item.amount),
        paymentCount: periodPayments.length,
      );
    }

    return TitheSummary(
      bookId: bookId,
      currencyCode: currencyCode,
      asOf: asOf,
      currentMonth: summarize(monthStart, nextMonth),
      yearToDate: summarize(yearStart, nextYear),
      cumulative: summarize(null, nextMonth),
      recentPayments: payments.take(recentPaymentLimit).toList(),
    );
  }

  TithePeriodSummary forPeriod({
    required String bookId,
    required Iterable<Transaction> transactions,
    required Iterable<InternalTransferLink> transferLinks,
    required DateTime start,
    required DateTime endExclusive,
  }) {
    final summary = calculate(
      bookId: bookId,
      currencyCode: '',
      transactions: transactions,
      transferLinks: transferLinks,
      asOf: endExclusive.subtract(const Duration(days: 1)),
      recentPaymentLimit: 0,
    );
    // Annual callers use the YTD aggregate; monthly callers use current month.
    return start.month == 1 && endExclusive.year == start.year + 1
        ? summary.yearToDate
        : summary.currentMonth;
  }

  static bool _isValidFinancialRecord(Transaction transaction) =>
      transaction.amount > 0 &&
      transaction.title.trim().isNotEmpty &&
      transaction.account.trim().isNotEmpty;
}
