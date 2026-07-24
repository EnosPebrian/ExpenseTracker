import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_definition_integrity_policy.dart';

void main() {
  const policy = AssetDefinitionIntegrityPolicy();

  group('AssetDefinitionIntegrityPolicy stock identity', () {
    test('accepts unique stocks and distinct explicit exchanges', () {
      final bbca = _definition(id: 'bbca', symbol: 'BBCA', exchange: 'IDX');

      expect(
        policy
            .validate(
              candidate: _definition(
                id: 'aapl',
                name: 'Apple',
                symbol: 'AAPL',
                exchange: 'NASDAQ',
                providerSymbol: 'AAPL',
              ),
              existingDefinitions: [bbca],
            )
            .isValid,
        isTrue,
      );
      expect(
        policy
            .validate(
              candidate: _definition(
                id: 'abc-lse',
                symbol: 'ABC',
                exchange: 'LSE',
                providerSymbol: 'ABC.LSE',
              ),
              existingDefinitions: [
                _definition(
                  id: 'abc-nyse',
                  symbol: 'ABC',
                  exchange: 'NYSE',
                  providerSymbol: 'ABC.NYSE',
                ),
              ],
            )
            .isValid,
        isTrue,
      );
    });

    test('blocks normalized symbol and exchange duplicates', () {
      final existing = _definition(
        id: 'bbca',
        symbol: ' BBCA ',
        exchange: ' idx ',
      );
      final result = policy.validate(
        candidate: _definition(
          id: 'duplicate',
          symbol: 'bbca',
          exchange: 'IDX',
          providerSymbol: 'OTHER',
        ),
        existingDefinitions: [existing],
      );

      expect(result.isValid, isFalse);
      expect(
        result.firstIssue?.code,
        AssetDefinitionIntegrityCode.stockIdentityConflict,
      );
      expect(result.firstIssue?.conflictingDefinitionId, 'bbca');
    });

    test('missing exchange cannot bypass a matching stock symbol', () {
      final result = policy.validate(
        candidate: _definition(
          id: 'duplicate',
          exchange: null,
          providerSymbol: 'OTHER',
        ),
        existingDefinitions: [_definition(id: 'bbca', exchange: 'IDX')],
      );

      expect(
        result.issues.map((issue) => issue.code),
        contains(AssetDefinitionIntegrityCode.stockIdentityConflict),
      );
    });

    test('editing excludes the definition own ID', () {
      final definition = _definition(id: 'bbca');
      final result = policy.validate(
        candidate: definition.copyWith(displayName: 'BBCA edited'),
        existingDefinitions: [definition],
        editingDefinitionId: definition.id,
      );

      expect(result.isValid, isTrue);
    });

    test('reports an archived stock conflict', () {
      final result = policy.validate(
        candidate: _definition(id: 'new-bbca', providerSymbol: 'OTHER'),
        existingDefinitions: [
          _definition(id: 'old-bbca', deletedAt: DateTime.utc(2026)),
        ],
      );

      expect(result.firstIssue?.message, contains('archived'));
      expect(result.firstIssue?.message, contains('Restore or edit'));
    });
  });

  group('AssetDefinitionIntegrityPolicy provider identity', () {
    test('blocks normalized provider identity across asset kinds', () {
      final result = policy.validate(
        candidate: _definition(
          id: 'crypto',
          name: 'Crypto alias',
          kind: AssetKind.crypto,
          symbol: 'BTC',
          exchange: null,
          providerCode: ' alpha_vantage ',
          providerSymbol: ' bbca.jk ',
          unit: 'coin',
          lotSize: 1,
        ),
        existingDefinitions: [_definition(id: 'bbca')],
      );

      expect(
        result.issues.map((issue) => issue.code),
        contains(AssetDefinitionIntegrityCode.providerIdentityConflict),
      );
    });

    test('reports an archived provider conflict', () {
      final result = policy.validate(
        candidate: _definition(id: 'duplicate', symbol: 'BBRI'),
        existingDefinitions: [
          _definition(id: 'archived', deletedAt: DateTime.utc(2026)),
        ],
      );

      expect(
        result.errorFor(AssetDefinitionIntegrityField.providerSymbol),
        contains('Archived asset'),
      );
    });

    test('online pricing requires provider code and symbol', () {
      final result = policy.validate(
        candidate: _definition(
          id: 'missing-provider',
          online: true,
          providerCode: null,
          providerSymbol: null,
        ),
        existingDefinitions: const [],
      );

      expect(
        result.errorFor(AssetDefinitionIntegrityField.providerCode),
        isNotNull,
      );
      expect(
        result.errorFor(AssetDefinitionIntegrityField.providerSymbol),
        isNotNull,
      );
    });

    test('disabled online pricing retains optional provider fields', () {
      final candidate = _definition(
        id: 'offline',
        online: false,
        providerCode: 'alpha_vantage',
        providerSymbol: 'BBCA.JK',
      );
      final result = policy.validate(
        candidate: candidate,
        existingDefinitions: const [],
      );

      expect(result.isValid, isTrue);
      expect(candidate.providerCode, 'alpha_vantage');
      expect(candidate.providerSymbol, 'BBCA.JK');
    });
  });

  group('AssetDefinitionIntegrityPolicy non-stock identity', () {
    test('same display name across unrelated kinds does not conflict', () {
      final result = policy.validate(
        candidate: _definition(
          id: 'other-cash',
          name: 'Reserve',
          kind: AssetKind.other,
          symbol: null,
          exchange: null,
          providerCode: null,
          providerSymbol: null,
          unit: 'unit',
          lotSize: 1,
          online: false,
        ),
        existingDefinitions: [
          _definition(
            id: 'inventory-reserve',
            name: 'Reserve',
            kind: AssetKind.inventory,
            symbol: null,
            exchange: null,
            providerCode: null,
            providerSymbol: null,
            unit: 'item',
            lotSize: 1,
            online: false,
          ),
        ],
      );

      expect(result.isValid, isTrue);
    });

    test('USD and SGD remain distinct', () {
      final usd = _foreignCurrency(id: 'usd', symbol: 'USD');
      final result = policy.validate(
        candidate: _foreignCurrency(id: 'sgd', symbol: 'SGD'),
        existingDefinitions: [usd],
      );

      expect(result.isValid, isTrue);
    });

    test('rejects an incompatible foreign-currency provider pair', () {
      final result = policy.validate(
        candidate: _foreignCurrency(
          id: 'usd',
          symbol: 'USD',
          providerSymbol: 'SGD/IDR',
        ),
        existingDefinitions: const [],
      );

      expect(
        result.errorFor(AssetDefinitionIntegrityField.providerSymbol),
        'Provider pair must be USD/IDR.',
      );
    });
  });
}

