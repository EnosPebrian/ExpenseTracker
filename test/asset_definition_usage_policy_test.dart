import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_definition_usage_policy.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_portfolio_calculator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';

void main() {
  const policy = AssetDefinitionUsagePolicy();

  group('AssetDefinitionUsagePolicy usage', () {
    test('unused definition can archive and edit identity', () {
      final result = policy.analyze(
        definition: _definition(),
        transactions: const [],
      );

      expect(result.hasLinkedTransactions, isFalse);
      expect(result.openQuantity, 0);
      expect(result.canArchive, isTrue);
      expect(result.canEditIdentity, isTrue);
    });

    test('linked open position blocks archive', () {
      final result = policy.analyze(
        definition: _definition(),
        transactions: [_assetTransaction(quantity: 500)],
      );

      expect(result.linkedTransactionCount, 1);
      expect(result.activeTransactionCount, 1);
      expect(result.openQuantity, 500);
      expect(result.hasOpenPosition, isTrue);
      expect(result.canArchive, isFalse);
      expect(result.canEditIdentity, isFalse);
    });

    test('fully sold historical position can archive', () {
      final result = policy.analyze(
        definition: _definition(),
        transactions: [
          _assetTransaction(id: 'buy', quantity: 500),
          _assetTransaction(
            id: 'sell',
            quantity: 500,
            action: AssetAction.sell,
          ),
        ],
      );

      expect(result.hasLinkedTransactions, isTrue);
      expect(result.openQuantity, 0);
      expect(result.hasOpenPosition, isFalse);
      expect(result.canArchive, isTrue);
      expect(result.canEditIdentity, isFalse);
    });

    test(
      'fully sold position retains realized gain after definition archive',
      () {
        final definition = _definition(deletedAt: DateTime.utc(2026, 7, 25));
        final buy = _assetTransaction(
          id: 'buy',
          quantity: 500,
          definition: definition,
        );
        final sell = _assetTransaction(
          id: 'sell',
          quantity: 500,
          action: AssetAction.sell,
          definition: definition,
        ).copyWith(amount: 600000, unitPrice: 1200);

        final portfolio = AssetPortfolioCalculator.calculate(
          transactions: [buy, sell],
          assetDefinitions: [definition],
        );

        expect(portfolio.holdings, isEmpty);
        expect(portfolio.totalRealizedGain, 100000);
      },
    );

    test('near-zero floating residue is normalized closed', () {
      final definition = _definition(
        kind: AssetKind.crypto,
        symbol: 'BTC',
        unit: 'coin',
        lotSize: 1,
      );
      final result = policy.analyze(
        definition: definition,
        transactions: [
          _assetTransaction(id: 'buy', quantity: 0.3, definition: definition),
          _assetTransaction(
            id: 'sell',
            quantity: 0.30000000000000004,
            action: AssetAction.sell,
            definition: definition,
          ),
        ],
      );

      expect(result.openQuantity, 0);
      expect(result.canArchive, isTrue);
    });

    test(
      'soft-deleted transactions remain links but do not affect quantity',
      () {
        final result = policy.analyze(
          definition: _definition(),
          transactions: [
            _assetTransaction(
              quantity: 500,
              deletedAt: DateTime.utc(2026, 7, 24),
            ),
          ],
        );

        expect(result.linkedTransactionCount, 1);
        expect(result.activeTransactionCount, 0);
        expect(result.openQuantity, 0);
        expect(result.canArchive, isTrue);
        expect(result.canEditIdentity, isFalse);
      },
    );

    test('linked fee expense is ignored as asset activity', () {
      final fee = Transaction(
        id: 'fee',
        title: 'Broker fee',
        category: 'Fee',
        account: 'Cash',
        date: DateTime.utc(2026, 7, 24),
        amount: 1000,
        type: TransactionType.expense,
        assetDefinitionId: _definition().id,
        relatedTransactionId: 'buy',
        relationType: TransactionRelationType.assetFeeExpense,
      );

      final result = policy.analyze(
        definition: _definition(),
        transactions: [fee],
      );

      expect(result.hasLinkedTransactions, isFalse);
      expect(result.canArchive, isTrue);
    });

    test('separate definitions and legacy snapshots do not falsely link', () {
      final definition = _definition();
      final result = policy.analyze(
        definition: definition,
        transactions: [
          _assetTransaction(definition: _definition(id: 'asset-bbri')),
          _assetTransaction(definition: definition, legacySnapshot: true),
        ],
      );

      expect(result.hasLinkedTransactions, isFalse);
      expect(result.openQuantity, 0);
    });
  });

  group('AssetDefinitionUsagePolicy edit protection', () {
    test('unlinked definition may edit protected fields', () {
      final existing = _definition();
      final usage = policy.analyze(
        definition: existing,
        transactions: const [],
      );
      final result = policy.validateEdit(
        existing: existing,
        candidate: existing.copyWith(symbol: 'BBRI', lotSize: 200),
        usage: usage,
      );

      expect(result.isValid, isTrue);
    });

    test('linked definition allows safe fields and harmless casing', () {
      final existing = _definition();
      final usage = policy.analyze(
        definition: existing,
        transactions: [_assetTransaction()],
      );
      final result = policy.validateEdit(
        existing: existing,
        candidate: existing.copyWith(
          displayName: 'BCA',
          symbol: ' bbca ',
          exchangeCode: ' idx ',
          providerCode: 'manual-provider',
          providerSymbol: 'NEW',
          onlinePricingEnabled: false,
        ),
        usage: usage,
      );

      expect(result.isValid, isTrue);
    });

    test('linked definition blocks every identity and accounting field', () {
      final existing = _definition();
      final usage = policy.analyze(
        definition: existing,
        transactions: [_assetTransaction()],
      );
      final result = policy.validateEdit(
        existing: existing,
        candidate: existing.copyWith(
          kind: AssetKind.inventory,
          symbol: 'BBRI',
          exchangeCode: 'NYSE',
          currencyCode: 'USD',
          unit: 'item',
          lotSize: 1,
        ),
        usage: usage,
      );

      expect(
        result.issues.map((issue) => issue.field),
        containsAll(AssetDefinitionProtectedField.values.skip(1)),
      );
    });

    test('archived definition is read-only', () {
      final existing = _definition(deletedAt: DateTime.utc(2026, 7, 24));
      final usage = policy.analyze(
        definition: existing,
        transactions: const [],
      );
      final result = policy.validateEdit(
        existing: existing,
        candidate: existing.copyWith(displayName: 'Changed'),
        usage: usage,
      );

      expect(result.isValid, isFalse);
      expect(
        result.firstIssue?.message,
        'Restore this asset before editing it.',
      );
    });
  });
}

