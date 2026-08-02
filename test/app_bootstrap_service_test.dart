import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/app/services/app_bootstrap_service.dart';
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_controller.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_project.dart';

class _FakeStore extends LocalStore {
  bool initialized = false;

  final ensuredSeeds = <String>[];
  final masterData = <String, List<String>>{};

  String _key(String entity, String? categoryType) {
    return '$entity:${categoryType ?? ''}';
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> ensureMasterSeeds(
    String entity,
    List<String> names, {
    String? categoryType,
  }) async {
    final key = _key(entity, categoryType);

    ensuredSeeds.add(key);
    masterData.putIfAbsent(key, () => List<String>.of(names));
  }

  @override
  Future<List<String>> getMasterNames(
    String entity, {
    String? categoryType,
  }) async {
    return List<String>.of(masterData[_key(entity, categoryType)] ?? const []);
  }

  @override
  Future<List<Map<String, Object?>>> getProjectRecords() async {
    return [
      for (final (index, name)
          in (masterData['projects:'] ?? const <String>[]).indexed)
        FinancialProject(id: 'project-$index', name: name).toRecord(),
    ];
  }
}

class _FakeTransactionRepository implements TransactionRepository {
  final saved = <Transaction>[];
  bool throwOnGet = false;

  @override
  Future<List<Transaction>> getAll({bool includeDeleted = false}) async {
    if (throwOnGet) {
      throw StateError('database unavailable');
    }

    return List<Transaction>.of(saved);
  }

  @override
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async => null;

  @override
  Future<void> save(Transaction transaction) async {
    saved.add(transaction);
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
    saved.add(parent);
    if (linkedExpense != null) saved.add(linkedExpense);
    if (obsoleteLinkedExpense != null) saved.add(obsoleteLinkedExpense);
  }
}

TransactionController _createController(_FakeTransactionRepository repository) {
  return TransactionController(
    create: CreateTransaction(repository),
    update: UpdateTransaction(repository),
    delete: DeleteTransaction(repository),
    get: GetTransactions(repository),
    duplicate: DuplicateTransaction(repository),
  );
}

void main() {
  test(
    'bootstrap initializes storage and never seeds financial data',
    () async {
      final store = _FakeStore();

      store.masterData['accounts:'] = ['Stored Account'];
      store.masterData['categories:expense'] = ['Stored Expense'];
      store.masterData['categories:income'] = ['Stored Income'];
      store.masterData['projects:'] = ['Stored Project'];

      final repository = _FakeTransactionRepository();
      final transactionController = _createController(repository);

      addTearDown(transactionController.dispose);

      final service = AppBootstrapService(
        store: store,
        transactionController: transactionController,
      );

      final result = await service.load();

      expect(store.initialized, isTrue);

      expect(store.ensuredSeeds, isEmpty);

      expect(result.accounts, ['Stored Account']);
      expect(result.expenseCategories, ['Stored Expense']);
      expect(result.incomeCategories, ['Stored Income']);
      expect(result.projects, ['Stored Project']);

      expect(transactionController.transactions, isEmpty);
      expect(repository.saved, isEmpty);
    },
  );
  test('bootstrap surfaces transaction loading failures', () async {
    final store = _FakeStore();
    final repository = _FakeTransactionRepository()..throwOnGet = true;

    final transactionController = _createController(repository);

    addTearDown(transactionController.dispose);

    final service = AppBootstrapService(
      store: store,
      transactionController: transactionController,
    );

    expect(
      service.load,
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('database unavailable'),
        ),
      ),
    );
  });
}
