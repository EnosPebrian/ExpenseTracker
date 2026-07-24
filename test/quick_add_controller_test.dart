import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/quick_add/quick_add_controller.dart';

class _FakeRepository implements TransactionRepository {
  final saved = <Transaction>[];
  bool throwOnSave = false;

  @override
  Future<List<Transaction>> getAll() async {
    return saved.where((item) => item.deletedAt == null).toList();
  }

  @override
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async => null;

  @override
  Future<void> save(Transaction transaction) async {
    if (throwOnSave) {
      throw StateError('database unavailable');
    }

    saved.add(transaction);
  }

  @override
  Future<void> softDelete(Transaction transaction) async {
    saved.add(transaction);
  }

  @override
  Future<void> saveAssetFeeChange({
    required Transaction parent,
    Transaction? linkedExpense,
    Transaction? obsoleteLinkedExpense,
  }) async {
    if (throwOnSave) throw StateError('database unavailable');
    saved.add(parent);
    if (linkedExpense != null) saved.add(linkedExpense);
    if (obsoleteLinkedExpense != null) saved.add(obsoleteLinkedExpense);
  }
}

TransactionController _createTransactionController(
  _FakeRepository repository, {
  List<AssetDefinition> assetDefinitions = const [],
}) {
  AssetDefinition? resolve(String id) {
    for (final definition in assetDefinitions) {
      if (definition.id == id) return definition;
    }
    return null;
  }

  return TransactionController(
    create: CreateTransaction(
      repository,
      assetDefinitionResolver: assetDefinitions.isEmpty ? null : resolve,
    ),
    update: UpdateTransaction(
      repository,
      assetDefinitionResolver: assetDefinitions.isEmpty ? null : resolve,
    ),
    delete: DeleteTransaction(repository),
    get: GetTransactions(repository),
    duplicate: DuplicateTransaction(
      repository,
      assetDefinitionResolver: assetDefinitions.isEmpty ? null : resolve,
    ),
  );
}

const _quickAddConfig = QuickAddConfig(
  accounts: ['Cash Enos', 'BNI Enos'],
  expenseCategories: ['Konsumsi'],
  incomeCategories: ['Gaji Enos'],
  projects: ['Life', 'Tebu Nai'],
  assets: ['Gold Holdings', 'Stock Portfolio', 'Bitcoin Wallet', 'Inventory'],
);

