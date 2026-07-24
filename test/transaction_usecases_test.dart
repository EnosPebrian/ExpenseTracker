import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';

class FakeTransactionRepository implements TransactionRepository {
  final saved = <Transaction>[];
  @override
  Future<List<Transaction>> getAll({bool includeDeleted = false}) async => saved
      .where((transaction) => includeDeleted || transaction.deletedAt == null)
      .toList();
  @override
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async => null;
  @override
  Future<void> save(Transaction transaction) async => saved.add(transaction);
  @override
  Future<void> softDelete(Transaction transaction) async =>
      saved.add(transaction);
  @override
  Future<void> saveAssetFeeChange({
    required Transaction parent,
    Transaction? linkedExpense,
    Transaction? obsoleteLinkedExpense,
  }) async {
    saved.add(parent);
    if (linkedExpense != null) saved.add(linkedExpense);
    if (obsoleteLinkedExpense != null) saved.add(obsoleteLinkedExpense);
  }
}

Transaction sample() => Transaction(
  projectId: 'life',
  title: 'Groceries',
  category: 'Konsumsi',
  account: 'BNI Enos',
  date: DateTime(2026, 7, 19),
  amount: 125000,
  type: TransactionType.expense,
);

Transaction assetTransaction({
  required String id,
  required DateTime date,
  required double quantity,
  required AssetAction action,
  int feeAmount = 0,
  AssetFeeTreatment feeTreatment = AssetFeeTreatment.none,
}) => Transaction(
  id: id,
  title: action == AssetAction.buy ? 'USD acquisition' : 'USD sale',
  category: 'Asset conversion',
  account: action == AssetAction.buy
      ? 'Cash -> US Dollar Cash'
      : 'US Dollar Cash -> Cash',
  date: date,
  amount: (quantity * 16000).round(),
  type: TransactionType.assetConversion,
  quantity: quantity,
  unit: 'usd',
  unitPrice: 16000,
  assetDefinitionId: 'asset-usd',
  assetName: 'US Dollar Cash',
  assetSymbol: 'USD',
  assetAction: action,
  feeAmount: feeAmount,
  feeTreatment: feeTreatment,
  createdAt: date,
  updatedAt: date,
);

