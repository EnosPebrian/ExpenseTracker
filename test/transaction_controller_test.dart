import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_controller.dart';

class _FakeRepository implements TransactionRepository {
  final saved = <Transaction>[];

  @override
  Future<List<Transaction>> getAll({bool includeDeleted = false}) async {
    return saved
        .where((item) => includeDeleted || item.deletedAt == null)
        .toList();
  }

  @override
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async => null;

  @override
  Future<void> save(Transaction transaction) async {
    final index = saved.indexWhere((item) => item.id == transaction.id);

    if (index >= 0) {
      saved[index] = transaction;
    } else {
      saved.add(transaction);
    }
  }

  @override
  Future<void> softDelete(Transaction transaction) async {
    saved.removeWhere((item) => item.id == transaction.id);
  }

  @override
  Future<void> saveAssetFeeChange({
    required Transaction parent,
    Transaction? linkedExpense,
    Transaction? obsoleteLinkedExpense,
  }) async {
    await save(parent);
    if (linkedExpense != null) await save(linkedExpense);
    if (obsoleteLinkedExpense != null) await save(obsoleteLinkedExpense);
  }
}

TransactionController _createController(_FakeRepository repository) {
  return TransactionController(
    create: CreateTransaction(repository),
    update: UpdateTransaction(repository),
    delete: DeleteTransaction(repository),
    get: GetTransactions(repository),
    duplicate: DuplicateTransaction(repository),
  );
}

Transaction _transaction({
  required String id,
  required String title,
  required DateTime date,
  DateTime? createdAt,
}) {
  return Transaction(
    id: id,
    title: title,
    category: 'Konsumsi',
    account: 'Cash Enos',
    date: date,
    amount: 125000,
    type: TransactionType.expense,
    createdAt: createdAt ?? date,
    updatedAt: createdAt ?? date,
  );
}

void main() {
  test('load sorts transactions from newest to oldest', () async {
    final repository = _FakeRepository()
      ..saved.addAll([
        _transaction(
          id: 'old',
          title: 'Old transaction',
          date: DateTime(2026, 7, 1),
        ),
        _transaction(
          id: 'new',
          title: 'New transaction',
          date: DateTime(2026, 7, 20),
        ),
        _transaction(
          id: 'middle',
          title: 'Middle transaction',
          date: DateTime(2026, 7, 10),
        ),
      ]);

    final controller = _createController(repository);

    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.transactions.map((item) => item.id).toList(), [
      'new',
      'middle',
      'old',
    ]);
  });

  test('creating a backdated transaction keeps chronological order', () async {
    final repository = _FakeRepository()
      ..saved.add(
        _transaction(
          id: 'latest',
          title: 'Latest',
          date: DateTime(2026, 7, 20),
        ),
      );

    final controller = _createController(repository);

    addTearDown(controller.dispose);

    await controller.load();

    await controller.createTransaction(
      _transaction(
        id: 'backdated',
        title: 'Backdated',
        date: DateTime(2026, 7, 5),
      ),
    );

    expect(controller.transactions.map((item) => item.id).toList(), [
      'latest',
      'backdated',
    ]);
  });

  test('editing transaction date immediately reorders the list', () async {
    final repository = _FakeRepository()
      ..saved.addAll([
        _transaction(id: 'first', title: 'First', date: DateTime(2026, 7, 20)),
        _transaction(id: 'second', title: 'Second', date: DateTime(2026, 7, 5)),
      ]);

    final controller = _createController(repository);

    addTearDown(controller.dispose);

    await controller.load();

    final second = controller.transactions.singleWhere(
      (item) => item.id == 'second',
    );

    await controller.updateTransaction(
      second.copyWith(date: DateTime(2026, 7, 25)),
    );

    expect(controller.transactions.map((item) => item.id).toList(), [
      'second',
      'first',
    ]);

    expect(controller.transactions.first.version, 2);
  });

  test('same transaction date uses newest createdAt first', () async {
    final repository = _FakeRepository()
      ..saved.addAll([
        _transaction(
          id: 'earlier-created',
          title: 'Earlier created',
          date: DateTime(2026, 7, 20, 9),
          createdAt: DateTime(2026, 7, 18),
        ),
        _transaction(
          id: 'later-created',
          title: 'Later created',
          date: DateTime(2026, 7, 20, 9),
          createdAt: DateTime(2026, 7, 19),
        ),
      ]);

    final controller = _createController(repository);

    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.transactions.map((item) => item.id).toList(), [
      'later-created',
      'earlier-created',
    ]);
  });

  test('oversell exposes available and requested quantities', () async {
    final buyDate = DateTime(2026, 7, 1);
    final repository = _FakeRepository()
      ..saved.add(
        Transaction(
          id: 'buy',
          title: 'USD acquisition',
          category: 'Asset conversion',
          account: 'Cash -> US Dollar Cash',
          date: buyDate,
          amount: 16000000,
          type: TransactionType.assetConversion,
          quantity: 1000,
          unit: 'usd',
          unitPrice: 16000,
          assetDefinitionId: 'asset-usd',
          assetName: 'US Dollar Cash',
          assetSymbol: 'USD',
          assetAction: AssetAction.buy,
          createdAt: buyDate,
        ),
      );
    final controller = _createController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    await expectLater(
      controller.createTransaction(
        Transaction(
          id: 'sale',
          title: 'USD sale',
          category: 'Asset conversion',
          account: 'US Dollar Cash -> Cash',
          date: DateTime(2026, 7, 2),
          amount: 24000000,
          type: TransactionType.assetConversion,
          quantity: 1500,
          unit: 'usd',
          unitPrice: 16000,
          assetDefinitionId: 'asset-usd',
          assetName: 'US Dollar Cash',
          assetSymbol: 'USD',
          assetAction: AssetAction.sell,
        ),
      ),
      throwsA(isA<TransactionValidationException>()),
    );

    expect(controller.assetValidation?.availableQuantity, 1000);
    expect(controller.assetValidation?.requestedQuantity, 1500);
    expect(repository.saved, hasLength(1));
  });
}
