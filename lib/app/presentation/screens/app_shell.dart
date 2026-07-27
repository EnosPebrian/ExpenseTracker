import 'package:flutter/material.dart';

import '../../../core/database/local_store.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/design/app_colors.dart';
import '../../../features/analytics/domain/financial_summary.dart';
import '../../../features/assets/presentation/screens/asset_conversion_screen.dart';
import '../../../features/assets/presentation/screens/asset_management_screen.dart';
import '../../../features/assets/presentation/screens/assets_dashboard_screen.dart';
import '../../../features/assets/controllers/asset_price_controller.dart';
import '../../../features/assets/data/repositories/alpha_vantage_asset_price_repository.dart';
import '../../../features/assets/domain/services/asset_portfolio_calculator.dart';
import '../../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../../features/cloud_sharing/domain/cloud_models.dart';
import '../../../features/cloud_sharing/domain/cloud_sharing_repository.dart';
import '../../../features/cloud_sharing/presentation/controllers/cloud_sharing_controller.dart';
import '../../../features/cloud_sharing/presentation/widgets/cloud_sharing_section.dart';
import '../../../features/master_data/presentation/screens/accounts_page.dart';
import '../../../features/master_data/presentation/screens/local_profile_setup_page.dart';
import '../../../features/master_data/domain/entities/local_profile.dart';
import '../../../features/master_data/domain/entities/financial_book.dart';
import '../../../features/master_data/domain/entities/household_member.dart';
import '../../../features/master_data/presentation/screens/household_settings_page.dart';
import '../../../features/master_data/presentation/screens/categories_page.dart';
import '../../../features/master_data/presentation/screens/projects_page.dart';
import '../../../features/reports/presentation/screens/reports_page.dart';
import '../../../features/sync/data/local_sync_repository.dart';
import '../../../features/sync/data/initial_sync_store.dart';
import '../../../features/sync/data/local_initial_sync_repository.dart';
import '../../../features/sync/domain/initial_sync_coordinator.dart';
import '../../../features/sync/domain/initial_sync_models.dart';
import '../../../features/sync/domain/initial_sync_transport.dart';
import '../../../features/sync/domain/sync_coordinator.dart';
import '../../../features/sync/domain/sync_models.dart';
import '../../../features/sync/domain/sync_transport.dart';
import '../../../features/sync/presentation/controllers/sync_controller.dart';
import '../../../features/sync/presentation/controllers/initial_sync_controller.dart';
import '../../../features/tithe/presentation/screens/tithe_page.dart';
import '../../../features/tithe/domain/tithe_policy.dart';
import '../../../features/transactions/domain/entities/transaction.dart';
import '../../../features/transactions/data/repositories/local_transaction_repository.dart';
import '../../../features/transactions/presentation/edit/edit_transaction_screen.dart';
import '../../../features/transactions/presentation/edit/transaction_form.dart';
import '../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../../features/transactions/presentation/quick_add/quick_add_controller.dart';
import '../../../features/transactions/presentation/quick_add/quick_add_screen.dart';
import '../../../features/transactions/presentation/screens/transaction_detail_screen.dart';
import '../../../features/transactions/presentation/screens/transaction_list_screen.dart';
import '../../../features/master_data/presentation/controllers/master_data_controller.dart';
import '../../../features/analytics/domain/financial_period.dart';
import '../../../features/assets/controllers/asset_definition_controller.dart';
import '../../../features/assets/data/repositories/local_asset_definition_repository.dart';
import '../../services/app_bootstrap_service.dart';
import '../../data/default_master_data.dart';
import '../../data/default_transactions.dart';
import '../../data/default_asset_definitions.dart';
import '../widgets/app_navigation_scaffold.dart';
import '../widgets/app_bootstrap_error_view.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.cloudSharingRepository,
    required this.syncTransport,
    required this.initialSyncTransport,
  });

  final CloudSharingRepository cloudSharingRepository;
  final SyncTransport syncTransport;
  final InitialSyncTransport initialSyncTransport;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int selected = 0;
  bool loading = true;
  String? bootstrapError;
  LocalProfile? localProfile;
  FinancialBook? financialBook;
  List<HouseholdMember> householdMembers = const [];
  String? activeMemberId;

  late FinancialPeriod dashboardPeriod;

  late final LocalStore store = LocalStore();

  late final CloudSharingController cloudSharingController =
      CloudSharingController(
        repository: widget.cloudSharingRepository,
        onLinked: _persistCloudLink,
      );
  late final LocalSyncRepository syncRepository = LocalSyncRepository(store);
  late final LocalInitialSyncRepository initialSyncRepository =
      LocalInitialSyncRepository(
        syncRepository: syncRepository,
        store: InitialSyncStoreAdapter(store),
      );
  late final SyncController syncController = SyncController(
    SyncCoordinator(
      repository: syncRepository,
      transport: widget.syncTransport,
    ),
  );
  late final InitialSyncController initialSyncController =
      InitialSyncController(
        coordinator: InitialSyncCoordinator(
          repository: initialSyncRepository,
          transport: widget.initialSyncTransport,
        ),
        onReady: _initialSyncReady,
      );

  late final LocalAssetDefinitionRepository assetDefinitionRepository =
      LocalAssetDefinitionRepository(store);

  late final LocalTransactionRepository assetUsageTransactionRepository =
      LocalTransactionRepository(store);

  late final AssetDefinitionController assetDefinitionController =
      AssetDefinitionController(
        repository: assetDefinitionRepository,
        transactionsProvider: () =>
            assetUsageTransactionRepository.getAll(includeDeleted: true),
      );

  late final AlphaVantageAssetPriceRepository? assetPriceRepository =
      AppEnvironment.hasAlphaVantageApiKey
      ? AlphaVantageAssetPriceRepository(
          apiKey: AppEnvironment.alphaVantageApiKey,
        )
      : null;

  late final AssetPriceController assetPriceController = AssetPriceController(
    store: store,
    repository: assetPriceRepository,
  );

  late final transactionController = TransactionProviders.controller(
    store,
    assetDefinitionResolver: assetDefinitionController.definitionById,
    afterMutation: assetDefinitionController.reload,
  );
  late final masterDataController = MasterDataController(
    persistAccount: (account) => store.upsertAccount(account.toRecord()),
    persist:
        ({
          required String entity,
          required String name,
          String? previousName,
          String? categoryType,
        }) {
          return store.saveMasterName(
            entity,
            name,
            previousName: previousName,
            categoryType: categoryType,
          );
        },
  );

  late final bootstrapService = AppBootstrapService(
    store: store,
    transactionController: transactionController,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.onSyncMutation = syncController.scheduleSync;

    dashboardPeriod = FinancialPeriod.thisMonth(DateTime.now());

    transactionController.addListener(_onAppStateChanged);
    masterDataController.addListener(_onAppStateChanged);
    assetDefinitionController.addListener(_onAppStateChanged);
    assetPriceController.addListener(_onAppStateChanged);
    cloudSharingController.addListener(_onCloudStateChanged);

    _loadLocalData();
    cloudSharingController.initialize();
  }

  void _onAppStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onCloudStateChanged() {
    _onAppStateChanged();
    _configureInitialSyncContext();
  }

  Future<void> _openTransactionDetail(
    BuildContext context,
    Transaction transaction,
  ) {
    return TransactionDetailScreen.show(
      context,
      transaction: transaction,
      controller: transactionController,
      enteredByName: _memberName(transaction.enteredByMemberId),
      onEdit: (selectedTransaction) {
        EditTransactionScreen.show(
          context,
          transaction: selectedTransaction,
          controller: transactionController,
          options: transactionFormOptions,
        );
      },
    );
  }

  Future<void> _loadLocalData() async {
    try {
      final result = await bootstrapService.load(
        defaultAccounts: defaultAccountNames,
        defaultExpenseCategories: defaultExpenseCategories,
        defaultIncomeCategories: defaultIncomeCategories,
        defaultProjects: defaultProjectNames,
        seedTransactions: buildDefaultTransactions(),
        requireProfile: true,
      );

      await assetDefinitionController.initialize(
        seeds: buildDefaultAssetDefinitions(),
      );

      final assetDefinitionError = assetDefinitionController.error;

      if (assetDefinitionError != null) {
        throw StateError(assetDefinitionError);
      }

      await assetPriceController.load();

      if (!mounted) {
        return;
      }

      setState(() {
        masterDataController.replaceAll(
          accounts: result.accounts,
          accountRecords: result.accountRecords,
          expenseCategories: result.expenseCategories,
          incomeCategories: result.incomeCategories,
          projects: result.projects,
        );
        localProfile = result.profile;
        financialBook = result.financialBook;
        householdMembers = result.householdMembers;
        activeMemberId = result.session.activeMemberId;

        bootstrapError = null;
        loading = false;
      });
      await syncController.setBook(result.financialBook);
      await _configureInitialSyncContext();
    } catch (exception) {
      if (!mounted) {
        return;
      }

      setState(() {
        bootstrapError = exception.toString();
        loading = false;
      });
    }
  }

  Future<void> _retryBootstrap() async {
    setState(() {
      bootstrapError = null;
      loading = true;
    });

    await _loadLocalData();
  }

  Future<void> _completeLocalProfile(LocalProfile profile) async {
    await store.upsertLocalProfile(profile.toRecord());
    await store.saveLocalSession(
      activeProfileId: profile.id,
      onboardingCompleted: true,
    );
    if (!mounted) return;
    setState(() {
      localProfile = profile;
      loading = true;
    });
    await _loadLocalData();
  }

  String? _memberName(String? id) {
    if (id == null) return null;
    for (final member in householdMembers) {
      if (member.id == id) return member.displayName;
    }
    return 'Former member';
  }

  Future<void> _renameBook(String name) async {
    final current = financialBook;
    if (current == null) return;
    final updated = current.copyWith(
      name: name,
      updatedAt: DateTime.now(),
      version: current.version + 1,
      syncStatus: 'pending',
    );
    await store.upsertFinancialBook(updated.toRecord());
    if (mounted) setState(() => financialBook = updated);
  }

  Future<void> _addMember(String name) async {
    final book = financialBook;
    if (book == null) return;
    final member = HouseholdMember(bookId: book.id, displayName: name);
    await store.upsertHouseholdMember(member.toRecord());
    await _reloadMembers();
  }

  Future<void> _renameMember(HouseholdMember member, String name) async {
    await store.upsertHouseholdMember(
      member
          .copyWith(
            displayName: name,
            updatedAt: DateTime.now(),
            version: member.version + 1,
            syncStatus: 'pending',
          )
          .toRecord(),
    );
    await _reloadMembers();
  }

  Future<void> _selectActiveMember(HouseholdMember member) async {
    final profile = localProfile;
    final book = financialBook;
    if (profile == null || book == null) return;
    await store.saveLocalSession(
      activeProfileId: profile.id,
      onboardingCompleted: true,
      activeBookId: book.id,
      activeMemberId: member.id,
    );
    transactionController.setActiveContext(
      bookId: book.id,
      memberId: member.id,
    );
    if (mounted) setState(() => activeMemberId = member.id);
  }

  Future<void> _reloadMembers() async {
    final book = financialBook;
    if (book == null) return;
    final rows = await store.getHouseholdMembers(bookId: book.id);
    if (mounted) {
      setState(() {
        householdMembers = rows.map(HouseholdMember.fromRecord).toList();
      });
    }
  }

  Future<void> _persistCloudLink(CloudLinkResult result) async {
    final book = financialBook;
    if (book == null || book.id != result.bookId) return;
    final linkedBook = book.copyWith(remoteLinkedAt: result.linkedAt);
    await store.upsertFinancialBook(linkedBook.toRecord(), enqueueSync: false);
    await syncRepository.setInitializationState(
      linkedBook.id,
      SyncInitializationState.primaryUploadRequired,
    );
    final updatedMembers = <HouseholdMember>[];
    for (final member in householdMembers) {
      final updated = member.id == result.householdMemberId
          ? member.copyWith(authUserId: result.userId)
          : member;
      if (updated != member) {
        await store.upsertHouseholdMember(
          updated.toRecord(),
          enqueueSync: false,
        );
      }
      updatedMembers.add(updated);
    }
    if (mounted) {
      setState(() {
        financialBook = linkedBook;
        householdMembers = updatedMembers;
      });
    }
    await syncController.setBook(linkedBook, runWhenReady: false);
    await _configureInitialSyncContext();
  }

  Future<void> _configureInitialSyncContext() async {
    final book = financialBook;
    final memberships = cloudSharingController.memberships
        .where((membership) => membership.status == 'active')
        .toList();
    CloudBookMembership? primaryMembership;
    CloudBookMembership? secondaryMembership;
    for (final membership in memberships) {
      if (membership.bookId == book?.id) {
        primaryMembership = membership;
      } else {
        secondaryMembership ??= membership;
      }
    }
    await initialSyncController.setContext(
      primaryBook: book,
      primaryIsOwner: primaryMembership?.role == CloudMembershipRole.owner,
      secondaryBookId: secondaryMembership?.bookId,
      secondaryRole: secondaryMembership?.role.name,
      secondaryMemberId: secondaryMembership?.householdMemberId,
      authUserId: cloudSharingController.user?.id,
    );
  }

  Future<void> _initialSyncReady(
    String bookId,
    InitialSyncDirection direction,
  ) async {
    if (direction == InitialSyncDirection.upload) {
      await syncController.setBook(financialBook);
      return;
    }
    if (!mounted) return;
    setState(() => loading = true);
    await _loadLocalData();
  }

  Future<void> addTransaction(Transaction transaction) {
    return transactionController.createTransaction(transaction);
  }

  QuickAddConfig get quickAddConfig {
    final accounts = masterDataController.accounts;
    final expenses = masterDataController.expenseCategories;
    final incomes = masterDataController.incomeCategories;

    return QuickAddConfig(
      accounts: accounts,
      expenseCategories: expenses,
      incomeCategories: incomes,
      projects: masterDataController.projects,
      assetDefinitions: assetDefinitionController.definitions,
      assetMarketPrices: assetPriceController.prices,
      defaultProject: 'Life',
      defaultAccount: accounts.isEmpty ? null : accounts.first,
      defaultExpenseCategory: expenses.isEmpty ? null : expenses.first,
      defaultIncomeCategory: incomes.isEmpty ? null : incomes.first,
    );
  }

  TransactionFormOptions get transactionFormOptions {
    return TransactionFormOptions(
      accounts: masterDataController.accounts,
      expenseCategories: masterDataController.expenseCategories,
      incomeCategories: masterDataController.incomeCategories,
      projects: masterDataController.projects,
      assetDefinitions: assetDefinitionController.definitions,
      assetMarketPrices: assetPriceController.prices,
    );
  }

  Future<void> openQuickAdd(BuildContext context) {
    return QuickAddScreen.show(
      context,
      transactionController: transactionController,
      config: quickAddConfig,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.onSyncMutation = null;
    transactionController.removeListener(_onAppStateChanged);
    masterDataController.removeListener(_onAppStateChanged);
    assetDefinitionController.removeListener(_onAppStateChanged);
    assetPriceController.removeListener(_onAppStateChanged);
    cloudSharingController.removeListener(_onCloudStateChanged);

    transactionController.dispose();
    masterDataController.dispose();
    assetDefinitionController.dispose();
    assetPriceController.dispose();
    cloudSharingController.dispose();
    syncController.dispose();
    initialSyncController.dispose();
    assetPriceRepository?.close();
    store.close();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncController.onResume();
  }

  @override
  Widget build(BuildContext context) {
    final transactions = transactionController.transactions;

    final referenceDate = DateTime.now();

    final assetPortfolio = AssetPortfolioCalculator.calculate(
      transactions: transactions,
      marketPrices: assetPriceController.prices,
      assetDefinitions: assetDefinitionController.allDefinitions,
    );

    final currentMonthSummary = FinancialSummary.calculate(
      transactions: transactions,
      referenceDate: referenceDate,
      tithePolicy: TithePolicy.defaultPolicy,
    );

    final dashboardSummary = FinancialSummary.forPeriod(
      transactions: transactions,
      periodStart: dashboardPeriod.start,
      periodEndExclusive: dashboardPeriod.endExclusive,
      tithePolicy: TithePolicy.defaultPolicy,
    );

    final pages = [
      Dashboard(
        transactions: transactions,
        summary: dashboardSummary,
        referenceDate: referenceDate,
        period: dashboardPeriod,
        transactionChanges: transactionController,
        transactionsProvider: () {
          return transactionController.transactions;
        },
        onPeriodChanged: (period) {
          setState(() {
            dashboardPeriod = period;
          });
        },
        onOpen: (transaction) {
          _openTransactionDetail(context, transaction);
        },
      ),
      AssetsDashboardScreen(
        portfolio: assetPortfolio,
        priceController: assetPriceController,
        onManageAssets: () {
          AssetManagementScreen.show(
            context,
            controller: assetDefinitionController,
          );
        },
      ),
      TransactionListScreen(
        controller: transactionController,
        onEdit: (transaction) {
          EditTransactionScreen.show(
            context,
            transaction: transaction,
            controller: transactionController,
            options: transactionFormOptions,
          );
        },
      ),
      AccountsPage(
        accountRecords: masterDataController.accountRecords,
        transactions: transactions,
        defaultCurrencyCode: localProfile?.defaultCurrencyCode ?? 'IDR',
        onSave: masterDataController.saveAccount,
        members: householdMembers,
      ),
      CategoriesPage(
        expenseCategories: masterDataController.expenseCategories,
        incomeCategories: masterDataController.incomeCategories,
        onSave: masterDataController.save,
      ),
      AssetConversionScreen(
        accounts: masterDataController.accounts,
        assets: assetDefinitionController.definitions,
        marketPrices: assetPriceController.prices,
        onSave: addTransaction,
        existingTransactionsProvider: () => transactionController.transactions,
      ),
      ProjectsPage(
        projects: masterDataController.projects,
        onSave: masterDataController.save,
      ),
      TithePage(summary: currentMonthSummary),
      ReportsPage(summary: currentMonthSummary),
      if (financialBook != null)
        HouseholdSettingsPage(
          book: financialBook!,
          members: householdMembers,
          activeMemberId: activeMemberId,
          onRenameBook: _renameBook,
          onAddMember: _addMember,
          onRenameMember: _renameMember,
          onSelectActiveMember: _selectActiveMember,
          cloudSharingSection: CloudSharingSection(
            controller: cloudSharingController,
            book: financialBook!,
            members: householdMembers,
            activeMemberId: activeMemberId,
            syncController: syncController,
            initialSyncController: initialSyncController,
          ),
        )
      else
        const SizedBox.shrink(),
    ];

    if (loading || transactionController.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: violet)),
      );
    }

    final error = bootstrapError;

    if (error != null) {
      return AppBootstrapErrorView(message: error, onRetry: _retryBootstrap);
    }

    if (localProfile == null) {
      return LocalProfileSetupPage(onSave: _completeLocalProfile);
    }

    return AppNavigationScaffold(
      selected: selected,
      child: pages[selected],
      onSelect: (index) {
        setState(() {
          selected = index;
        });
      },
      onQuickAdd: () {
        openQuickAdd(context);
      },
    );
  }
}
