import '../../backup/domain/backup_models.dart';
import '../../budgets/domain/entities/monthly_category_budget.dart';
import '../../master_data/domain/entities/account.dart';
import '../../master_data/domain/services/account_balance_calculator.dart';
import '../../tithe/domain/tithe_policy.dart';
import '../../transactions/domain/entities/internal_transfer_link.dart';
import '../../transactions/domain/entities/transaction.dart';
import '../../transactions/domain/entities/transaction_import_rule.dart';
import '../../transactions/domain/services/internal_transfer_integrity_validator.dart';
import 'health_check_models.dart';

abstract interface class HealthCheckDataSource {
  Future<HealthCheckSnapshot> load();
}

class HealthCheckService {
  const HealthCheckService({required this.dataSource, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final HealthCheckDataSource dataSource;
  final DateTime Function() _now;

  Future<HealthCheckReport> run() async {
    final generatedAt = _now();
    try {
      final snapshot = await dataSource.load();
      return HealthCheckReport(
        generatedAt: generatedAt,
        sections: [
          _database(snapshot),
          _household(snapshot),
          _transactions(snapshot, generatedAt),
          _transfers(snapshot),
          _importInbox(snapshot),
          _rulesAndPlanning(snapshot, generatedAt),
          _sync(snapshot),
          _backup(snapshot),
        ],
      );
    } catch (_) {
      return HealthCheckReport(
        generatedAt: generatedAt,
        sections: [
          HealthCheckSection(
            id: 'database',
            title: 'Database',
            checks: const [
              HealthCheckItem(
                code: 'database.open',
                title: 'Local database',
                status: HealthCheckItemStatus.error,
                summary: 'Pilgrim could not read the local database.',
                suggestedAction:
                    'Close and reopen the app. Keep your existing data files intact.',
              ),
            ],
          ),
        ],
      );
    }
  }

  HealthCheckSection _database(HealthCheckSnapshot snapshot) {
    final matches = snapshot.schemaVersion == snapshot.expectedSchemaVersion;
    return HealthCheckSection(
      id: 'database',
      title: 'Database',
      checks: [
        const HealthCheckItem(
          code: 'database.open',
          title: 'Local database',
          status: HealthCheckItemStatus.healthy,
          summary: 'The local database opened successfully.',
        ),
        HealthCheckItem(
          code: 'database.schema_version',
          title: 'SQLite schema',
          status: matches
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: matches
              ? 'SQLite schema: v${snapshot.schemaVersion}'
              : 'SQLite schema v${snapshot.schemaVersion} does not match the expected v${snapshot.expectedSchemaVersion}.',
          suggestedAction: matches
              ? null
              : 'Update Pilgrim Tracker before continuing financial work.',
        ),
        const HealthCheckItem(
          code: 'database.core_tables',
          title: 'Core data access',
          status: HealthCheckItemStatus.healthy,
          summary: 'Core household records are readable.',
        ),
      ],
    );
  }

  HealthCheckSection _household(HealthCheckSnapshot snapshot) {
    final books = snapshot.rows('household');
    final activeSessionBook = snapshot.localSession['active_book_id'];
    final bookValid =
        books.length == 1 &&
        books.single['id'] == snapshot.bookId &&
        books.single['deleted_at'] == null &&
        activeSessionBook == snapshot.bookId;
    final members = snapshot.rows('members');
    final activeMembers = members.where((row) => row['deleted_at'] == null);
    var foreignRows = 0;
    for (final rows in [
      ...snapshot.records.values,
      snapshot.importSessions,
      snapshot.importDrafts,
    ]) {
      foreignRows += rows.where((row) {
        final bookId = row['book_id'];
        return bookId != null && bookId != snapshot.bookId;
      }).length;
    }
    return HealthCheckSection(
      id: 'household',
      title: 'Household',
      checks: [
        HealthCheckItem(
          code: 'household.active_identity',
          title: 'Active household',
          status: bookValid
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: bookValid
              ? 'The active household identity is consistent.'
              : 'The active household cannot be resolved safely.',
          suggestedAction: bookValid
              ? null
              : 'Stop editing and restore from a validated backup if reopening does not help.',
        ),
        HealthCheckItem(
          code: 'household.member_identity',
          title: 'Household members',
          status: activeMembers.isNotEmpty
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: activeMembers.isNotEmpty
              ? '${activeMembers.length} active household member${activeMembers.length == 1 ? '' : 's'} available.'
              : 'The household has no active member.',
        ),
        HealthCheckItem(
          code: 'household.scope',
          title: 'Household boundaries',
          status: foreignRows == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: foreignRows == 0
              ? 'No cross-household records were found.'
              : '$foreignRows record${foreignRows == 1 ? '' : 's'} cross the household boundary.',
        ),
      ],
    );
  }

  HealthCheckSection _transactions(HealthCheckSnapshot snapshot, DateTime now) {
    final accountRows = snapshot.rows('accounts');
    final categoryRows = snapshot.rows('categories');
    final projects = {
      for (final row in snapshot.rows('projects')) row['id'] as String: row,
    };
    final members = {
      for (final row in snapshot.rows('members')) row['id'] as String: row,
    };
    final definitions = {
      for (final row in snapshot.rows('asset_definitions'))
        row['id'] as String: row,
    };
    final accountNames = {
      for (final row in accountRows)
        (row['name'] as String).trim().toLowerCase(),
    };
    final categories = {
      for (final row in categoryRows)
        (row['name'] as String).trim().toLowerCase(): row,
    };
    final activeRows = snapshot
        .rows('transactions')
        .where((row) => row['deleted_at'] == null)
        .toList();
    final ids = <String>{};
    var invalidReferences = 0;
    var invalidIdentities = 0;
    final transactions = <Transaction>[];
    for (final row in activeRows) {
      final id = row['id'] as String?;
      if (id == null || id.isEmpty || !ids.add(id)) invalidIdentities++;
      try {
        final transaction = Transaction.fromRecord(row);
        transactions.add(transaction);
        if (transaction.bookId != snapshot.bookId ||
            !_accountReferenceExists(transaction, accountNames) ||
            !_categoryReferenceValid(transaction, categories) ||
            (transaction.projectId != null &&
                !projects.containsKey(transaction.projectId)) ||
            (transaction.enteredByMemberId != null &&
                !members.containsKey(transaction.enteredByMemberId)) ||
            (transaction.assetDefinitionId != null &&
                !definitions.containsKey(transaction.assetDefinitionId)) ||
            transaction.amount < 0 ||
            (transaction.type == TransactionType.assetConversion &&
                transaction.assetAction == null)) {
          invalidReferences++;
        }
      } catch (_) {
        invalidReferences++;
      }
    }

    var balanceErrors = 0;
    final accounts = <Account>[];
    for (final row in accountRows.where((row) => row['deleted_at'] == null)) {
      try {
        accounts.add(Account.fromRecord(row));
      } catch (_) {
        balanceErrors++;
      }
    }
    final start = DateTime(now.year, now.month);
    final end = now.month == 12
        ? DateTime(now.year + 1)
        : DateTime(now.year, now.month + 1);
    for (final account in accounts) {
      try {
        final opening = AccountBalanceCalculator.calculateAsOf(
          account: account,
          transactions: transactions,
          endExclusive: start,
        );
        final closing = AccountBalanceCalculator.calculateAsOf(
          account: account,
          transactions: transactions,
          endExclusive: end,
        );
        var movement = 0;
        for (final transaction in transactions) {
          if (!AccountBalanceCalculator.belongsToAccount(
                account,
                transaction,
              ) ||
              transaction.date.isBefore(start) ||
              !transaction.date.isBefore(end) ||
              !_onOrAfterOpening(account, transaction.date)) {
            continue;
          }
          movement += AccountBalanceCalculator.cashEffect(transaction);
        }
        final openingDate = account.openingBalanceDate;
        final openingAdjustment =
            openingDate != null &&
                !_localDate(openingDate).isBefore(start) &&
                _localDate(openingDate).isBefore(end)
            ? account.openingBalance
            : 0;
        if (opening + openingAdjustment + movement != closing) {
          balanceErrors++;
        }
      } catch (_) {
        balanceErrors++;
      }
    }

    return HealthCheckSection(
      id: 'transactions',
      title: 'Transactions',
      checks: [
        HealthCheckItem(
          code: 'transactions.invalid_reference',
          title: 'Transaction references',
          status: invalidReferences == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: invalidReferences == 0
              ? 'No invalid transaction references were found.'
              : '$invalidReferences transaction${invalidReferences == 1 ? '' : 's'} contain invalid references.',
          suggestedAction: invalidReferences == 0
              ? null
              : 'Avoid editing affected records and keep a current encrypted backup.',
        ),
        HealthCheckItem(
          code: 'transactions.duplicate_identity',
          title: 'Transaction identity',
          status: invalidIdentities == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: invalidIdentities == 0
              ? 'Live transaction identities are unique.'
              : '$invalidIdentities invalid or duplicate live transaction identities were found.',
        ),
        HealthCheckItem(
          code: 'transactions.account_reconciliation',
          title: 'Account reconciliation',
          status: balanceErrors == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: balanceErrors == 0
              ? '${accounts.length} account balance${accounts.length == 1 ? '' : 's'} reconciled for the current month.'
              : '$balanceErrors account balance${balanceErrors == 1 ? '' : 's'} could not be reconciled.',
        ),
      ],
    );
  }

  HealthCheckSection _transfers(HealthCheckSnapshot snapshot) {
    final transactions = <String, Transaction>{};
    for (final row in snapshot.rows('transactions')) {
      try {
        final value = Transaction.fromRecord(row);
        transactions[value.id] = value;
      } catch (_) {}
    }
    final accounts = <String, Account>{};
    for (final row in snapshot.rows('accounts')) {
      try {
        final value = Account.fromRecord(row);
        accounts[value.id] = value;
      } catch (_) {}
    }
    final links = <InternalTransferLink>[];
    var broken = 0;
    for (final row in snapshot.rows('transfer_links')) {
      try {
        links.add(InternalTransferLink.fromRecord(row));
      } catch (_) {
        if (row['deleted_at'] == null) broken++;
      }
    }
    final validator = const InternalTransferIntegrityValidator();
    for (final link in links.where((link) => link.isActive)) {
      final outgoing = transactions[link.outgoingTransactionId];
      final incoming = transactions[link.incomingTransactionId];
      final source = accounts[link.sourceAccountId];
      final destination = accounts[link.destinationAccountId];
      if (outgoing == null ||
          incoming == null ||
          source == null ||
          destination == null) {
        broken++;
        continue;
      }
      try {
        validator.validate(
          link: link,
          outgoing: outgoing,
          incoming: incoming,
          sourceAccount: source,
          destinationAccount: destination,
          existingLinks: links,
          replacedLinkId: link.id,
        );
      } catch (_) {
        broken++;
      }
    }
    final legacy = transactions.values
        .where(
          (transaction) =>
              transaction.deletedAt == null &&
              transaction.type == TransactionType.transfer,
        )
        .length;
    final activeLinks = links.where((link) => link.isActive).length;
    return HealthCheckSection(
      id: 'transfers',
      title: 'Transfers',
      checks: [
        HealthCheckItem(
          code: 'transfers.canonical_integrity',
          title: 'Canonical transfers',
          status: broken == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: broken == 0
              ? '$activeLinks canonical transfer${activeLinks == 1 ? '' : 's'} checked; no broken links found.'
              : '$broken canonical transfer${broken == 1 ? '' : 's'} have a broken relationship.',
          suggestedAction: broken == 0
              ? null
              : 'Review the related transactions; Health Check did not change them.',
        ),
        HealthCheckItem(
          code: 'transfers.legacy_count',
          title: 'Legacy transfers',
          status: legacy == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.info,
          summary: legacy == 0
              ? 'No legacy single-row transfers were found.'
              : '$legacy legacy transfer${legacy == 1 ? '' : 's'} remain readable and unchanged.',
        ),
      ],
    );
  }

  HealthCheckSection _importInbox(HealthCheckSnapshot snapshot) {
    final sessions = <String, Map<String, Object?>>{
      for (final row in snapshot.importSessions) row['id'] as String: row,
    };
    final accounts = {
      for (final row in snapshot.rows('accounts')) row['id'] as String: row,
    };
    final categories = {
      for (final row in snapshot.rows('categories')) row['id'] as String: row,
    };
    var lifecycleIssues = 0;
    var identityIssues = 0;
    var sourceIssues = 0;
    for (final session in snapshot.importSessions) {
      final state = session['state'];
      if (session['book_id'] != snapshot.bookId ||
          (state == 'completed' && session['completed_at'] == null) ||
          (state == 'discarded' && session['deleted_at'] == null) ||
          ((state == 'pendingReview' || state == 'readyToCommit') &&
              (session['completed_at'] != null ||
                  session['deleted_at'] != null))) {
        lifecycleIssues++;
      }
      final destination = session['destination_account_id'] as String?;
      if (destination != null &&
          (!accounts.containsKey(destination) ||
              accounts[destination]!['book_id'] != snapshot.bookId ||
              accounts[destination]!['deleted_at'] != null)) {
        lifecycleIssues++;
      }
      if ((session['source_fingerprint'] as String? ?? '').trim().isEmpty) {
        sourceIssues++;
      }
    }
    for (final draft in snapshot.importDrafts) {
      final session = sessions[draft['session_id']];
      if (session == null || draft['book_id'] != snapshot.bookId) {
        lifecycleIssues++;
        continue;
      }
      final finalId = draft['deterministic_transaction_id'] as String?;
      final binding = draft['deterministic_transaction_account_id'] as String?;
      if ((finalId == null) != (binding == null)) identityIssues++;
      if (binding != null &&
          (binding != session['destination_account_id'] ||
              !accounts.containsKey(binding) ||
              accounts[binding]!['book_id'] != snapshot.bookId)) {
        identityIssues++;
      }
      final included = (draft['included'] as num?)?.toInt() != 0;
      if (session['state'] == 'completed' &&
          included &&
          draft['deleted_at'] == null &&
          (finalId == null || binding == null)) {
        identityIssues++;
      }
      if (session['state'] == 'discarded' && draft['deleted_at'] == null) {
        lifecycleIssues++;
      }
      final category = draft['category_id'] as String?;
      if (category != null &&
          (!categories.containsKey(category) ||
              categories[category]!['book_id'] != snapshot.bookId)) {
        lifecycleIssues++;
      }
      if ((draft['id'] as String? ?? '').trim().isEmpty ||
          (draft['source_row_identity'] as String? ?? '').trim().isEmpty) {
        sourceIssues++;
      }
    }
    final pending = snapshot.importSessions
        .where(
          (row) =>
              row['deleted_at'] == null &&
              (row['state'] == 'pendingReview' ||
                  row['state'] == 'readyToCommit'),
        )
        .length;
    return HealthCheckSection(
      id: 'import_inbox',
      title: 'Import Inbox',
      checks: [
        HealthCheckItem(
          code: 'inbox.lifecycle',
          title: 'Review lifecycle',
          status: lifecycleIssues == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: lifecycleIssues == 0
              ? 'Import session relationships and lifecycle are consistent.'
              : '$lifecycleIssues Import Inbox lifecycle issue${lifecycleIssues == 1 ? '' : 's'} were found.',
        ),
        HealthCheckItem(
          code: 'inbox.deferred_identity',
          title: 'Deferred transaction identity',
          status: identityIssues == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: identityIssues == 0
              ? 'Draft transaction identities and account bindings are consistent.'
              : '$identityIssues draft identit${identityIssues == 1 ? 'y is' : 'ies are'} inconsistent.',
        ),
        HealthCheckItem(
          code: 'inbox.source_identity',
          title: 'Import source identity',
          status: sourceIssues == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: sourceIssues == 0
              ? 'Import source identities are structurally usable.'
              : '$sourceIssues import source identit${sourceIssues == 1 ? 'y is' : 'ies are'} incomplete.',
        ),
        HealthCheckItem(
          code: 'inbox.pending_sessions',
          title: 'Pending imports',
          status: pending == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.info,
          summary: pending == 0
              ? 'No imports are waiting for review.'
              : '$pending import session${pending == 1 ? '' : 's'} waiting for review.',
          suggestedAction: pending == 0
              ? null
              : 'Open Import Inbox to continue.',
        ),
      ],
    );
  }

  HealthCheckSection _rulesAndPlanning(
    HealthCheckSnapshot snapshot,
    DateTime now,
  ) {
    final accounts = {
      for (final row in snapshot.rows('accounts')) row['id'] as String: row,
    };
    final categories = {
      for (final row in snapshot.rows('categories')) row['id'] as String: row,
    };
    final members = {
      for (final row in snapshot.rows('members')) row['id'] as String: row,
    };
    var ruleIssues = 0;
    final semanticKeys = <String>{};
    for (final row in snapshot.rows('transaction_import_rules')) {
      final active =
          row['deleted_at'] == null && (row['enabled'] as num?)?.toInt() != 0;
      if (!active) continue;
      try {
        final rule = TransactionImportRule.fromRecord(row);
        final category = categories[rule.categoryId];
        final account = rule.accountId == null
            ? null
            : accounts[rule.accountId];
        if (rule.bookId != snapshot.bookId ||
            category == null ||
            category['deleted_at'] != null ||
            category['book_id'] != snapshot.bookId ||
            category['category_type'] != rule.transactionType.name ||
            (rule.accountId != null &&
                (account == null ||
                    account['deleted_at'] != null ||
                    account['book_id'] != snapshot.bookId)) ||
            !semanticKeys.add(rule.semanticKey)) {
          ruleIssues++;
        }
      } catch (_) {
        ruleIssues++;
      }
    }

    var budgetIssues = 0;
    final budgetKeys = <String>{};
    for (final row in snapshot.rows('budgets')) {
      if (row['deleted_at'] != null) continue;
      try {
        final budget = MonthlyCategoryBudget.fromRecord(row);
        final category = categories[budget.categoryId];
        if (budget.bookId != snapshot.bookId ||
            category == null ||
            category['book_id'] != snapshot.bookId ||
            category['deleted_at'] != null ||
            category['category_type'] != 'expense' ||
            budget.limitMinor <= 0 ||
            budget.currencyCode !=
                snapshot.rows('household').single['base_currency_code'] ||
            !budgetKeys.add('${budget.categoryId}|${budget.monthKey}')) {
          budgetIssues++;
        }
      } catch (_) {
        budgetIssues++;
      }
    }
    var referenceIssues = 0;
    for (final account in accounts.values) {
      final owner = account['owner_member_id'] as String?;
      if (account['book_id'] != snapshot.bookId ||
          (owner != null &&
              (!members.containsKey(owner) ||
                  members[owner]!['book_id'] != snapshot.bookId))) {
        referenceIssues++;
      }
    }
    var titheValid = true;
    try {
      final rate = TithePolicy.defaultPolicy.rateFor(now);
      titheValid = rate >= 0 && rate <= 1;
    } catch (_) {
      titheValid = false;
    }
    return HealthCheckSection(
      id: 'planning',
      title: 'Rules & planning',
      checks: [
        HealthCheckItem(
          code: 'rules.reference_integrity',
          title: 'Import rules',
          status: ruleIssues == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: ruleIssues == 0
              ? 'Active import-rule references are valid.'
              : '$ruleIssues active import rule${ruleIssues == 1 ? '' : 's'} have invalid references.',
        ),
        HealthCheckItem(
          code: 'budgets.reference_integrity',
          title: 'Budgets',
          status: budgetIssues == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: budgetIssues == 0
              ? 'Active budget references are valid.'
              : '$budgetIssues active budget${budgetIssues == 1 ? '' : 's'} have invalid structure.',
        ),
        HealthCheckItem(
          code: 'master_data.reference_integrity',
          title: 'Account ownership',
          status: referenceIssues == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: referenceIssues == 0
              ? 'Account ownership references are valid.'
              : '$referenceIssues account ownership reference${referenceIssues == 1 ? '' : 's'} are invalid.',
        ),
        HealthCheckItem(
          code: 'tithe.policy',
          title: 'Tithe configuration',
          status: titheValid
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.error,
          summary: titheValid
              ? 'The current tithe policy resolves successfully.'
              : 'The current tithe policy cannot be resolved.',
        ),
      ],
    );
  }

  HealthCheckSection _sync(HealthCheckSnapshot snapshot) {
    final sync = snapshot.sync;
    final localOnly = sync.cloudState == HealthCloudState.localOnly;
    final cloudStatus = switch (sync.cloudState) {
      HealthCloudState.localOnly => const HealthCheckItem(
        code: 'sync.mode',
        title: 'Sync mode',
        status: HealthCheckItemStatus.healthy,
        summary: 'Sync mode: Local only. Cloud access is not required.',
      ),
      HealthCloudState.ready => const HealthCheckItem(
        code: 'sync.mode',
        title: 'Sync mode',
        status: HealthCheckItemStatus.healthy,
        summary: 'Cloud sharing is ready.',
      ),
      HealthCloudState.pending => const HealthCheckItem(
        code: 'sync.mode',
        title: 'Sync mode',
        status: HealthCheckItemStatus.info,
        summary: 'Cloud sharing is ready with local work pending.',
      ),
      HealthCloudState.unavailable => const HealthCheckItem(
        code: 'sync.cloud_availability',
        title: 'Cloud availability',
        status: HealthCheckItemStatus.warning,
        summary:
            'Cloud sync is currently unavailable. Local data remains usable.',
        suggestedAction: 'Try Sync now later from Household settings.',
      ),
      HealthCloudState.signedOut => const HealthCheckItem(
        code: 'sync.cloud_availability',
        title: 'Cloud sign-in',
        status: HealthCheckItemStatus.warning,
        summary: 'This device is signed out of cloud sharing.',
        suggestedAction: 'Open Household settings to sign in.',
      ),
      HealthCloudState.notConfigured => const HealthCheckItem(
        code: 'sync.cloud_availability',
        title: 'Cloud configuration',
        status: HealthCheckItemStatus.warning,
        summary: 'This build is not configured for cloud sharing.',
      ),
      HealthCloudState.initializing => const HealthCheckItem(
        code: 'sync.initialization',
        title: 'Cloud setup',
        status: HealthCheckItemStatus.info,
        summary: 'Initial cloud synchronization is still in progress.',
      ),
      HealthCloudState.failed => const HealthCheckItem(
        code: 'sync.cloud_availability',
        title: 'Cloud sync',
        status: HealthCheckItemStatus.warning,
        summary:
            'Cloud synchronization needs attention. Local data remains usable.',
        suggestedAction: 'Open Household settings to review sync status.',
      ),
    };
    return HealthCheckSection(
      id: 'sync',
      title: 'Sync',
      checks: [
        cloudStatus,
        HealthCheckItem(
          code: 'sync.pending_outbox',
          title: 'Pending changes',
          status: sync.pendingOutboxCount == 0 || localOnly
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.warning,
          summary: sync.pendingOutboxCount == 0
              ? 'No changes are waiting to sync.'
              : '${sync.pendingOutboxCount} change${sync.pendingOutboxCount == 1 ? ' is' : 's are'} waiting to sync.',
        ),
        HealthCheckItem(
          code: 'sync.failed_outbox',
          title: 'Failed changes',
          status: sync.failedOutboxCount == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.warning,
          summary: sync.failedOutboxCount == 0
              ? 'No failed sync changes were found.'
              : '${sync.failedOutboxCount} change${sync.failedOutboxCount == 1 ? '' : 's'} need sync attention.',
        ),
        HealthCheckItem(
          code: 'sync.unresolved_conflicts',
          title: 'Conflicts',
          status: sync.unresolvedConflictCount == 0
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.warning,
          summary: sync.unresolvedConflictCount == 0
              ? 'No unresolved conflicts.'
              : '${sync.unresolvedConflictCount} conflict${sync.unresolvedConflictCount == 1 ? '' : 's'} need review.',
          suggestedAction: sync.unresolvedConflictCount == 0
              ? null
              : 'Review conflicts from Household settings.',
        ),
        HealthCheckItem(
          code: 'sync.last_success',
          title: 'Last successful sync',
          status: localOnly || sync.lastSuccessfulSyncAt != null
              ? HealthCheckItemStatus.healthy
              : HealthCheckItemStatus.info,
          summary: localOnly
              ? 'Not applicable in local-only mode.'
              : sync.lastSuccessfulSyncAt == null
              ? 'No successful sync time is available on this device.'
              : 'A successful sync has been recorded on this device.',
        ),
      ],
    );
  }

  HealthCheckSection _backup(
    HealthCheckSnapshot snapshot,
  ) => HealthCheckSection(
    id: 'backup',
    title: 'Backup',
    checks: [
      HealthCheckItem(
        code: 'backup.format',
        title: 'Encrypted backup support',
        status: snapshot.backupFormatVersion == portableBackupFormatVersion
            ? HealthCheckItemStatus.healthy
            : HealthCheckItemStatus.error,
        summary: 'Backup format supported: v${snapshot.backupFormatVersion}',
      ),
      const HealthCheckItem(
        code: 'backup.status',
        title: 'Recent backup status',
        status: HealthCheckItemStatus.info,
        summary: 'Recent backup status is not tracked on this device.',
        suggestedAction: 'Open Backup & Export to create an encrypted backup.',
      ),
    ],
  );

  static bool _accountReferenceExists(
    Transaction transaction,
    Set<String> accountNames,
  ) {
    final recordedAccount = transaction.account;
    final direct = recordedAccount.trim().toLowerCase();
    if (accountNames.contains(direct)) return true;
    final route = recordedAccount.split('->');
    if (transaction.type == TransactionType.assetConversion &&
        route.length == 2) {
      final cashAccount = switch (transaction.assetAction) {
        AssetAction.buy => route.first,
        AssetAction.sell => route.last,
        null => recordedAccount,
      };
      return accountNames.contains(cashAccount.trim().toLowerCase());
    }
    return route.length == 2 &&
        accountNames.contains(route.first.trim().toLowerCase()) &&
        accountNames.contains(route.last.trim().toLowerCase());
  }

  static bool _categoryReferenceValid(
    Transaction transaction,
    Map<String, Map<String, Object?>> categories,
  ) {
    if (transaction.type == TransactionType.assetConversion) return true;
    final category = categories[transaction.category.trim().toLowerCase()];
    if (category == null) return false;
    if (transaction.type == TransactionType.expense) {
      return category['category_type'] == 'expense';
    }
    if (transaction.type == TransactionType.income) {
      return category['category_type'] == 'income';
    }
    return true;
  }

  static bool _onOrAfterOpening(Account account, DateTime transactionDate) {
    final opening = account.openingBalanceDate;
    return opening == null ||
        !_localDate(transactionDate).isBefore(_localDate(opening));
  }

  static DateTime _localDate(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
