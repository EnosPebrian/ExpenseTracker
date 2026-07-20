import '../../core/database/local_store.dart';
import '../../features/transactions/domain/entities/transaction.dart';
import '../../features/transactions/presentation/controllers/transaction_controller.dart';

class AppBootstrapResult {
  const AppBootstrapResult({
    required this.accounts,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.projects,
  });

  final List<String> accounts;
  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final List<String> projects;
}

class AppBootstrapService {
  const AppBootstrapService({
    required this.store,
    required this.transactionController,
  });

  final LocalStore store;
  final TransactionController transactionController;

  Future<AppBootstrapResult> load({
    required List<String> defaultAccounts,
    required List<String> defaultExpenseCategories,
    required List<String> defaultIncomeCategories,
    required List<String> defaultProjects,
    required List<Transaction> seedTransactions,
  }) async {
    await store.initialize();

    await store.ensureMasterSeeds('accounts', defaultAccounts);

    await store.ensureMasterSeeds(
      'categories',
      defaultExpenseCategories,
      categoryType: 'expense',
    );

    await store.ensureMasterSeeds(
      'categories',
      defaultIncomeCategories,
      categoryType: 'income',
    );

    await store.ensureMasterSeeds('projects', defaultProjects);

    final accounts = await store.getMasterNames('accounts');

    final expenseCategories = await store.getMasterNames(
      'categories',
      categoryType: 'expense',
    );

    final incomeCategories = await store.getMasterNames(
      'categories',
      categoryType: 'income',
    );

    final projects = await store.getMasterNames('projects');

    await transactionController.load(seed: seedTransactions);

    final transactionError = transactionController.error;

    if (transactionError != null) {
      throw StateError('Unable to load transactions: $transactionError');
    }

    return AppBootstrapResult(
      accounts: List<String>.unmodifiable(accounts),
      expenseCategories: List<String>.unmodifiable(expenseCategories),
      incomeCategories: List<String>.unmodifiable(incomeCategories),
      projects: List<String>.unmodifiable(projects),
    );
  }
}
