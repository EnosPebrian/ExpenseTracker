import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pilgrim_tracker/features/assets/data/repositories/alpha_vantage_asset_price_repository.dart';

void main() {
  test('parses a stock quote into integer money', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['function'], 'GLOBAL_QUOTE');

      expect(request.url.queryParameters['symbol'], 'BBCA');

      return http.Response('''
        {
          "Global Quote": {
            "01. symbol": "BBCA",
            "05. price": "9250.0000",
            "07. latest trading day": "2026-07-21"
          }
        }
        ''', 200);
    });

    final repository = AlphaVantageAssetPriceRepository(
      apiKey: 'test-key',
      client: client,
    );

    final quote = await repository.fetchStockQuote(
      symbol: 'BBCA',
      currencyCode: 'IDR',
      minorUnitScale: 1,
    );

    expect(quote.symbol, 'BBCA');
    expect(quote.priceMinor, 9250);
    expect(quote.minorUnitScale, 1);
    expect(quote.currencyCode, 'IDR');
    expect(quote.unit, 'share');
    expect(quote.isDelayed, isTrue);
  });

  test('parses and sorts symbol search results', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['function'], 'SYMBOL_SEARCH');

      return http.Response('''
        {
          "bestMatches": [
            {
              "1. symbol": "AAA",
              "2. name": "Lower Match",
              "3. type": "Equity",
              "4. region": "Test",
              "8. currency": "IDR",
              "9. matchScore": "0.5000"
            },
            {
              "1. symbol": "BBB",
              "2. name": "Higher Match",
              "3. type": "Equity",
              "4. region": "Test",
              "8. currency": "IDR",
              "9. matchScore": "0.9000"
            }
          ]
        }
        ''', 200);
    });

    final repository = AlphaVantageAssetPriceRepository(
      apiKey: 'test-key',
      client: client,
    );

    final matches = await repository.searchStockSymbols('bank');

    expect(matches, hasLength(2));
    expect(matches.first.symbol, 'BBB');
    expect(matches.first.currencyCode, 'IDR');
    expect(matches.first.matchScore, 0.9);
  });

  test('converts gold USD per ounce into IDR per gram', () async {
    final client = MockClient((request) async {
      final function = request.url.queryParameters['function'];

      switch (function) {
        case 'GOLD_SILVER_SPOT':
          return http.Response('''
            {
              "symbol": "GOLD",
              "price": "2000.00",
              "timestamp": "2026-07-21T10:00:00Z"
            }
            ''', 200);

        case 'CURRENCY_EXCHANGE_RATE':
          expect(request.url.queryParameters['from_currency'], 'USD');

          expect(request.url.queryParameters['to_currency'], 'IDR');

          return http.Response('''
            {
              "Realtime Currency Exchange Rate": {
                "5. Exchange Rate": "16000.00",
                "6. Last Refreshed": "2026-07-21 10:00:00"
              }
            }
            ''', 200);

        default:
          return http.Response('Not found', 404);
      }
    });

    final repository = AlphaVantageAssetPriceRepository(
      apiKey: 'test-key',
      client: client,
    );

    final quote = await repository.fetchGoldPriceInIdrPerGram();

    expect(quote.symbol, 'XAU');
    expect(quote.currencyCode, 'IDR');
    expect(quote.unit, 'gram');
    expect(quote.minorUnitScale, 1);
    expect(quote.priceMinor, 1028824);
  });

  test('turns provider information responses into exceptions', () async {
    final client = MockClient((request) async {
      return http.Response('''
        {
          "Information": "API request limit reached."
        }
        ''', 200);
    });

    final repository = AlphaVantageAssetPriceRepository(
      apiKey: 'test-key',
      client: client,
    );

    expect(
      () => repository.fetchStockQuote(
        symbol: 'BBCA',
        currencyCode: 'IDR',
        minorUnitScale: 1,
      ),
      throwsA(isA<AssetPriceException>()),
    );
  });
}