void main() {
  test('CreateTransaction validates and saves through repository', () async {
    final repository = FakeTransactionRepository();
    final created = await CreateTransaction(repository)(sample());
    expect(repository.saved.single.id, created.id);
    expect(created.projectId, 'life');
    expect(created.syncStatus, 'pending');
  });

  test('UpdateTransaction preserves UUID and increments version', () async {
    final repository = FakeTransactionRepository();
    final original = sample();
    final updated = await UpdateTransaction(repository)(
      original.copyWith(amount: 150000),
    );
    expect(updated.id, original.id);
    expect(updated.version, original.version + 1);
    expect(updated.amount, 150000);
  });

  test(
    'asset update preserves execution reference and duplicate clears it',
    () async {
      final repository = FakeTransactionRepository();
      final original =
          assetTransaction(
            id: 'usd-reference',
            date: DateTime(2026, 7, 24),
            quantity: 1000,
            action: AssetAction.buy,
          ).copyWith(
            marketReferenceUnitPrice: 16250,
            marketReferenceCurrencyCode: 'IDR',
            marketReferenceUnit: 'usd',
            marketReferenceSource: AssetMarketReferenceSource.cachedQuote,
            marketReferenceQuotedAt: DateTime.utc(2026, 7, 24, 8),
          );
      repository.saved.add(original);

      final updated = await UpdateTransaction(repository)(
        original.copyWith(title: 'Updated USD acquisition'),
      );
      expect(updated.marketReferenceUnitPrice, 16250);
      expect(
        updated.marketReferenceSource,
        AssetMarketReferenceSource.cachedQuote,
      );

      final duplicate = await DuplicateTransaction(repository)(original);
      expect(duplicate.marketReferenceUnitPrice, isNull);
      expect(duplicate.marketReferenceSource, isNull);
      expect(duplicate.marketReferenceQuotedAt, isNull);
    },
  );

  test(
    'DuplicateTransaction creates a fresh UUID and resets metadata',
    () async {
      final repository = FakeTransactionRepository();
      final original = sample().copyWith(version: 4, syncStatus: 'synced');
      final duplicate = await DuplicateTransaction(repository)(original);
      expect(duplicate.id, isNot(original.id));
      expect(duplicate.projectId, original.projectId);
      expect(duplicate.amount, original.amount);
      expect(duplicate.version, 1);
      expect(duplicate.syncStatus, 'pending');
      expect(repository.saved.single.syncStatus, 'pending');
    },
  );

  test('DeleteTransaction sends a versioned soft-delete record', () async {
    final repository = FakeTransactionRepository();
    final original = sample();
    await DeleteTransaction(repository)(original);
    final deleted = repository.saved.single;
    expect(deleted.id, original.id);
    expect(deleted.deletedAt, isNotNull);
    expect(deleted.version, original.version + 1);
    expect(deleted.syncStatus, 'pending');
  });

  test('invalid asset sale is rejected before persistence', () async {
    final repository = FakeTransactionRepository()
      ..saved.add(
        assetTransaction(
          id: 'buy',
          date: DateTime(2026, 7, 1),
          quantity: 1000,
          action: AssetAction.buy,
        ),
      );
    final sale = assetTransaction(
      id: 'sale',
      date: DateTime(2026, 7, 2),
      quantity: 1500,
      action: AssetAction.sell,
    );

    await expectLater(
      CreateTransaction(repository)(sale),
      throwsA(
        isA<TransactionValidationException>().having(
          (exception) => exception.assetValidation?.availableQuantity,
          'available quantity',
          1000,
        ),
      ),
    );
    expect(repository.saved, hasLength(1));
  });

  test('valid asset sale is persisted', () async {
    final repository = FakeTransactionRepository()
      ..saved.add(
        assetTransaction(
          id: 'buy',
          date: DateTime(2026, 7, 1),
          quantity: 1000,
          action: AssetAction.buy,
        ),
      );

    await CreateTransaction(repository)(
      assetTransaction(
        id: 'sale',
        date: DateTime(2026, 7, 2),
        quantity: 1000,
        action: AssetAction.sell,
      ),
    );

    expect(repository.saved, hasLength(2));
    expect(repository.saved.last.assetAction, AssetAction.sell);
  });

  test('editing a sale validates the replacement history', () async {
    final purchase = assetTransaction(
      id: 'buy',
      date: DateTime(2026, 7, 1),
      quantity: 1000,
      action: AssetAction.buy,
    );
    final sale = assetTransaction(
      id: 'sale',
      date: DateTime(2026, 7, 2),
      quantity: 400,
      action: AssetAction.sell,
    );
    final repository = FakeTransactionRepository()
      ..saved.addAll([purchase, sale]);

    final allowed = await UpdateTransaction(repository)(
      sale.copyWith(quantity: 700.0),
    );
    expect(allowed.quantity, 700);

    final blockedRepository = FakeTransactionRepository()
      ..saved.addAll([purchase, sale]);
    await expectLater(
      UpdateTransaction(blockedRepository)(sale.copyWith(quantity: 1100.0)),
      throwsA(isA<TransactionValidationException>()),
    );
    expect(blockedRepository.saved, hasLength(2));
  });

  test('reducing a purchase is blocked when it breaks a later sale', () async {
    final purchase = assetTransaction(
      id: 'buy',
      date: DateTime(2026, 7, 1),
      quantity: 1000,
      action: AssetAction.buy,
    );
    final repository = FakeTransactionRepository()
      ..saved.addAll([
        purchase,
        assetTransaction(
          id: 'sale',
          date: DateTime(2026, 7, 2),
          quantity: 800,
          action: AssetAction.sell,
        ),
      ]);

    await expectLater(
      UpdateTransaction(repository)(purchase.copyWith(quantity: 500.0)),
      throwsA(
        isA<TransactionValidationException>().having(
          (exception) => exception.assetValidation?.invalidatesLaterTransaction,
          'invalidates later sale',
          isTrue,
        ),
      ),
    );
    expect(repository.saved, hasLength(2));
  });

  test('deleting a required purchase is blocked', () async {
    final purchase = assetTransaction(
      id: 'buy',
      date: DateTime(2026, 7, 1),
      quantity: 1000,
      action: AssetAction.buy,
    );
    final repository = FakeTransactionRepository()
      ..saved.addAll([
        purchase,
        assetTransaction(
          id: 'sale',
          date: DateTime(2026, 7, 2),
          quantity: 800,
          action: AssetAction.sell,
        ),
      ]);

    await expectLater(
      DeleteTransaction(repository)(purchase),
      throwsA(isA<TransactionValidationException>()),
    );
    expect(repository.saved, hasLength(2));
  });

  test('ordinary transaction deletion does not load asset history', () async {
    final repository = _FailingReadRepository();

    await DeleteTransaction(repository)(sample());

    expect(repository.deleted, isTrue);
  });

  test('negative asset fee is rejected', () async {
    final repository = FakeTransactionRepository();

    await expectLater(
      CreateTransaction(repository)(
        assetTransaction(
          id: 'negative-fee',
          date: DateTime(2026, 7, 1),
          quantity: 1,
          action: AssetAction.buy,
          feeAmount: -1,
          feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
        ),
      ),
      throwsA(isA<TransactionValidationException>()),
    );
    expect(repository.saved, isEmpty);
  });

  test('buy accepts capitalization and rejects sale deduction', () async {
    final repository = FakeTransactionRepository();
    final valid = assetTransaction(
      id: 'buy-with-fee',
      date: DateTime(2026, 7, 1),
      quantity: 10,
      action: AssetAction.buy,
      feeAmount: 50000,
      feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
    );

    await CreateTransaction(repository)(valid);
    expect(repository.saved.single.feeAmount, 50000);

    await expectLater(
      CreateTransaction(repository)(
        valid.copyWith(
          id: 'invalid-buy-fee',
          feeTreatment: AssetFeeTreatment.deductFromSaleProceeds,
        ),
      ),
      throwsA(isA<TransactionValidationException>()),
    );
  });

  test('sell accepts deduction and rejects capitalization', () async {
    final purchase = assetTransaction(
      id: 'buy',
      date: DateTime(2026, 7, 1),
      quantity: 10,
      action: AssetAction.buy,
    );
    final repository = FakeTransactionRepository()..saved.add(purchase);
    final valid = assetTransaction(
      id: 'sell-with-fee',
      date: DateTime(2026, 7, 2),
      quantity: 5,
      action: AssetAction.sell,
      feeAmount: 40000,
      feeTreatment: AssetFeeTreatment.deductFromSaleProceeds,
    );

    await CreateTransaction(repository)(valid);
    expect(repository.saved.last.feeAmount, 40000);

    await expectLater(
      CreateTransaction(repository)(
        valid.copyWith(
          id: 'invalid-sell-fee',
          feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
        ),
      ),
      throwsA(isA<TransactionValidationException>()),
    );
  });

  test('deducted sell fee must be lower than gross proceeds', () async {
    final repository = FakeTransactionRepository()
      ..saved.add(
        assetTransaction(
          id: 'buy',
          date: DateTime(2026, 7, 1),
          quantity: 10,
          action: AssetAction.buy,
        ),
      );

    await expectLater(
      CreateTransaction(repository)(
        assetTransaction(
          id: 'sell',
          date: DateTime(2026, 7, 2),
          quantity: 1,
          action: AssetAction.sell,
          feeAmount: 16000,
          feeTreatment: AssetFeeTreatment.deductFromSaleProceeds,
        ),
      ),
      throwsA(
        isA<TransactionValidationException>().having(
          (error) => error.message,
          'message',
          contains('less than the gross sale amount'),
        ),
      ),
    );
  });

  test('duplicate preserves asset fee snapshots', () async {
    final repository = FakeTransactionRepository();
    final original = assetTransaction(
      id: 'buy-with-fee',
      date: DateTime(2026, 7, 1),
      quantity: 10,
      action: AssetAction.buy,
      feeAmount: 50000,
      feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
    );

    final duplicate = await DuplicateTransaction(repository)(original);

    expect(duplicate.feeAmount, 50000);
    expect(duplicate.feeTreatment, AssetFeeTreatment.capitalizeIntoCostBasis);
  });

  test('create and edit reject quantities beyond snapshot precision', () async {
    final repository = FakeTransactionRepository();
    final overPreciseUsd = assetTransaction(
      id: 'over-precise-usd',
      date: DateTime(2026, 7, 1),
      quantity: 1000.257,
      action: AssetAction.buy,
    );

    await expectLater(
      CreateTransaction(repository)(overPreciseUsd),
      throwsA(
        isA<TransactionValidationException>().having(
          (error) => error.message,
          'message',
          'USD supports up to 2 decimal places.',
        ),
      ),
    );
    expect(repository.saved, isEmpty);

    final stock =
        assetTransaction(
          id: 'stock',
          date: DateTime(2026, 7, 1),
          quantity: 100,
          action: AssetAction.buy,
        ).copyWith(
          unit: 'share',
          assetName: 'Bank Central Asia',
          assetSymbol: 'BBCA',
          assetDefinitionId: 'asset-bbca',
        );
    await expectLater(
      UpdateTransaction(repository)(stock.copyWith(quantity: 100.5)),
      throwsA(
        isA<TransactionValidationException>().having(
          (error) => error.message,
          'message',
          'Stock quantity must be entered as whole shares.',
        ),
      ),
    );
  });

  test(
    'historical over-precision records remain readable without validation',
    () async {
      final repository = FakeTransactionRepository();
      final historical = assetTransaction(
        id: 'legacy-over-precision',
        date: DateTime(2025, 1, 1),
        quantity: 1000.257,
        action: AssetAction.buy,
      );
      repository.saved.add(historical);

      final loaded = await GetTransactions(repository)();
      expect(loaded.single.quantity, 1000.257);
    },
  );

  test('create and edit stock trades use the shared lot policy', () async {
    final repository = FakeTransactionRepository();
    final create = CreateTransaction(
      repository,
      assetDefinitionResolver: _resolveDefinition,
    );
    final invalidBuy = _stockTransaction(
      id: 'invalid-buy',
      date: DateTime(2026, 7, 1),
      quantity: 150,
      action: AssetAction.buy,
    );

    await expectLater(
      create(invalidBuy),
      throwsA(
        isA<TransactionValidationException>().having(
          (error) => error.message,
          'message',
          contains('100, 200, 300'),
        ),
      ),
    );
    expect(repository.saved, isEmpty);

    final purchase = _stockTransaction(
      id: 'buy',
      date: DateTime(2026, 7, 1),
      quantity: 250,
      action: AssetAction.buy,
    );
    repository.saved.add(purchase);
    final sale = _stockTransaction(
      id: 'sale',
      date: DateTime(2026, 7, 2),
      quantity: 50,
      action: AssetAction.sell,
    );
    final createdSale = await create(sale);
    expect(createdSale.quantity, 50);

    final update = UpdateTransaction(
      repository,
      assetDefinitionResolver: _resolveDefinition,
    );
    await expectLater(
      update(sale.copyWith(quantity: 25.0)),
      throwsA(isA<TransactionValidationException>()),
    );
    expect(repository.saved.where((item) => item.id == 'sale'), hasLength(1));
  });

  test('changing stock identity revalidates destination lot size', () async {
    final repository = FakeTransactionRepository();
    final original = _stockTransaction(
      id: 'aapl-buy',
      date: DateTime(2026, 7, 1),
      quantity: 50,
      action: AssetAction.buy,
      definition: _aapl,
    );
    repository.saved.add(original);

    await expectLater(
      UpdateTransaction(
        repository,
        assetDefinitionResolver: _resolveDefinition,
      )(
        original.copyWith(
          assetDefinitionId: _bbca.id,
          assetName: _bbca.displayName,
          assetSymbol: _bbca.symbol,
        ),
      ),
      throwsA(
        isA<TransactionValidationException>().having(
          (error) => error.message,
          'message',
          contains('100, 200, 300'),
        ),
      ),
    );
  });
}

