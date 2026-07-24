import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_transaction_sequence_validator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

const validator = AssetTransactionSequenceValidator();

Transaction assetTransaction({
  required String id,
  required DateTime date,
  required double quantity,
  required AssetAction action,
  String? definitionId = 'asset-usd',
  String assetName = 'US Dollar Cash',
  String assetSymbol = 'USD',
  String unit = 'usd',
  DateTime? deletedAt,
}) {
  return Transaction(
    id: id,
    title: action == AssetAction.buy ? '$assetSymbol buy' : '$assetSymbol sale',
    category: 'Asset conversion',
    account: action == AssetAction.buy
        ? 'Cash -> $assetName'
        : '$assetName -> Cash',
    date: date,
    amount: (quantity * 16000).round(),
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: unit,
    unitPrice: 16000,
    assetDefinitionId: definitionId,
    assetName: assetName,
    assetSymbol: assetSymbol,
    assetAction: action,
    createdAt: date,
    updatedAt: date,
    deletedAt: deletedAt,
  );
}

void main() {
  final july1 = DateTime(2026, 7, 1);
  final july5 = DateTime(2026, 7, 5);
  final july10 = DateTime(2026, 7, 10);

  test('sale below available quantity is valid', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'buy',
          date: july1,
          quantity: 10,
          action: AssetAction.buy,
        ),
      ],
      candidate: assetTransaction(
        id: 'sale',
        date: july5,
        quantity: 6,
        action: AssetAction.sell,
      ),
    );

    expect(result.isValid, isTrue);
    expect(result.availableQuantity, 10);
    expect(result.requestedQuantity, 6);
  });

  test('sale equal to available quantity fully sells the position', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'buy',
          date: july1,
          quantity: 10,
          action: AssetAction.buy,
        ),
      ],
      candidate: assetTransaction(
        id: 'sale',
        date: july5,
        quantity: 10,
        action: AssetAction.sell,
      ),
    );

    expect(result.isValid, isTrue);
    expect(result.availableQuantity, 10);
    expect(result.shortfall, 0);
  });

  test('sale above available quantity reports availability and shortfall', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'buy',
          date: july1,
          quantity: 1000,
          action: AssetAction.buy,
        ),
      ],
      candidate: assetTransaction(
        id: 'sale',
        date: july5,
        quantity: 1500,
        action: AssetAction.sell,
      ),
    );

    expect(result.isValid, isFalse);
    expect(result.availableQuantity, 1000);
    expect(result.requestedQuantity, 1500);
    expect(result.shortfall, 500);
    expect(result.invalidTransactionId, 'sale');
  });

  test('future buy does not fund a backdated sale', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'early-buy',
          date: july1,
          quantity: 500,
          action: AssetAction.buy,
        ),
        assetTransaction(
          id: 'future-buy',
          date: july10,
          quantity: 500,
          action: AssetAction.buy,
        ),
      ],
      candidate: assetTransaction(
        id: 'sale',
        date: july5,
        quantity: 700,
        action: AssetAction.sell,
      ),
    );

    expect(result.isValid, isFalse);
    expect(result.availableQuantity, 500);
    expect(result.invalidTransactionDate, july5);
  });

  test('multiple buys before a sale are accumulated', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'buy-1',
          date: july1,
          quantity: 400,
          action: AssetAction.buy,
        ),
        assetTransaction(
          id: 'buy-2',
          date: july5,
          quantity: 600,
          action: AssetAction.buy,
        ),
      ],
      candidate: assetTransaction(
        id: 'sale',
        date: july10,
        quantity: 900,
        action: AssetAction.sell,
      ),
    );

    expect(result.isValid, isTrue);
    expect(result.availableQuantity, 1000);
  });

  test('multiple partial sales replay against the remaining quantity', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'buy',
          date: july1,
          quantity: 1000,
          action: AssetAction.buy,
        ),
        assetTransaction(
          id: 'sale-1',
          date: july5,
          quantity: 300,
          action: AssetAction.sell,
        ),
      ],
      candidate: assetTransaction(
        id: 'sale-2',
        date: july10,
        quantity: 600,
        action: AssetAction.sell,
      ),
    );

    expect(result.isValid, isTrue);
    expect(result.availableQuantity, 700);
  });

  test('another sale after a fully sold position is blocked', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'buy',
          date: july1,
          quantity: 10,
          action: AssetAction.buy,
        ),
        assetTransaction(
          id: 'full-sale',
          date: july5,
          quantity: 10,
          action: AssetAction.sell,
        ),
      ],
      candidate: assetTransaction(
        id: 'extra-sale',
        date: july10,
        quantity: 1,
        action: AssetAction.sell,
      ),
    );

    expect(result.isValid, isFalse);
    expect(result.availableQuantity, 0);
  });

  test('editing a sale excludes its original version', () {
    final originalSale = assetTransaction(
      id: 'sale',
      date: july5,
      quantity: 400,
      action: AssetAction.sell,
    );
    final history = [
      assetTransaction(
        id: 'buy',
        date: july1,
        quantity: 1000,
        action: AssetAction.buy,
      ),
      originalSale,
    ];

    final allowed = validator.validateCandidate(
      existingTransactions: history,
      candidate: originalSale.copyWith(quantity: 700.0),
      replacedTransactionId: originalSale.id,
    );
    final blocked = validator.validateCandidate(
      existingTransactions: history,
      candidate: originalSale.copyWith(quantity: 1100.0),
      replacedTransactionId: originalSale.id,
    );

    expect(allowed.isValid, isTrue);
    expect(allowed.availableQuantity, 1000);
    expect(blocked.isValid, isFalse);
  });

  test('reducing a purchase cannot invalidate a later sale', () {
    final purchase = assetTransaction(
      id: 'buy',
      date: july1,
      quantity: 1000,
      action: AssetAction.buy,
    );
    final result = validator.validateCandidate(
      existingTransactions: [
        purchase,
        assetTransaction(
          id: 'sale',
          date: july5,
          quantity: 800,
          action: AssetAction.sell,
        ),
      ],
      candidate: purchase.copyWith(quantity: 500.0),
      replacedTransactionId: purchase.id,
    );

    expect(result.isValid, isFalse);
    expect(result.invalidatesLaterTransaction, isTrue);
    expect(result.invalidTransactionId, 'sale');
  });

  test('moving a purchase after a sale is blocked', () {
    final purchase = assetTransaction(
      id: 'buy',
      date: july1,
      quantity: 1000,
      action: AssetAction.buy,
    );
    final result = validator.validateCandidate(
      existingTransactions: [
        purchase,
        assetTransaction(
          id: 'sale',
          date: july5,
          quantity: 800,
          action: AssetAction.sell,
        ),
      ],
      candidate: purchase.copyWith(date: july10),
      replacedTransactionId: purchase.id,
    );

    expect(result.isValid, isFalse);
    expect(result.invalidTransactionId, 'sale');
  });

  test('changing asset identity validates the original asset history', () {
    final usdPurchase = assetTransaction(
      id: 'buy',
      date: july1,
      quantity: 1000,
      action: AssetAction.buy,
    );
    final result = validator.validateCandidate(
      existingTransactions: [
        usdPurchase,
        assetTransaction(
          id: 'sale',
          date: july5,
          quantity: 800,
          action: AssetAction.sell,
        ),
      ],
      candidate: usdPurchase.copyWith(
        assetDefinitionId: 'asset-sgd',
        assetName: 'Singapore Dollar Cash',
        assetSymbol: 'SGD',
        unit: 'sgd',
      ),
      replacedTransactionId: usdPurchase.id,
    );

    expect(result.isValid, isFalse);
    expect(result.invalidTransactionId, 'sale');
  });

  test('soft-deleted purchases do not contribute quantity', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'deleted-buy',
          date: july1,
          quantity: 1000,
          action: AssetAction.buy,
          deletedAt: july5,
        ),
      ],
      candidate: assetTransaction(
        id: 'sale',
        date: july10,
        quantity: 1,
        action: AssetAction.sell,
      ),
    );

    expect(result.isValid, isFalse);
    expect(result.availableQuantity, 0);
  });

  test('legacy snapshot fallback matches buy and sale', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'legacy-buy',
          date: july1,
          quantity: 10,
          action: AssetAction.buy,
          definitionId: null,
          assetName: 'Gold Holdings',
          assetSymbol: '',
          unit: 'gram',
        ),
      ],
      candidate: assetTransaction(
        id: 'legacy-sale',
        date: july5,
        quantity: 6,
        action: AssetAction.sell,
        definitionId: null,
        assetName: 'Gold Holdings',
        assetSymbol: '',
        unit: 'gram',
      ),
    );

    expect(result.isValid, isTrue);
    expect(result.availableQuantity, 10);
  });

  test('USD and SGD remain isolated', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'usd-buy',
          date: july1,
          quantity: 1000,
          action: AssetAction.buy,
        ),
      ],
      candidate: assetTransaction(
        id: 'sgd-sale',
        date: july5,
        quantity: 1,
        action: AssetAction.sell,
        definitionId: 'asset-sgd',
        assetName: 'Singapore Dollar Cash',
        assetSymbol: 'SGD',
        unit: 'sgd',
      ),
    );

    expect(result.isValid, isFalse);
    expect(result.availableQuantity, 0);
  });

  test('separate stock definition IDs remain isolated', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'stock-a-buy',
          date: july1,
          quantity: 500,
          action: AssetAction.buy,
          definitionId: 'stock-a',
          assetName: 'Company A',
          assetSymbol: 'SAME',
          unit: 'share',
        ),
      ],
      candidate: assetTransaction(
        id: 'stock-b-sale',
        date: july5,
        quantity: 1,
        action: AssetAction.sell,
        definitionId: 'stock-b',
        assetName: 'Company B',
        assetSymbol: 'SAME',
        unit: 'share',
      ),
    );

    expect(result.isValid, isFalse);
    expect(result.availableQuantity, 0);
  });

  test('floating-point noise does not reject an exact sale', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'buy',
          date: july1,
          quantity: 0.3,
          action: AssetAction.buy,
        ),
        assetTransaction(
          id: 'sale-1',
          date: july5,
          quantity: 0.1,
          action: AssetAction.sell,
        ),
      ],
      candidate: assetTransaction(
        id: 'sale-2',
        date: july10,
        quantity: 0.2,
        action: AssetAction.sell,
      ),
    );

    expect(result.isValid, isTrue);
  });

  test('fully sold floating quantity cannot fund a later real sale', () {
    final history = [
      assetTransaction(
        id: 'buy-1',
        date: july1,
        quantity: 0.1,
        action: AssetAction.buy,
      ),
      assetTransaction(
        id: 'buy-2',
        date: july5,
        quantity: 0.2,
        action: AssetAction.buy,
      ),
      assetTransaction(
        id: 'full-sale',
        date: july10,
        quantity: 0.3,
        action: AssetAction.sell,
      ),
    ];

    final result = validator.validateCandidate(
      existingTransactions: history,
      candidate: assetTransaction(
        id: 'later-sale',
        date: DateTime(2026, 7, 11),
        quantity: 0.01,
        action: AssetAction.sell,
      ),
    );

    expect(result.isValid, isFalse);
    expect(result.availableQuantity, 0);
  });

  test('already-negative legacy history cannot fund another transaction', () {
    final result = validator.validateCandidate(
      existingTransactions: [
        assetTransaction(
          id: 'legacy-buy',
          date: july1,
          quantity: 1,
          action: AssetAction.buy,
        ),
        assetTransaction(
          id: 'legacy-oversell',
          date: july5,
          quantity: 2,
          action: AssetAction.sell,
        ),
      ],
      candidate: assetTransaction(
        id: 'new-buy',
        date: july10,
        quantity: 10,
        action: AssetAction.buy,
      ),
    );

    expect(result.isValid, isFalse);
    expect(result.invalidTransactionId, 'legacy-oversell');
  });
}