void main() {
  test(
    'Quick Add defaults to Life and persists the selected project',
    () async {
      final repository = _FakeRepository();
      final transactions = _createTransactionController(repository);
      final quickAdd = QuickAddController(
        transactions: transactions,
        config: _quickAddConfig,
      );

      addTearDown(() {
        quickAdd.dispose();
        transactions.dispose();
      });

      quickAdd.setAmountText('125.000');

      expect(quickAdd.project, 'Life');

      quickAdd.setProject('Tebu Nai');
      quickAdd.description = 'Groceries';

      expect(await quickAdd.save(), isTrue);
      expect(repository.saved, hasLength(1));

      final saved = repository.saved.single;

      expect(saved.projectId, 'tebu-nai');
      expect(saved.title, 'Groceries');
      expect(saved.amount, 125000);
      expect(saved.type, TransactionType.expense);
    },
  );

  test('Quick Add records cash to gold asset conversion', () async {
    final repository = _FakeRepository();
    final transactions = _createTransactionController(repository);
    final quickAdd = QuickAddController(
      transactions: transactions,
      config: _quickAddConfig,
    );

    addTearDown(() {
      quickAdd.dispose();
      transactions.dispose();
    });

    quickAdd.setType(TransactionType.assetConversion);
    quickAdd.setAmountText('50.000.000');
    quickAdd.assetConversion.quantityController.text = '20';

    expect(quickAdd.assetConversion.sellAsset, isFalse);
    expect(quickAdd.assetConversion.source, 'Cash Enos');
    expect(quickAdd.assetConversion.destination, 'Gold Holdings');

    expect(await quickAdd.save(), isTrue);
    expect(repository.saved, hasLength(1));

    final saved = repository.saved.single;

    expect(saved.type, TransactionType.assetConversion);
    expect(saved.category, 'Asset conversion');
    expect(saved.account, 'Cash Enos -> Gold Holdings');
    expect(saved.title, 'Gold Holdings acquisition');
    expect(saved.amount, 50000000);
    expect(saved.quantity, 20);
    expect(saved.unit, 'gram');
    expect(saved.unitPrice, 2500000);
    expect(saved.projectId, 'life');
  });

  test('Quick Add records gold to cash asset conversion', () async {
    final repository = _FakeRepository()
      ..saved.add(_goldTransaction(quantity: 20, action: AssetAction.buy));
    final transactions = _createTransactionController(repository);
    await transactions.load();
    final quickAdd = QuickAddController(
      transactions: transactions,
      config: _quickAddConfig,
    );

    addTearDown(() {
      quickAdd.dispose();
      transactions.dispose();
    });

    quickAdd.setType(TransactionType.assetConversion);
    quickAdd.assetConversion.setSellAsset(true);
    quickAdd.setAmountText('54.000.000');
    quickAdd.assetConversion.quantityController.text = '20';
    quickAdd.setProject('No project');
    quickAdd.description = 'Sell gold';

    expect(quickAdd.assetConversion.source, 'Gold Holdings');
    expect(quickAdd.assetConversion.destination, 'Cash Enos');

    expect(await quickAdd.save(), isTrue);
    expect(repository.saved, hasLength(2));

    final saved = repository.saved.last;

    expect(saved.type, TransactionType.assetConversion);
    expect(saved.account, 'Gold Holdings -> Cash Enos');
    expect(saved.title, 'Sell gold');
    expect(saved.amount, 54000000);
    expect(saved.quantity, 20);
    expect(saved.unit, 'gram');
    expect(saved.unitPrice, 2700000);
    expect(saved.projectId, isNull);
  });

  test('Quick Add blocks oversell and preserves entered values', () async {
    final repository = _FakeRepository()
      ..saved.add(_goldTransaction(quantity: 10, action: AssetAction.buy));
    final transactions = _createTransactionController(repository);
    await transactions.load();
    final quickAdd = QuickAddController(
      transactions: transactions,
      config: _quickAddConfig,
    );

    addTearDown(() {
      quickAdd.dispose();
      transactions.dispose();
    });

    quickAdd.setType(TransactionType.assetConversion);
    quickAdd.assetConversion.setSellAsset(true);
    quickAdd.setAmountText('30.000.000');
    quickAdd.assetConversion.quantityController.text = '12';
    quickAdd.description = 'Keep this description';

    expect(quickAdd.assetConversion.availableQuantity, 10);
    expect(await quickAdd.save(), isFalse);
    expect(quickAdd.error, contains('sell up to GRAM 10'));
    expect(repository.saved, hasLength(1));
    expect(quickAdd.amountText, '30.000.000');
    expect(quickAdd.assetConversion.quantityController.text, '12');
    expect(quickAdd.description, 'Keep this description');
  });

  test('Quick Add rejects asset conversion without quantity', () async {
    final repository = _FakeRepository();
    final transactions = _createTransactionController(repository);
    final quickAdd = QuickAddController(
      transactions: transactions,
      config: _quickAddConfig,
    );

    addTearDown(() {
      quickAdd.dispose();
      transactions.dispose();
    });

    quickAdd.setType(TransactionType.assetConversion);
    quickAdd.setAmountText('50.000.000');
    quickAdd.assetConversion.quantityController.text = '';

    expect(await quickAdd.save(), isFalse);
    expect(quickAdd.error, 'Enter an asset quantity greater than zero.');
    expect(repository.saved, isEmpty);
    expect(transactions.transactions, isEmpty);
  });
  test('Quick Add returns false and exposes persistence failure', () async {
    final repository = _FakeRepository()..throwOnSave = true;

    final transactions = _createTransactionController(repository);

    final quickAdd = QuickAddController(
      transactions: transactions,
      config: _quickAddConfig,
    );

    addTearDown(() {
      quickAdd.dispose();
      transactions.dispose();
    });

    quickAdd.setAmountText('125.000');
    quickAdd.description = 'Failed transaction';

    final saved = await quickAdd.save();

    expect(saved, isFalse);
    expect(quickAdd.error, contains('database unavailable'));
    expect(transactions.error, contains('database unavailable'));
    expect(repository.saved, isEmpty);
    expect(transactions.transactions, isEmpty);
    expect(quickAdd.saving, isFalse);
  });

  test('Quick Add persists a capitalized asset fee', () async {
    final repository = _FakeRepository();
    final transactions = _createTransactionController(repository);
    final quickAdd = QuickAddController(
      transactions: transactions,
      config: _quickAddConfig,
    );
    addTearDown(() {
      quickAdd.dispose();
      transactions.dispose();
    });

    quickAdd.setType(TransactionType.assetConversion);
    quickAdd.setAmountText('10.000.000');
    quickAdd.assetConversion.quantityController.text = '4';
    quickAdd.assetConversion.feeController.text = '50.000';

    expect(await quickAdd.save(), isTrue);
    final saved = repository.saved.single;
    expect(saved.amount, 10000000);
    expect(saved.feeAmount, 50000);
    expect(saved.feeTreatment, AssetFeeTreatment.capitalizeIntoCostBasis);
    expect(saved.unitPrice, 2500000);
  });

  test('Quick Add persists one linked separate fee expense', () async {
    final repository = _FakeRepository();
    final transactions = _createTransactionController(repository);
    final quickAdd = QuickAddController(
      transactions: transactions,
      config: _quickAddConfig,
    );
    addTearDown(() {
      quickAdd.dispose();
      transactions.dispose();
    });

    quickAdd.setType(TransactionType.assetConversion);
    quickAdd.setAmountText('10.000.000');
    quickAdd.assetConversion.quantityController.text = '4';
    quickAdd.assetConversion.feeController.text = '50.000';
    quickAdd.assetConversion.setFeeTreatment(
      AssetFeeTreatment.recordAsSeparateExpense,
    );

    expect(await quickAdd.save(), isTrue);
    expect(repository.saved, hasLength(2));
    final parent = repository.saved.firstWhere(
      (transaction) => transaction.type == TransactionType.assetConversion,
    );
    final child = repository.saved.firstWhere(
      (transaction) =>
          transaction.relationType == TransactionRelationType.assetFeeExpense,
    );
    expect(child.relatedTransactionId, parent.id);
    expect(child.amount, 50000);
  });

  test('Quick Add preserves fee input after fee validation failure', () async {
    final repository = _FakeRepository()
      ..saved.add(_goldTransaction(quantity: 10, action: AssetAction.buy));
    final transactions = _createTransactionController(repository);
    await transactions.load();
    final quickAdd = QuickAddController(
      transactions: transactions,
      config: _quickAddConfig,
    );
    addTearDown(() {
      quickAdd.dispose();
      transactions.dispose();
    });

    quickAdd.setType(TransactionType.assetConversion);
    quickAdd.assetConversion.setSellAsset(true);
    quickAdd.setAmountText('40.000');
    quickAdd.assetConversion.quantityController.text = '1';
    quickAdd.assetConversion.feeController.text = '40.000';

    expect(await quickAdd.save(), isFalse);
    expect(quickAdd.error, contains('less than the gross sale amount'));
    expect(quickAdd.assetConversion.feeController.text, '40.000');
    expect(repository.saved, hasLength(1));
  });

  test(
    'Quick Add blocks over-precision without changing quantity or fee',
    () async {
      final repository = _FakeRepository();
      final transactions = _createTransactionController(repository);
      final quickAdd = QuickAddController(
        transactions: transactions,
        config: _quickAddConfig,
      );
      addTearDown(() {
        quickAdd.dispose();
        transactions.dispose();
      });

      quickAdd.setType(TransactionType.assetConversion);
      quickAdd.setAmountText('10.000.000');
      quickAdd.assetConversion.quantityController.text = '1.23456';
      quickAdd.assetConversion.feeController.text = '50.000';

      expect(await quickAdd.save(), isFalse);
      expect(quickAdd.error, 'Gold supports up to 4 decimal places.');
      expect(quickAdd.assetConversion.quantityController.text, '1.23456');
      expect(quickAdd.assetConversion.feeAmount, 50000);
      expect(repository.saved, isEmpty);
    },
  );

  test('Quick Add saves a valid gold precision boundary', () async {
    final repository = _FakeRepository();
    final transactions = _createTransactionController(repository);
    final quickAdd = QuickAddController(
      transactions: transactions,
      config: _quickAddConfig,
    );
    addTearDown(() {
      quickAdd.dispose();
      transactions.dispose();
    });

    quickAdd.setType(TransactionType.assetConversion);
    quickAdd.setAmountText('10.000.000');
    quickAdd.assetConversion.quantityController.text = '1.2345';

    expect(await quickAdd.save(), isTrue);
    expect(repository.saved.single.quantity, 1.2345);
  });

  test('Quick Add enforces stock lots and preserves rejected input', () async {
    final repository = _FakeRepository();
    final definition = _bbcaDefinition();
    final transactions = _createTransactionController(
      repository,
      assetDefinitions: [definition],
    );
    final quickAdd = QuickAddController(
      transactions: transactions,
      config: QuickAddConfig(
        accounts: const ['Cash Enos'],
        expenseCategories: const ['Konsumsi'],
        incomeCategories: const ['Gaji Enos'],
        projects: const ['Life'],
        assetDefinitions: [definition],
      ),
    );
    addTearDown(() {
      quickAdd.dispose();
      transactions.dispose();
    });

    quickAdd.setType(TransactionType.assetConversion);
    quickAdd.setAmountText('1.500.000');
    quickAdd.assetConversion.quantityController.text = '150';

    expect(await quickAdd.save(), isFalse);
    expect(quickAdd.error, contains('100, 200, 300'));
    expect(quickAdd.assetConversion.quantityController.text, '150');
    expect(repository.saved, isEmpty);

    quickAdd.assetConversion.quantityController.text = '100';
    expect(await quickAdd.save(), isTrue);
    expect(repository.saved.single.quantity, 100);
  });
}

AssetDefinition _bbcaDefinition() => AssetDefinition(
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

Transaction _goldTransaction({
  required double quantity,
  required AssetAction action,
}) {
  final date = DateTime(2026, 7, 1);
  return Transaction(
    id: action == AssetAction.buy ? 'gold-buy' : 'gold-sale',
    title: action == AssetAction.buy
        ? 'Gold Holdings acquisition'
        : 'Gold Holdings sale',
    category: 'Asset conversion',
    account: action == AssetAction.buy
        ? 'Cash Enos -> Gold Holdings'
        : 'Gold Holdings -> Cash Enos',
    date: date,
    amount: (quantity * 2500000).round(),
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: 'gram',
    unitPrice: 2500000,
    assetDefinitionId: 'legacy-gold-holdings',
    assetName: 'Gold Holdings',
    assetAction: action,
    createdAt: date,
    updatedAt: date,
  );
}