AssetDefinition _definition({
  String id = 'asset-bbca',
  AssetKind kind = AssetKind.stock,
  String? symbol = 'BBCA',
  String unit = 'share',
  int lotSize = 100,
  DateTime? deletedAt,
}) {
  final timestamp = DateTime.utc(2026, 7, 24);
  return AssetDefinition(
    id: id,
    displayName: symbol ?? 'Asset',
    kind: kind,
    symbol: symbol,
    providerCode: 'alpha_vantage',
    providerSymbol: symbol,
    exchangeCode: kind == AssetKind.stock ? 'IDX' : null,
    currencyCode: 'IDR',
    unit: unit,
    lotSize: lotSize,
    onlinePricingEnabled: true,
    createdAt: timestamp,
    updatedAt: timestamp,
    deletedAt: deletedAt,
    version: 1,
    deviceId: 'test-device',
    syncStatus: 'local_only',
  );
}

Transaction _assetTransaction({
  String id = 'transaction',
  double quantity = 100,
  AssetAction action = AssetAction.buy,
  AssetDefinition? definition,
  DateTime? deletedAt,
  bool legacySnapshot = false,
}) {
  final asset = definition ?? _definition();
  return Transaction(
    id: id,
    title: '${action.name} ${asset.displayName}',
    category: 'Asset conversion',
    account: 'Cash -> ${asset.displayName}',
    date: DateTime.utc(2026, 7, 24),
    amount: (quantity * 1000).round(),
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: asset.unit,
    unitPrice: 1000,
    assetDefinitionId: legacySnapshot ? null : asset.id,
    assetName: asset.displayName,
    assetSymbol: asset.symbol,
    assetAction: action,
    deletedAt: deletedAt,
  );
}
