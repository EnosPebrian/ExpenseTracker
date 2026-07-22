import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/asset_symbol_match.dart';
import '../../domain/entities/market_quote.dart';
import '../../domain/repositories/asset_price_repository.dart';

class AssetPriceException implements Exception {
  const AssetPriceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AlphaVantageAssetPriceRepository implements AssetPriceRepository {
  AlphaVantageAssetPriceRepository({
    required String apiKey,
    http.Client? client,
  }) : apiKey = apiKey.trim(),
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (this.apiKey.isEmpty) {
      throw ArgumentError.value(
        apiKey,
        'apiKey',
        'An Alpha Vantage API key is required.',
      );
    }
  }

  static const String _host = 'www.alphavantage.co';
  static const String _path = '/query';

  /// Number of grams in one troy ounce.
  static const double _gramsPerTroyOunce = 31.1034768;

  final String apiKey;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<MarketQuote> fetchStockQuote({
    required String symbol,
    required String currencyCode,
    required int minorUnitScale,
  }) async {
    final normalizedSymbol = symbol.trim().toUpperCase();
    final normalizedCurrency = currencyCode.trim().toUpperCase();

    if (normalizedSymbol.isEmpty) {
      throw ArgumentError.value(
        symbol,
        'symbol',
        'A stock symbol is required.',
      );
    }

    if (normalizedCurrency.isEmpty) {
      throw ArgumentError.value(
        currencyCode,
        'currencyCode',
        'A currency code is required.',
      );
    }

    if (minorUnitScale <= 0) {
      throw ArgumentError.value(
        minorUnitScale,
        'minorUnitScale',
        'The minor-unit scale must be positive.',
      );
    }

    final data = await _query({
      'function': 'GLOBAL_QUOTE',
      'symbol': normalizedSymbol,
    });

    final quote = _asStringMap(data['Global Quote']);

    if (quote == null || quote.isEmpty) {
      throw const AssetPriceException(
        'The stock quote response did not contain a Global Quote.',
      );
    }

    final price = _requiredDouble(quote['05. price'], fieldName: 'stock price');

    if (price <= 0) {
      throw const AssetPriceException(
        'The stock quote returned a non-positive price.',
      );
    }

    final responseSymbol = quote['01. symbol']?.toString().trim().toUpperCase();

    final latestTradingDay = _parseDate(quote['07. latest trading day']);

    return MarketQuote(
      symbol: responseSymbol == null || responseSymbol.isEmpty
          ? normalizedSymbol
          : responseSymbol,
      priceMinor: (price * minorUnitScale).round(),
      minorUnitScale: minorUnitScale,
      currencyCode: normalizedCurrency,
      unit: 'share',
      quotedAt: latestTradingDay ?? DateTime.now().toUtc(),
      source: 'Alpha Vantage',
      // The basic GLOBAL_QUOTE response should not be presented as guaranteed
      // realtime market data.
      isDelayed: true,
    );
  }

  @override
  Future<List<AssetSymbolMatch>> searchStockSymbols(String keywords) async {
    final normalizedKeywords = keywords.trim();

    if (normalizedKeywords.isEmpty) {
      return const [];
    }

    final data = await _query({
      'function': 'SYMBOL_SEARCH',
      'keywords': normalizedKeywords,
    });

    final rawMatches = data['bestMatches'];

    if (rawMatches is! List) {
      return const [];
    }

    final matches = <AssetSymbolMatch>[];

    for (final rawMatch in rawMatches) {
      final match = _asStringMap(rawMatch);

      if (match == null) {
        continue;
      }

      final symbol = match['1. symbol']?.toString().trim() ?? '';
      final name = match['2. name']?.toString().trim() ?? '';

      if (symbol.isEmpty || name.isEmpty) {
        continue;
      }

      matches.add(
        AssetSymbolMatch(
          symbol: symbol,
          name: name,
          type: match['3. type']?.toString().trim() ?? 'Unknown',
          region: match['4. region']?.toString().trim() ?? 'Unknown',
          currencyCode:
              match['8. currency']?.toString().trim().toUpperCase() ?? '',
          matchScore:
              double.tryParse(
                match['9. matchScore']?.toString().trim() ?? '',
              ) ??
              0,
        ),
      );
    }

    matches.sort((left, right) => right.matchScore.compareTo(left.matchScore));

    return List<AssetSymbolMatch>.unmodifiable(matches);
  }

