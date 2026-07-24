import '../entities/asset_symbol_match.dart';
import '../entities/market_quote.dart';

abstract interface class AssetPriceRepository {
  /// Fetches the latest available price for one stock symbol.
  ///
  /// [minorUnitScale] should normally be:
  ///
  /// - 1 for IDR
  /// - 100 for USD
  Future<MarketQuote> fetchStockQuote({
    required String symbol,
    required String currencyCode,
    required int minorUnitScale,
  });

  /// Fetches international gold spot price and converts it to IDR per gram.
  Future<MarketQuote> fetchGoldPriceInIdrPerGram();

  /// Searches the provider's supported stock symbols.
  Future<List<AssetSymbolMatch>> searchStockSymbols(String keywords);
}
