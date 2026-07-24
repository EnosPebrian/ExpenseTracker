import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_trade_validator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

const validator = AssetTradeValidator();

void main() {
  test('backdated sale uses only shares available on its date', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        _trade('early', DateTime(2026, 7, 1), 250, AssetAction.buy),
        _trade('future', DateTime(2026, 7, 10), 250, AssetAction.buy),
      ],
      candidate: _trade('sale', DateTime(2026, 7, 5), 150, AssetAction.sell),
      definition: _bbca,
    );
    expect(result.isValid, isTrue);
    expect(result.sequenceValidation.availableQuantity, 250);
    expect(result.lotValidation!.isOddLotCleanup, isTrue);
    expect(result.lotValidation!.remainingShares, 100);
  });

  test('definition identity isolates available shares', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        _trade('other', DateTime(2026, 7, 1), 500, AssetAction.buy).copyWith(
          assetDefinitionId: 'asset-bbri',
          assetName: 'Bank Rakyat Indonesia',
          assetSymbol: 'BBRI',
        ),
      ],
      candidate: _trade('sale', DateTime(2026, 7, 2), 100, AssetAction.sell),
      definition: _bbca,
    );
    expect(result.isValid, isFalse);
    expect(result.sequenceValidation.availableQuantity, 0);
  });

  test('oversell remains independently blocked when lot is valid', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        _trade('buy', DateTime(2026, 7, 1), 250, AssetAction.buy),
      ],
      candidate: _trade('sale', DateTime(2026, 7, 2), 300, AssetAction.sell),
      definition: _bbca,
    );
    expect(result.lotValidation!.isValid, isTrue);
    expect(result.sequenceValidation.isValid, isFalse);
    expect(result.isValid, isFalse);
  });

  test('editing excludes the original sale before lot cleanup', () {
    final original = _trade(
      'sale',
      DateTime(2026, 7, 2),
      100,
      AssetAction.sell,
    );
    final result = validator.validateCandidate(
      existingTransactions: [
        _trade('buy', DateTime(2026, 7, 1), 250, AssetAction.buy),
        original,
      ],
      candidate: original.copyWith(quantity: 150.0),
      replacedTransactionId: original.id,
      definition: _bbca,
    );
    expect(result.isValid, isTrue);
    expect(result.sequenceValidation.availableQuantity, 250);
  });

  test('new stock transaction requires an active matching definition', () {
    final candidate = _trade('buy', DateTime(2026, 7, 1), 100, AssetAction.buy);
    expect(
      validator
          .validateCandidate(
            existingTransactions: const [],
            candidate: candidate,
          )
          .message,
      contains('could not be found'),
    );
    expect(
      validator
          .validateCandidate(
            existingTransactions: const [],
            candidate: candidate,
            definition: _bbca.copyWith(deletedAt: DateTime.utc(2026, 7, 1)),
          )
          .message,
      contains('no longer active'),
    );
  });
}

Transaction _trade(
  String id,
  DateTime date,
  double quantity,
  AssetAction action,
) => Transaction(
  id: id,
  title: 'BBCA trade',
  category: 'Asset conversion',
  account: action == AssetAction.buy ? 'Cash -> BBCA' : 'BBCA -> Cash',
  date: date,
  amount: (quantity * 10000).round(),
  type: TransactionType.assetConversion,
  quantity: quantity,
  unit: 'share',
  unitPrice: 10000,
  assetDefinitionId: 'asset-bbca',
  assetName: 'Bank Central Asia',
  assetSymbol: 'BBCA',
  assetAction: action,
  createdAt: date,
  updatedAt: date,
);

final _bbca = AssetDefinition(
  id: 'asset-bbca',
  displayName: 'Bank Central Asia',
  kind: AssetKind.stock,
  symbol: 'BBCA',
  providerCode: null,
  providerSymbol: null,
  exchangeCode: 'IDX',
  currencyCode: 'IDR',
  unit: 'share',
  lotSize: 100,
  onlinePricingEnabled: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'test',
  syncStatus: 'local_only',
);
