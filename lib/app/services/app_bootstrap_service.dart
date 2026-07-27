import '../../core/database/local_store.dart';
import '../../features/master_data/domain/entities/account.dart';
import '../../features/master_data/domain/entities/local_profile.dart';
import '../../features/master_data/domain/entities/financial_book.dart';
import '../../features/master_data/domain/entities/household_member.dart';
import '../../features/transactions/domain/entities/transaction.dart';
import '../../features/transactions/presentation/controllers/transaction_controller.dart';

class AppBootstrapResult {
  const AppBootstrapResult({
    required this.accounts,
    required this.accountRecords,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.projects,
    required this.profile,
    required this.session,
    required this.financialBook,
    required this.householdMembers,
  });

  final List<String> accounts;
  final List<Account> accountRecords;
  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final List<String> projects;
  final LocalProfile? profile;
  final LocalSessionState session;
  final FinancialBook? financialBook;
  final List<HouseholdMember> householdMembers;
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
    bool requireProfile = false,
  }) async {
    await store.initialize();

    final profileRecord = requireProfile
        ? await store.getActiveLocalProfile()
        : null;
    final profile = profileRecord == null
        ? null
        : LocalProfile.fromRecord(profileRecord);
    if (profileRecord != null) {
      await store.ensureHouseholdForProfile(profileRecord);
    }
    final sessionRecord = requireProfile ? await store.getLocalSession() : null;
    final session = LocalSessionState(
      activeProfileId: sessionRecord?['active_profile_id'] as String?,
      onboardingCompleted:
          (sessionRecord?['onboarding_completed'] as num?)?.toInt() == 1,
      activeBookId: sessionRecord?['active_book_id'] as String?,
      activeMemberId: sessionRecord?['active_member_id'] as String?,
    );
    store.setActiveBookId(session.activeBookId);
    transactionController.setActiveContext(
      bookId: session.activeBookId,
      memberId: session.activeMemberId,
    );
    final bookRows = requireProfile
        ? await store.getFinancialBooks()
        : const <Map<String, Object?>>[];
    final activeBookRows = session.activeBookId == null
        ? const <Map<String, Object?>>[]
        : bookRows.where((row) => row['id'] == session.activeBookId).toList();
    final financialBook = activeBookRows.isEmpty
        ? null
        : FinancialBook.fromRecord(activeBookRows.first);
    final householdMembers = !requireProfile || session.activeBookId == null
        ? const <HouseholdMember>[]
        : (await store.getHouseholdMembers(
            bookId: session.activeBookId,
          )).map(HouseholdMember.fromRecord).toList();

    if (!requireProfile || profile != null) {
      if (requireProfile) {
        await store.ensureAccountSeeds(
          defaultAccounts,
          currencyCode: profile!.defaultCurrencyCode,
        );
      } else {
        await store.ensureMasterSeeds('accounts', defaultAccounts);
      }
    }

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

    final storedAccountNames = await store.getMasterNames('accounts');
    final accountRows = requireProfile
        ? await store.getAccounts()
        : const <Map<String, Object?>>[];
    final accountRecords = accountRows.isNotEmpty
        ? accountRows.map(Account.fromRecord).toList()
        : storedAccountNames.map((name) => Account(name: name)).toList();
    final accounts = accountRecords.map((account) => account.name).toList();

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
      accountRecords: List<Account>.unmodifiable(accountRecords),
      expenseCategories: List<String>.unmodifiable(expenseCategories),
      incomeCategories: List<String>.unmodifiable(incomeCategories),
      projects: List<String>.unmodifiable(projects),
      profile: profile,
      session: session,
      financialBook: financialBook,
      householdMembers: List<HouseholdMember>.unmodifiable(householdMembers),
    );
  }
}
