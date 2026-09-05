import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
import '../../../features/backup/data/local_household_backup_store.dart';
import '../../../features/backup/data/initial_sync_backup_recovery_reader.dart';
import '../../../features/backup/data/portable_file_service.dart';
import '../../../features/backup/domain/backup_recovery_service.dart';
import '../../../features/backup/domain/household_backup_service.dart';
import '../../../features/backup/domain/restore_lifecycle_service.dart';
import '../../../features/backup/presentation/controllers/backup_export_controller.dart';
import '../../../features/backup/presentation/controllers/backup_recovery_controller.dart';
import '../../../features/backup/presentation/controllers/restore_lifecycle_controller.dart';
import '../../../features/backup/presentation/screens/backup_export_screen.dart';
import '../../../features/budgets/data/local_monthly_budget_repository.dart';
import '../../../features/budgets/presentation/controllers/monthly_budget_controller.dart';
import '../../../features/budgets/presentation/screens/budgets_page.dart';
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
import '../../../features/master_data/domain/entities/financial_project.dart';
import '../../../features/master_data/presentation/screens/household_settings_page.dart';
import '../../../features/master_data/presentation/screens/categories_page.dart';
import '../../../features/master_data/presentation/screens/projects_page.dart';
import '../../../features/health/data/local_health_check_data_source.dart';
import '../../../features/health/domain/health_check_service.dart';
import '../../../features/health/presentation/controllers/health_check_controller.dart';
import '../../../features/health/presentation/screens/health_check_screen.dart';
import '../../../features/reports/presentation/screens/reports_page.dart';
import '../../../features/reports/presentation/controllers/financial_statement_controller.dart';
import '../../../features/reports/presentation/screens/statements_screen.dart';
import '../../../features/sync/data/local_sync_repository.dart';
import '../../../features/sync/data/initial_sync_store.dart';
import '../../../features/sync/data/local_initial_sync_repository.dart';
import '../../../features/sync/domain/initial_sync_coordinator.dart';
import '../../../features/sync/domain/initial_sync_models.dart';
import '../../../features/sync/domain/initial_sync_transport.dart';
import '../../../features/sync/domain/sync_coordinator.dart';
import '../../../features/sync/domain/sync_models.dart';
import '../../../features/sync/domain/sync_transport.dart';
import '../../../features/sync/domain/conflict_resolution_service.dart';
import '../../../features/sync/presentation/controllers/sync_controller.dart';
import '../../../features/sync/presentation/controllers/sync_conflict_controller.dart';
import '../../../features/sync/presentation/screens/conflict_review_screen.dart';
import '../../../features/sync/presentation/controllers/initial_sync_controller.dart';
import '../../../features/tithe/presentation/screens/tithe_page.dart';
import '../../../features/tithe/domain/tithe_policy.dart';
import '../../../features/telegram_integration/domain/telegram_integration_repository.dart';
import '../../../features/telegram_integration/presentation/screens/integrations_screen.dart';
import '../../../features/transactions/domain/entities/transaction.dart';
import '../../../features/transactions/data/repositories/local_transaction_repository.dart';
import '../../../features/transactions/data/transaction_import_file_service.dart';
import '../../../features/transactions/data/document_import_file_service.dart';
import '../../../features/transactions/data/local_transaction_import_rule_repository.dart';
import '../../../features/transactions/data/local_import_review_repository.dart';
import '../../../features/transactions/data/supabase_document_extraction_provider.dart';
import '../../../features/transactions/domain/extraction/document_extraction_models.dart';
import '../../../features/transactions/domain/extraction/document_extraction_provider.dart';
import '../../../features/transactions/domain/usecases/transaction_usecases.dart';
import '../../../features/transactions/domain/import/transaction_import_models.dart';
import '../../../features/transactions/domain/services/transaction_import_rule_engine.dart';
import '../../../features/transactions/presentation/controllers/transaction_import_controller.dart';
import '../../../features/transactions/presentation/controllers/internal_transfer_review_controller.dart';
import '../../../features/transactions/presentation/controllers/document_import_controller.dart';
import '../../../features/transactions/presentation/import/document_import_screen.dart';
import '../../../features/transactions/presentation/import/transaction_import_screen.dart';
import '../../../features/transactions/presentation/import/import_review_inbox_screen.dart';
import '../../../features/transactions/presentation/import/transaction_import_rules_screen.dart';
import '../../../features/transactions/presentation/edit/edit_transaction_screen.dart';
import '../../../features/transactions/presentation/edit/transaction_form.dart';
import '../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../../features/transactions/presentation/quick_add/quick_add_controller.dart';
import '../../../features/transactions/presentation/quick_add/quick_add_screen.dart';
import '../../../features/transactions/presentation/screens/transaction_detail_screen.dart';
import '../../../features/transactions/presentation/screens/internal_transfer_review_screen.dart';
import '../../../features/transactions/presentation/screens/transaction_list_screen.dart';
import '../../../features/master_data/presentation/controllers/master_data_controller.dart';
import '../../../features/analytics/domain/financial_period.dart';
import '../../../features/assets/controllers/asset_definition_controller.dart';
import '../../../features/assets/data/repositories/local_asset_definition_repository.dart';
import '../../services/app_bootstrap_service.dart';
import '../../data/default_asset_definitions.dart';
import '../widgets/app_navigation_scaffold.dart';
import '../widgets/app_bootstrap_error_view.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.cloudSharingRepository,
    required this.syncTransport,
    required this.initialSyncTransport,
    this.telegramIntegrationRepository =
        const UnavailableTelegramIntegrationRepository(),
  });

  final CloudSharingRepository cloudSharingRepository;
  final SyncTransport syncTransport;
  final InitialSyncTransport initialSyncTransport;
  final TelegramIntegrationRepository telegramIntegrationRepository;

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
  Set<String> currentSessionImportedTransactionIds = const {};

  late FinancialPeriod dashboardPeriod;

  late final LocalStore store = LocalStore();

  late final BackupExportController backupExportController =
      BackupExportController(
        backupService: HouseholdBackupService(LocalHouseholdBackupStore(store)),
        fileService: const PortableFileService(),
        onRestored: _refreshAfterRestore,
      );

  late final BackupRecoveryController backupRecoveryController =
      BackupRecoveryController(
        backupService: HouseholdBackupService(LocalHouseholdBackupStore(store)),
        recoveryService: BackupRecoveryService(
          store: LocalHouseholdBackupStore(store),
          remoteReader: InitialSyncBackupRecoveryReader(
            widget.initialSyncTransport,
          ),
        ),
        fileService: const PortableFileService(),
        onRecovered: _refreshSyncedData,
        onViewTransactions: () {
          if (mounted) setState(() => selected = 2);
        },
      );

  late final RestoreLifecycleController restoreLifecycleController =
      RestoreLifecycleController(
        service: RestoreLifecycleService(LocalHouseholdBackupStore(store)),
        bootstrapCloud: _bootstrapRestoredClone,
      );

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
    onRemoteDataApplied: _refreshSyncedData,
  );
  late final HealthCheckController healthCheckController =
      HealthCheckController(
        HealthCheckService(
          dataSource: LocalHealthCheckDataSource(
            store: store,
            bookId: () => financialBook?.id ?? '',
            syncStatus: () => syncController.status,
            lastSuccessfulSyncAt: () => syncController.lastSuccessfulSyncAt,
          ),
        ),
      );
  late final SyncConflictController? syncConflictController =
      widget.syncTransport is ConflictResolutionTransport
      ? SyncConflictController(
          service: ConflictResolutionService(
            repository: syncRepository,
            transport: widget.syncTransport as ConflictResolutionTransport,
          ),
          afterResolution: syncController.syncNow,
        )
      : null;
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
  late final monthlyBudgetController = MonthlyBudgetController(
    repository: LocalMonthlyBudgetRepository(store),
  );
  late final masterDataController = MasterDataController(
    persistAccount: (account) => store.upsertAccount(account.toRecord()),
    loadProjectRecords: () async => (await store.getProjectRecords())
        .map(FinancialProject.fromRecord)
        .toList(),
    loadCategoryRecords: () => store.getCategoryRecords(includeDeleted: true),
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
    monthlyBudgetController.addListener(_onAppStateChanged);
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
      final result = await bootstrapService.load(requireProfile: true);

      await assetDefinitionController.initialize(
        seeds: buildDefaultAssetDefinitions(),
        preserveExistingDefinitionsOnSeedConflict: true,
      );

      final assetDefinitionError = assetDefinitionController.error;

      if (assetDefinitionError != null) {
        throw StateError(assetDefinitionError);
      }

      await assetPriceController.load();
      final allCategoryRows = await store.getCategoryRecords(
        includeDeleted: true,
        bookId: result.financialBook?.id,
      );
      final categoryRows = allCategoryRows
          .where((row) => row['category_type'] == 'expense')
          .toList(growable: false);
      await monthlyBudgetController.load(
        bookId: result.financialBook?.id,
        categoryNames: {
          for (final row in categoryRows)
            row['id'] as String: row['name'] as String,
        },
        activeCategoryIds: {
          for (final row in categoryRows)
            if (row['deleted_at'] == null) row['id'] as String,
        },
        currencyCode: result.financialBook?.baseCurrencyCode ?? 'IDR',
        transactions: transactionController.transactions,
        pairedTransactionIds: transactionController.pairedTransactionIds,
      );
      if (result.financialBook != null) {
        await backupExportController.load(result.financialBook!.id);
        backupRecoveryController.load(result.financialBook!.id);
        await restoreLifecycleController.load(result.financialBook!.id);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        masterDataController.replaceAll(
          accounts: result.accounts,
          accountRecords: result.accountRecords,
          expenseCategories: result.expenseCategories,
          incomeCategories: result.incomeCategories,
          expenseCategoryIdsByName: _categoryIdsByName(
            allCategoryRows,
            'expense',
          ),
          incomeCategoryIdsByName: _categoryIdsByName(
            allCategoryRows,
            'income',
          ),
          projects: result.projects,
          projectRecords: result.projectRecords,
        );
        localProfile = result.profile;
        financialBook = result.financialBook;
        householdMembers = result.householdMembers;
        activeMemberId = result.session.activeMemberId;

        bootstrapError = null;
        loading = false;
      });
      await syncController.setBook(result.financialBook);
      await syncConflictController?.setBook(result.financialBook?.id);
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

  Future<void> _refreshSyncedData({bool reloadBackup = true}) async {
    final result = await bootstrapService.load(requireProfile: true);
    await assetDefinitionController.reload();
    final allCategoryRows = await store.getCategoryRecords(
      includeDeleted: true,
      bookId: result.financialBook?.id,
    );
    final categoryRows = allCategoryRows
        .where((row) => row['category_type'] == 'expense')
        .toList(growable: false);
    await monthlyBudgetController.load(
      bookId: result.financialBook?.id,
      categoryNames: {
        for (final row in categoryRows)
          row['id'] as String: row['name'] as String,
      },
      activeCategoryIds: {
        for (final row in categoryRows)
          if (row['deleted_at'] == null) row['id'] as String,
      },
      currencyCode: result.financialBook?.baseCurrencyCode ?? 'IDR',
      transactions: transactionController.transactions,
      pairedTransactionIds: transactionController.pairedTransactionIds,
    );
    final assetDefinitionError = assetDefinitionController.error;
    if (assetDefinitionError != null) {
      throw StateError(assetDefinitionError);
    }
    if (reloadBackup && result.financialBook != null) {
      await backupExportController.load(result.financialBook!.id);
      backupRecoveryController.load(result.financialBook!.id);
    }
    if (result.financialBook != null) {
      await restoreLifecycleController.load(result.financialBook!.id);
    }
    if (!mounted) return;
    setState(() {
      masterDataController.replaceAll(
        accounts: result.accounts,
        accountRecords: result.accountRecords,
        expenseCategories: result.expenseCategories,
        incomeCategories: result.incomeCategories,
        expenseCategoryIdsByName: _categoryIdsByName(
          allCategoryRows,
          'expense',
        ),
        incomeCategoryIdsByName: _categoryIdsByName(
          allCategoryRows,
          'income',
        ),
        projects: result.projects,
        projectRecords: result.projectRecords,
      );
      localProfile = result.profile;
      financialBook = result.financialBook;
      householdMembers = result.householdMembers;
      activeMemberId = result.session.activeMemberId;
    });
  }

  Future<void> _refreshAfterRestore() async {
    await _refreshSyncedData(reloadBackup: false);
    await syncController.setBook(financialBook, runWhenReady: false);
    await syncConflictController?.setBook(financialBook?.id);
    await _configureInitialSyncContext();
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

  Future<void> _bootstrapRestoredClone(RestoreLifecycleClone clone) async {
    await _refreshAfterRestore();
    final book = financialBook;
    HouseholdMember? member;
    for (final candidate in householdMembers) {
      if (candidate.id == activeMemberId) {
        member = candidate;
        break;
      }
    }
    if (book == null || book.id != clone.book.id || member == null) {
      throw StateError('The recovery clone could not be activated locally.');
    }
    if (cloudSharingController.user == null) {
      throw StateError('Sign in before creating a new shared household.');
    }

    await cloudSharingController.linkHousehold(
      book: book,
      activeMember: member,
    );
    final linkedMembership = cloudSharingController.memberships.any(
      (membership) =>
          membership.bookId == clone.book.id &&
          membership.status == 'active' &&
          membership.role == CloudMembershipRole.owner,
    );
    if (cloudSharingController.error != null || !linkedMembership) {
      throw StateError(
        cloudSharingController.error ??
            'The new hosted household owner membership was not created.',
      );
    }

    await _configureInitialSyncContext();
    if (!initialSyncController.canUpload) {
      throw StateError(
        'The new hosted household did not enter the protected initial-upload state.',
      );
    }
    await initialSyncController.upload(confirmed: true);
    if (initialSyncController.lastResult?.success != true) {
      throw StateError(
        initialSyncController.error ?? 'Initial upload did not complete.',
      );
    }
    await syncController.setBook(financialBook);
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
      hostedBookIds: memberships
          .map((membership) => membership.bookId)
          .toList(),
      hostedRoles: {
        for (final membership in memberships)
          membership.bookId: membership.role.name,
      },
      hostedMemberIds: {
        for (final membership in memberships)
          membership.bookId: membership.householdMemberId,
      },
      cloudConfigured: cloudSharingController.diagnostics.isConfigured,
      remoteStateLoaded: cloudSharingController.remoteStateLoaded,
      remoteStateError: cloudSharingController.error,
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
      expenseCategoryIdsByName:
          masterDataController.expenseCategoryIdsByName,
      incomeCategoryIdsByName: masterDataController.incomeCategoryIdsByName,
      projects: masterDataController.projects,
      projectIdsByName: masterDataController.projectIdsByName,
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
      expenseCategoryIdsByName:
          masterDataController.expenseCategoryIdsByName,
      incomeCategoryIdsByName: masterDataController.incomeCategoryIdsByName,
      projects: masterDataController.projects,
      projectIdsByName: masterDataController.projectIdsByName,
      assetDefinitions: assetDefinitionController.definitions,
      assetMarketPrices: assetPriceController.prices,
    );
  }

  static Map<String, String> _categoryIdsByName(
    Iterable<Map<String, Object?>> rows,
    String type,
  ) => {
    for (final row in rows)
      if (row['deleted_at'] == null && row['category_type'] == type)
        row['name'] as String: row['id'] as String,
  };

  Future<void> openQuickAdd(BuildContext context) {
    return QuickAddScreen.show(
      context,
      transactionController: transactionController,
      config: quickAddConfig,
      onAddAccount: () => setState(() => selected = 3),
      onAddCategory: () => setState(() => selected = 4),
    );
  }

  Future<void> openCsvImport(BuildContext context) async {
    final fileService = TransactionImportFileService();
    final controller = _createTransactionImportController(fileService.pick);
    if (controller == null) return;
    await TransactionImportScreen.show(
      context,
      controller: controller,
      onViewImported: (ids) {
        Navigator.of(context).pop();
        setState(() {
          currentSessionImportedTransactionIds = ids.toSet();
          selected = 2;
        });
      },
    );
    controller.dispose();
  }

  Future<void> openInternalTransferReview(BuildContext context) async {
    final service = transactionController.internalTransfers;
    if (service == null) return;
    final controller = InternalTransferReviewController(
      transactions: List.of(transactionController.transactions),
      accounts: List.of(masterDataController.accountRecords),
      links: List.of(transactionController.transferLinks),
      service: service,
      afterMutation: _refreshSyncedData,
    );
    await controller.scan();
    if (!context.mounted) {
      controller.dispose();
      return;
    }
    await InternalTransferReviewScreen.show(context, controller: controller);
    controller.dispose();
    await transactionController.load();
  }

  TransactionImportController? _createTransactionImportController(
    Future<SelectedCsvFile?> Function() pickFile,
  ) {
    final book = financialBook;
    if (book == null) return null;
    final repository = assetUsageTransactionRepository;
    return TransactionImportController(
      pickFile: pickFile,
      importBatch: ImportTransactionsBatch(repository),
      existingTransactions: () => repository.getAll(includeDeleted: true),
      accounts: masterDataController.accountRecords,
      expenseCategories: masterDataController.expenseCategories,
      incomeCategories: masterDataController.incomeCategories,
      activeBookId: book.id,
      activeMemberId: activeMemberId,
      internalTransfers: transactionController.internalTransfers,
      existingTransferLinks: () async =>
          transactionController.internalTransfers?.getLinks() ?? const [],
      importReviewRepository: LocalImportReviewRepository(store),
      hasUnresolvedSyncConflict: () async =>
          await store.getUnresolvedSyncConflictCount(book.id) > 0,
      importRules: () => LocalTransactionImportRuleRepository(
        store,
      ).getAll(bookId: book.id, activeOnly: true),
      saveImportRule: LocalTransactionImportRuleRepository(store).save,
      ruleCategories: () async {
        final rows = await store.getCategoryRecords(
          bookId: book.id,
          includeDeleted: true,
        );
        return {
          for (final row in rows)
            row['id'] as String: ImportRuleCategory(
              id: row['id'] as String,
              bookId: row['book_id'] as String,
              name: row['name'] as String,
              type: row['category_type'] == 'income'
                  ? TransactionType.income
                  : TransactionType.expense,
              available: row['deleted_at'] == null,
            ),
        };
      },
      refreshBeforeAnalysis: () async {
        if (!syncController.canSync) {
          return syncController.status == SyncStatus.localOnly;
        }
        await syncController.syncNow();
        return syncController.status == SyncStatus.synced ||
            syncController.status == SyncStatus.pending ||
            syncController.status == SyncStatus.conflict;
      },
      afterImport: _refreshSyncedData,
    );
  }

  Future<void> openDocumentImport(
    BuildContext context,
    FinancialDocumentType type,
  ) async {
    final transactionController = _createTransactionImportController(
      () async => null,
    );
    if (transactionController == null) return;
    final DocumentExtractionProvider provider =
        AppEnvironment.hasSupabaseConfiguration
        ? SupabaseDocumentExtractionProvider(Supabase.instance.client)
        : const UnavailableDocumentExtractionProvider();
    final controller = DocumentImportController(
      type: type,
      provider: provider,
      fileService: DocumentImportFileService(),
      transactions: transactionController,
    );
    await DocumentImportScreen.show(
      context,
      controller: controller,
      onViewImported: (ids) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        setState(() {
          currentSessionImportedTransactionIds = ids.toSet();
          selected = 2;
        });
      },
    );
    controller.dispose();
    transactionController.dispose();
  }

  Future<void> openTransactionImport(BuildContext context) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Import transactions')),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Import Inbox'),
              subtitle: const Text('Resume saved transaction drafts'),
              onTap: () => Navigator.pop(context, 'inbox'),
            ),
            ListTile(
              leading: const Icon(Icons.table_view),
              title: const Text('CSV'),
              onTap: () => Navigator.pop(context, 'csv'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Receipt / invoice photo'),
              onTap: () => Navigator.pop(context, 'receipt'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance),
              title: const Text('Bank statement PDF / images'),
              onTap: () => Navigator.pop(context, 'statement'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (source) {
      case 'inbox':
        await openImportInbox(context);
        break;
      case 'csv':
        await openCsvImport(context);
        break;
      case 'receipt':
        await openDocumentImport(context, FinancialDocumentType.receiptInvoice);
        break;
      case 'statement':
        await openDocumentImport(context, FinancialDocumentType.bankStatement);
        break;
      default:
        break;
    }
  }

  Future<void> openImportInbox(BuildContext context) async {
    final book = financialBook;
    if (book == null) return;
    final repository = LocalImportReviewRepository(store);
    await ImportReviewInboxScreen.show(
      context,
      repository: repository,
      bookId: book.id,
      onReview: (sessionId) => openSavedImportReview(context, sessionId),
    );
  }

  Future<void> openSavedImportReview(
    BuildContext context,
    String sessionId,
  ) async {
    final repository = LocalImportReviewRepository(store);
    final bundle = await repository.load(sessionId);
    if (bundle == null || !context.mounted) return;
    final controller = _createTransactionImportController(() async => null);
    if (controller == null) return;
    await controller.loadSavedReview(bundle);
    if (!context.mounted) {
      controller.dispose();
      return;
    }
    if (controller.reviewBundle?.session.terminal == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This import was already completed on another device.'),
        ),
      );
      controller.dispose();
      return;
    }
    await TransactionImportScreen.showPrepared(
      context,
      controller: controller,
      title: bundle.session.title,
      sourceSummary: const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Resumed from the Import Inbox. The original source file is not stored. '
            'Rules, duplicates, and possible transfers were checked again using current data.',
          ),
        ),
      ),
      onViewImported: (ids) {
        Navigator.of(context).pop();
        setState(() {
          currentSessionImportedTransactionIds = ids.toSet();
          selected = 2;
        });
      },
    );
    controller.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.onSyncMutation = null;
    transactionController.removeListener(_onAppStateChanged);
    masterDataController.removeListener(_onAppStateChanged);
    assetDefinitionController.removeListener(_onAppStateChanged);
    assetPriceController.removeListener(_onAppStateChanged);
    monthlyBudgetController.removeListener(_onAppStateChanged);
    cloudSharingController.removeListener(_onCloudStateChanged);

    transactionController.dispose();
    masterDataController.dispose();
    assetDefinitionController.dispose();
    assetPriceController.dispose();
    monthlyBudgetController.dispose();
    cloudSharingController.dispose();
    syncController.dispose();
    syncConflictController?.dispose();
    initialSyncController.dispose();
    backupExportController.dispose();
    backupRecoveryController.dispose();
    restoreLifecycleController.dispose();
    healthCheckController.dispose();
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
    final displayTransactions = transactionController.displayTransactions;
    monthlyBudgetController.updateTransactions(
      transactions,
      pairedTransactionIds: transactionController.pairedTransactionIds,
    );

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
      transferLinks: transactionController.transferLinks,
    );

    final dashboardSummary = FinancialSummary.forPeriod(
      transactions: transactions,
      periodStart: dashboardPeriod.start,
      periodEndExclusive: dashboardPeriod.endExclusive,
      tithePolicy: TithePolicy.defaultPolicy,
      transferLinks: transactionController.transferLinks,
    );

    final pages = [
      Dashboard(
        transactions: displayTransactions,
        hasAccounts: masterDataController.accountRecords.isNotEmpty,
        summary: dashboardSummary,
        referenceDate: referenceDate,
        period: dashboardPeriod,
        transactionChanges: transactionController,
        transactionsProvider: () {
          return transactionController.displayTransactions;
        },
        onPeriodChanged: (period) {
          setState(() {
            dashboardPeriod = period;
          });
        },
        onOpen: (transaction) {
          _openTransactionDetail(context, transaction);
        },
        onAddAccount: () => setState(() => selected = 3),
        onAddTransaction: () => openQuickAdd(context),
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
        importedTransactionIds: currentSessionImportedTransactionIds,
        onImportCsv: () => openTransactionImport(context),
        onReviewTransfers: () => openInternalTransferReview(context),
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
        transactions: displayTransactions,
        defaultCurrencyCode: localProfile?.defaultCurrencyCode ?? 'IDR',
        onSave: masterDataController.saveAccount,
        members: householdMembers,
      ),
      CategoriesPage(
        expenseCategories: masterDataController.expenseCategories,
        incomeCategories: masterDataController.incomeCategories,
        onSave: masterDataController.save,
        onManageImportRules: financialBook == null
            ? null
            : () => TransactionImportRulesScreen.show(
                context,
                store: store,
                bookId: financialBook!.id,
                accounts: masterDataController.accountRecords,
              ),
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
        projectIdsByName: masterDataController.projectIdsByName,
        transactions: transactions,
        currencyCode: localProfile?.defaultCurrencyCode ?? 'IDR',
        onSave: masterDataController.save,
      ),
      BudgetsPage(
        controller: monthlyBudgetController,
        currencyCode: financialBook?.baseCurrencyCode ?? 'IDR',
      ),
      TithePage(summary: currentMonthSummary),
      ReportsPage(
        summary: currentMonthSummary,
        onOpenStatements: financialBook == null
            ? null
            : () => StatementsScreen.show(
                context,
                FinancialStatementController(
                  book: financialBook!,
                  accounts: masterDataController.accountRecords,
                  transactions: transactionController.transactions,
                  transferLinks: transactionController.transferLinks,
                  budgets: monthlyBudgetController.budgets,
                  categoryNamesById: monthlyBudgetController.categoryNames,
                  localDataWarning:
                      financialBook!.remoteLinkedAt != null &&
                      syncController.status != SyncStatus.synced,
                ),
              ),
      ),
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
            backupExportController: backupExportController,
            restoreLifecycleController: restoreLifecycleController,
            onOpenRecovery: () => setState(() => selected = 12),
            onReviewConflicts: syncConflictController == null
                ? null
                : () => ConflictReviewScreen.show(
                    context,
                    syncConflictController!,
                  ),
          ),
        )
      else
        const SizedBox.shrink(),
      if (financialBook != null && activeMemberId != null)
        IntegrationsScreen(
          repository: widget.telegramIntegrationRepository,
          bookId: financialBook!.id,
          memberId: activeMemberId!,
        )
      else
        const SizedBox.shrink(),
      BackupExportScreen(
        controller: backupExportController,
        recoveryController: backupRecoveryController,
        restoreLifecycleController: restoreLifecycleController,
        authenticatedEmail: cloudSharingController.user?.email,
        onOpenHousehold: () => setState(() => selected = 10),
      ),
      HealthCheckScreen(
        controller: healthCheckController,
        onOpenConflicts: syncConflictController == null
            ? null
            : () => ConflictReviewScreen.show(context, syncConflictController!),
        onOpenImportInbox: () => openImportInbox(context),
        onOpenBackup: () => setState(() => selected = 12),
        onOpenHousehold: () => setState(() => selected = 10),
      ),
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
