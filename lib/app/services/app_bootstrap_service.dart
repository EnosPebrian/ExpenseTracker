import '../../core/database/local_store.dart';
import '../../features/master_data/domain/entities/account.dart';
import '../../features/master_data/domain/entities/local_profile.dart';
import '../../features/master_data/domain/entities/financial_book.dart';
import '../../features/master_data/domain/entities/household_member.dart';
import '../../features/master_data/domain/entities/financial_project.dart';
import '../../features/transactions/presentation/controllers/transaction_controller.dart';

class AppBootstrapResult {
  const AppBootstrapResult({
    required this.accounts,
    required this.accountRecords,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.projects,
    required this.projectRecords,
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
  final List<FinancialProject> projectRecords;
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

  Future<AppBootstrapResult> load({bool requireProfile = false}) async {
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

    final projectRecords = (await store.getProjectRecords())
        .map(FinancialProject.fromRecord)
        .toList();
    final projects = projectRecords.map((project) => project.name).toList();

    await transactionController.load();

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
      projectRecords: List<FinancialProject>.unmodifiable(projectRecords),
      profile: profile,
      session: session,
      financialBook: financialBook,
      householdMembers: List<HouseholdMember>.unmodifiable(householdMembers),
    );
  }
}