Transaction _stockTransaction({
  required String id,
  required DateTime date,
  required double quantity,
  required AssetAction action,
  AssetDefinition? definition,
}) {
  final selected = definition ?? _bbca;
  return Transaction(
    id: id,
    title: '${selected.symbol} trade',
    category: 'Asset conversion',
    account: action == AssetAction.buy
        ? 'Cash -> ${selected.displayName}'
        : '${selected.displayName} -> Cash',
    date: date,
    amount: (quantity * 10000).round(),
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: 'share',
    unitPrice: 10000,
    assetDefinitionId: selected.id,
    assetName: selected.displayName,
    assetSymbol: selected.symbol,
    assetAction: action,
    createdAt: date,
    updatedAt: date,
  );
}

AssetDefinition? _resolveDefinition(String id) {
  for (final definition in [_bbca, _aapl]) {
    if (definition.id == id) return definition;
  }
  return null;
}

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

final _aapl = AssetDefinition(
  id: 'asset-aapl',
  displayName: 'Apple',
  kind: AssetKind.stock,
  symbol: 'AAPL',
  providerCode: null,
  providerSymbol: null,
  exchangeCode: 'NASDAQ',
  currencyCode: 'IDR',
  unit: 'share',
  lotSize: 1,
  onlinePricingEnabled: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'test',
  syncStatus: 'local_only',
);

class _FailingReadRepository implements TransactionRepository {
  bool deleted = false;

  @override
  Future<List<Transaction>> getAll({bool includeDeleted = false}) {
    throw StateError('Ordinary deletion must not load asset history.');
  }

  @override
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async => null;

  @override
  Future<void> save(Transaction transaction) async {}

  @override
  Future<void> softDelete(Transaction transaction) async {
    deleted = true;
  }

  @override
  Future<void> saveAssetFeeChange({
    required Transaction parent,
    Transaction? linkedExpense,
    Transaction? obsoleteLinkedExpense,
  }) async {}
}