  @override
  Future<MarketQuote> fetchGoldPriceInIdrPerGram() async {
    final goldData = await _query({
      'function': 'GOLD_SILVER_SPOT',
      'symbol': 'GOLD',
    });

    final goldUsdPerTroyOunce = _extractGoldSpotPrice(goldData);

    if (goldUsdPerTroyOunce <= 0) {
      throw const AssetPriceException(
        'The gold endpoint returned a non-positive spot price.',
      );
    }

    final exchangeData = await _query({
      'function': 'CURRENCY_EXCHANGE_RATE',
      'from_currency': 'USD',
      'to_currency': 'IDR',
    });

    final exchangeRateContainer = _asStringMap(
      exchangeData['Realtime Currency Exchange Rate'],
    );

    if (exchangeRateContainer == null) {
      throw const AssetPriceException(
        'The exchange-rate response did not contain the expected data.',
      );
    }

    final usdToIdr = _requiredDouble(
      exchangeRateContainer['5. Exchange Rate'],
      fieldName: 'USD to IDR exchange rate',
    );

    if (usdToIdr <= 0) {
      throw const AssetPriceException(
        'The USD to IDR exchange rate was not positive.',
      );
    }

    final idrPerGram = (goldUsdPerTroyOunce * usdToIdr / _gramsPerTroyOunce)
        .round();

    final quotedAt =
        _extractDate(goldData) ??
        _parseDate(exchangeRateContainer['6. Last Refreshed']) ??
        DateTime.now().toUtc();

    return MarketQuote(
      symbol: 'XAU',
      priceMinor: idrPerGram,
      minorUnitScale: 1,
      currencyCode: 'IDR',
      unit: 'gram',
      quotedAt: quotedAt,
      source: 'Alpha Vantage spot + USD/IDR',
      isDelayed: false,
    );
  }

  Future<Map<String, dynamic>> _query(Map<String, String> parameters) async {
    final uri = Uri.https(_host, _path, {...parameters, 'apikey': apiKey});

    late final http.Response response;

    try {
      response = await _client.get(uri);
    } on Exception catch (exception) {
      throw AssetPriceException(
        'Could not contact the market-data provider: $exception',
      );
    }

    if (response.statusCode != 200) {
      throw AssetPriceException(
        'Market-data request failed with HTTP '
        '${response.statusCode}.',
      );
    }

    late final Object? decoded;

    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const AssetPriceException(
        'The market-data provider returned invalid JSON.',
      );
    }

    if (decoded is! Map) {
      throw const AssetPriceException(
        'The market-data provider returned an unexpected response.',
      );
    }

    final data = Map<String, dynamic>.from(decoded);

    _throwIfApiError(data);

    return data;
  }

  void _throwIfApiError(Map<String, dynamic> data) {
    for (final key in const ['Error Message', 'Information', 'Note']) {
      final message = data[key]?.toString().trim();

      if (message != null && message.isNotEmpty) {
        throw AssetPriceException(message);
      }
    }
  }

  double _extractGoldSpotPrice(Map<String, dynamic> data) {
    final directPrice = _findNumericValue(data, const {
      'price',
      'spotprice',
      'goldprice',
      'lastprice',
      'value',
    });

    if (directPrice != null) {
      return directPrice;
    }

    final bid = _findNumericValue(data, const {'bid', 'bidprice'});

    final ask = _findNumericValue(data, const {'ask', 'askprice'});

    if (bid != null && ask != null) {
      return (bid + ask) / 2;
    }

    throw const AssetPriceException(
      'The gold response did not contain a recognizable spot price.',
    );
  }

  DateTime? _extractDate(Map<String, dynamic> data) {
    for (final map in _allMaps(data)) {
      for (final entry in map.entries) {
        final normalizedKey = _normalizeKey(entry.key);

        if (const {
          'timestamp',
          'lastupdated',
          'updatedat',
          'lastrefreshed',
          'date',
        }.contains(normalizedKey)) {
          final parsed = _parseDate(entry.value);

          if (parsed != null) {
            return parsed;
          }
        }
      }
    }

    return null;
  }

  double? _findNumericValue(
    Map<String, dynamic> data,
    Set<String> acceptedKeys,
  ) {
    for (final map in _allMaps(data)) {
      for (final entry in map.entries) {
        final normalizedKey = _normalizeKey(entry.key);

        if (!acceptedKeys.contains(normalizedKey)) {
          continue;
        }

        final parsed = double.tryParse(
          entry.value?.toString().replaceAll(',', '').trim() ?? '',
        );

        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  Iterable<Map<String, dynamic>> _allMaps(Map<String, dynamic> root) sync* {
    yield root;

    for (final value in root.values) {
      if (value is Map) {
        final nested = Map<String, dynamic>.from(value);

        yield* _allMaps(nested);
      } else if (value is List) {
        for (final item in value) {
          if (item is Map) {
            yield* _allMaps(Map<String, dynamic>.from(item));
          }
        }
      }
    }
  }

  String _normalizeKey(String value) {
    return value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  }

  Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(value);
  }

  double _requiredDouble(Object? value, {required String fieldName}) {
    final parsed = double.tryParse(
      value?.toString().replaceAll(',', '').trim() ?? '',
    );

    if (parsed == null) {
      throw AssetPriceException(
        'The provider response did not contain a valid $fieldName.',
      );
    }

    return parsed;
  }

  DateTime? _parseDate(Object? value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text)?.toUtc();
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