AssetDefinition _definition({
  required String id,
  String name = 'Bank Central Asia',
  AssetKind kind = AssetKind.stock,
  String? symbol = 'BBCA',
  String? providerCode = 'alpha_vantage',
  String? providerSymbol = 'BBCA.JK',
  String? exchange = 'IDX',
  String currency = 'IDR',
  String unit = 'share',
  int lotSize = 100,
  bool online = true,
  DateTime? deletedAt,
}) {
  final timestamp = DateTime.utc(2026, 7, 24);
  return AssetDefinition(
    id: id,
    displayName: name,
    kind: kind,
    symbol: symbol,
    providerCode: providerCode,
    providerSymbol: providerSymbol,
    exchangeCode: exchange,
    currencyCode: currency,
    unit: unit,
    lotSize: lotSize,
    onlinePricingEnabled: online,
    createdAt: timestamp,
    updatedAt: timestamp,
    deletedAt: deletedAt,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}

AssetDefinition _foreignCurrency({
  required String id,
  required String symbol,
  String? providerSymbol,
}) {
  return _definition(
    id: id,
    name: '$symbol Cash',
    kind: AssetKind.foreignCurrency,
    symbol: symbol,
    providerSymbol: providerSymbol ?? '$symbol/IDR',
    exchange: null,
    unit: symbol.toLowerCase(),
    lotSize: 1,
  );
}
