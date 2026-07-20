import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/quick_add/quick_add_controller.dart';

class _FakeRepository implements TransactionRepository {
  final saved = <Transaction>[];
  bool throwOnSave = false;

  @override
  Future<List<Transaction>> getAll() async {
    return List.of(saved);
  }

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
}

TransactionController _createTransactionController(_FakeRepository repository) {
  return TransactionController(
    create: CreateTransaction(repository),
    update: UpdateTransaction(repository),
    delete: DeleteTransaction(repository),
    get: GetTransactions(repository),
    duplicate: DuplicateTransaction(repository),
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
    quickAdd.assetConversion.setSellAsset(true);
    quickAdd.setAmountText('54.000.000');
    quickAdd.assetConversion.quantityController.text = '20';
    quickAdd.setProject('No project');
    quickAdd.description = 'Sell gold';

    expect(quickAdd.assetConversion.source, 'Gold Holdings');
    expect(quickAdd.assetConversion.destination, 'Cash Enos');

    expect(await quickAdd.save(), isTrue);
    expect(repository.saved, hasLength(1));

    final saved = repository.saved.single;

    expect(saved.type, TransactionType.assetConversion);
    expect(saved.account, 'Gold Holdings -> Cash Enos');
    expect(saved.title, 'Sell gold');
    expect(saved.amount, 54000000);
    expect(saved.quantity, 20);
    expect(saved.unit, 'gram');
    expect(saved.unitPrice, 2700000);
    expect(saved.projectId, isNull);
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
}
