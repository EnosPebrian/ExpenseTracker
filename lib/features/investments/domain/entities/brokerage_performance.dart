import '../../../assets/domain/entities/asset_portfolio.dart';
import '../../../master_data/domain/entities/account.dart';

class BrokerageAccountPerformance {
  const BrokerageAccountPerformance({
    required this.account,
    required this.cashBalance,
    required this.portfolio,
    required this.dividendIncome,
    required this.investmentCosts,
  });

  final Account account;
  final int cashBalance;
  final AssetPortfolio portfolio;
  final int dividendIncome;
  final int investmentCosts;

  int get realizedPerformance =>
      portfolio.totalRealizedGain + dividendIncome - investmentCosts;
  int get netWorth => cashBalance + portfolio.totalMarketValue;
}

class BrokerageCurrencyPerformance {
  const BrokerageCurrencyPerformance({
    required this.currencyCode,
    required this.cashBalance,
    required this.positionMarketValue,
    required this.positionCostBasis,
    required this.realizedGain,
    required this.unrealizedGain,
    required this.dividendIncome,
    required this.investmentCosts,
  });

  final String currencyCode;
  final int cashBalance;
  final int positionMarketValue;
  final int positionCostBasis;
  final int realizedGain;
  final int unrealizedGain;
  final int dividendIncome;
  final int investmentCosts;

  int get realizedPerformance =>
      realizedGain + dividendIncome - investmentCosts;
  int get netWorth => cashBalance + positionMarketValue;
}

class BrokeragePerformance {
  const BrokeragePerformance({
    required this.accounts,
    required this.currencies,
  });

  final List<BrokerageAccountPerformance> accounts;
  final List<BrokerageCurrencyPerformance> currencies;
}
