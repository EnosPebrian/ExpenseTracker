import '../../../assets/domain/entities/asset_definition.dart';
import '../../../assets/domain/entities/asset_market_price.dart';
import '../../../assets/domain/services/asset_portfolio_calculator.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../master_data/domain/services/account_balance_calculator.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../entities/brokerage_performance.dart';

class BrokeragePerformanceCalculator {
  const BrokeragePerformanceCalculator._();

  static BrokeragePerformance calculate({
    required Iterable<Account> accounts,
    required Iterable<Transaction> transactions,
    Iterable<AssetDefinition> assetDefinitions = const [],
    Iterable<AssetMarketPrice> marketPrices = const [],
  }) {
    final liveTransactions = transactions
        .where((transaction) => transaction.deletedAt == null)
        .toList(growable: false);
    final brokerageAccounts = accounts
        .where(
          (account) =>
              account.deletedAt == null &&
              account.accountType == AccountType.brokerage,
        )
        .toList(growable: false);
    final accountResults = <BrokerageAccountPerformance>[];
    for (final account in brokerageAccounts) {
      final accountTransactions = liveTransactions
          .where((transaction) => transaction.brokerageAccountId == account.id)
          .toList(growable: false);
      final portfolio = AssetPortfolioCalculator.calculate(
        transactions: accountTransactions,
        assetDefinitions: assetDefinitions,
        marketPrices: marketPrices,
        brokerageAccountId: account.id,
      );
      var dividends = 0;
      var costs = 0;
      for (final transaction in accountTransactions) {
        switch (transaction.brokerageActivityType) {
          case BrokerageActivityType.dividend:
            dividends += transaction.amount;
          case BrokerageActivityType.fee:
          case BrokerageActivityType.tax:
            costs += transaction.amount;
          case BrokerageActivityType.buy:
          case BrokerageActivityType.sell:
          case BrokerageActivityType.deposit:
          case BrokerageActivityType.withdrawal:
          case BrokerageActivityType.split:
          case null:
            break;
        }
      }
      accountResults.add(
        BrokerageAccountPerformance(
          account: account,
          cashBalance: AccountBalanceCalculator.calculate(
            account: account,
            transactions: liveTransactions,
          ),
          portfolio: portfolio,
          dividendIncome: dividends,
          investmentCosts: costs,
        ),
      );
    }

    final currencyResults = <String, _CurrencyAccumulator>{};
    for (final result in accountResults) {
      final currency = result.account.currencyCode;
      final accumulator = currencyResults.putIfAbsent(
        currency,
        _CurrencyAccumulator.new,
      );
      accumulator
        ..cash += result.cashBalance
        ..marketValue += result.portfolio.totalMarketValue
        ..costBasis += result.portfolio.totalCostBasis
        ..realized += result.portfolio.totalRealizedGain
        ..unrealized += result.portfolio.totalUnrealizedGain
        ..dividends += result.dividendIncome
        ..costs += result.investmentCosts;
    }

    final currencies =
        currencyResults.entries
            .map(
              (entry) => BrokerageCurrencyPerformance(
                currencyCode: entry.key,
                cashBalance: entry.value.cash,
                positionMarketValue: entry.value.marketValue,
                positionCostBasis: entry.value.costBasis,
                realizedGain: entry.value.realized,
                unrealizedGain: entry.value.unrealized,
                dividendIncome: entry.value.dividends,
                investmentCosts: entry.value.costs,
              ),
            )
            .toList(growable: false)
          ..sort(
            (left, right) => left.currencyCode.compareTo(right.currencyCode),
          );
    accountResults.sort(
      (left, right) => left.account.name.compareTo(right.account.name),
    );
    return BrokeragePerformance(
      accounts: List.unmodifiable(accountResults),
      currencies: List.unmodifiable(currencies),
    );
  }
}

class _CurrencyAccumulator {
  int cash = 0;
  int marketValue = 0;
  int costBasis = 0;
  int realized = 0;
  int unrealized = 0;
  int dividends = 0;
  int costs = 0;
}
