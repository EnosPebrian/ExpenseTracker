import 'package:uuid/uuid.dart';

import '../../analytics/domain/financial_summary.dart';
import '../../assets/domain/entities/asset_definition.dart';
import '../../assets/domain/entities/asset_market_price.dart';
import '../../assets/domain/services/asset_portfolio_calculator.dart';
import '../../master_data/domain/entities/account.dart';
import '../../master_data/domain/services/account_balance_calculator.dart';
import '../../tithe/domain/tithe_policy.dart';
import '../../transactions/domain/entities/transaction.dart';
import '../../transactions/domain/entities/internal_transfer_link.dart';
import 'backup_models.dart';

class HouseholdBackupIntegrity {
  const HouseholdBackupIntegrity._();

  static const _forbiddenFields = {
    'access_token',
    'refresh_token',
    'otp',
    'password',
    'api_key',
    'remote_linked_at',
    'auth_user_id',
    'sync_status',
    'device_id',
  };

  static Map<String, List<Map<String, Object?>>> sanitize(
    Map<String, List<Map<String, Object?>>> source,
  ) {
    return {
      for (final key in portableBackupEntityKeys)
        key: (source[key] ?? const [])
            .map(
              (record) => Map<String, Object?>.fromEntries(
                record.entries.where(
                  (entry) =>
                      !_isForbiddenField(entry.key) &&
                      !entry.key.startsWith('_'),
                ),
              ),
            )
            .toList(growable: false),
    };
  }

  static void validate(Map<String, List<Map<String, Object?>>> snapshot) {
    final households = snapshot['household'] ?? const [];
    if (households.length != 1) {
      throw const BackupValidationException(
        'A backup must contain exactly one household.',
      );
    }
    final household = households.single;
    final bookId = _requiredString(household, 'id', 'household');
    _requiredString(household, 'name', 'household');
    final baseCurrency = _requiredString(
      household,
      'base_currency_code',
      'household',
    );

    for (final key in portableBackupEntityKeys.skip(1)) {
      final ids = <String>{};
      for (final record in snapshot[key] ?? const []) {
        if (record['book_id'] != bookId) {
          throw BackupValidationException(
            '$key contains a record outside the selected household.',
          );
        }
        if (key != 'manual_market_prices') {
          final id = _requiredString(record, 'id', key);
          if (!ids.add(id)) {
            throw BackupValidationException('$key contains duplicate ID $id.');
          }
        }
      }
    }

    final members = snapshot['members'] ?? const [];
    final memberIds = _ids(members);
    if (!members.any((member) => member['deleted_at'] == null)) {
      throw const BackupValidationException(
        'The household must contain at least one active member.',
      );
    }

    final accounts = snapshot['accounts'] ?? const [];
    final accountNames = <String>{};
    for (final account in accounts) {
      final name = _requiredString(account, 'name', 'accounts');
      accountNames.add(name.toLowerCase());
      final owner = account['owner_member_id'] as String?;
      if (owner != null && !memberIds.contains(owner)) {
        throw BackupValidationException(
          'Account $name references a missing household member.',
        );
      }
      if (account['opening_balance'] is! int) {
        throw BackupValidationException(
          'Account $name has an invalid opening balance.',
        );
      }
    }

    final categories = snapshot['categories'] ?? const [];
    final categoryIds = _ids(categories);
    final categoryTypes = <String, String>{};
    for (final category in categories) {
      _requiredString(category, 'name', 'categories');
      categoryTypes[category['id'] as String] =
          category['category_type'] as String? ?? '';
    }
    final activeBudgetKeys = <String>{};
    for (final budget in snapshot['budgets'] ?? const []) {
      final id = _requiredString(budget, 'id', 'budgets');
      final categoryId = _requiredString(budget, 'category_id', 'budgets');
      if (!categoryIds.contains(categoryId)) {
        throw BackupValidationException(
          'Budget $id references a missing category.',
        );
      }
      if (categoryTypes[categoryId] != 'expense') {
        throw BackupValidationException(
          'Budget $id must reference an expense category.',
        );
      }
      final monthStart = _requiredString(budget, 'month_start', 'budgets');
      final parsedMonth = DateTime.tryParse(monthStart);
      final note = budget['note'];
      if (!RegExp(r'^\d{4}-\d{2}-01$').hasMatch(monthStart) ||
          parsedMonth == null ||
          parsedMonth.day != 1 ||
          budget['limit_minor'] is! int ||
          (budget['limit_minor'] as int) <= 0 ||
          budget['currency_code'] != baseCurrency ||
          (note != null && (note is! String || note.length > 120))) {
        throw BackupValidationException('Budget $id is invalid.');
      }
      if (budget['deleted_at'] == null &&
          !activeBudgetKeys.add('$categoryId:$monthStart')) {
        throw const BackupValidationException(
          'Budgets contain duplicate active category-month records.',
        );
      }
    }
    final accountIds = _ids(accounts);
    final activeRuleKeys = <String>{};
    for (final rule in snapshot['transaction_import_rules'] ?? const []) {
      final id = _requiredString(rule, 'id', 'transaction_import_rules');
      final type = _requiredString(
        rule,
        'transaction_type',
        'transaction_import_rules',
      );
      final categoryId = _requiredString(
        rule,
        'category_id',
        'transaction_import_rules',
      );
      final accountId = rule['account_id'] as String?;
      final pattern = _requiredString(
        rule,
        'pattern_key',
        'transaction_import_rules',
      );
      if (!categoryIds.contains(categoryId) ||
          categoryTypes[categoryId] != type) {
        throw BackupValidationException(
          'Import rule $id references a missing or incompatible category.',
        );
      }
      if (accountId != null && !accountIds.contains(accountId)) {
        throw BackupValidationException(
          'Import rule $id references a missing account.',
        );
      }
      if (!const {'expense', 'income'}.contains(type) ||
          !const {
            'description',
            'reference',
            'merchantHint',
            'descriptionOrReference',
          }.contains(rule['match_field']) ||
          !const {
            'contains',
            'equals',
            'startsWith',
          }.contains(rule['match_operator']) ||
          rule['enabled'] is! int ||
          rule['priority'] is! int ||
          pattern.length > 160) {
        throw BackupValidationException('Import rule $id is invalid.');
      }
      final semanticKey = [
        type,
        rule['match_field'],
        rule['match_operator'],
        pattern,
        accountId ?? '',
      ].join('|');
      if (rule['deleted_at'] == null && !activeRuleKeys.add(semanticKey)) {
        throw const BackupValidationException(
          'Import rules contain duplicate active match definitions.',
        );
      }
    }
    final projectIds = _ids(snapshot['projects'] ?? const []);
    final assetDefinitionIds = _ids(snapshot['asset_definitions'] ?? const []);
    final transactions = snapshot['transactions'] ?? const [];
    final transactionIds = _ids(transactions);

    for (final record in transactions) {
      final id = _requiredString(record, 'id', 'transactions');
      final type = _requiredString(record, 'transaction_type', 'transactions');
      final amount = record['amount'];
      if (amount is! int || amount < 0) {
        throw BackupValidationException(
          'Transaction $id has an invalid financial amount.',
        );
      }
      if (record['transaction_date'] is! int) {
        throw BackupValidationException('Transaction $id has an invalid date.');
      }
      final enteredBy = record['entered_by_member_id'] as String?;
      if (enteredBy != null && !memberIds.contains(enteredBy)) {
        throw BackupValidationException(
          'Transaction $id references a missing household member.',
        );
      }
      final projectId = record['project_id'] as String?;
      if (projectId != null && !projectIds.contains(projectId)) {
        throw BackupValidationException(
          'Transaction $id references a missing project.',
        );
      }
      final relatedId = record['related_transaction_id'] as String?;
      if (relatedId != null && !transactionIds.contains(relatedId)) {
        throw BackupValidationException(
          'Transaction $id references a missing related transaction.',
        );
      }
      final definitionId = record['asset_definition_id'] as String?;
      if (definitionId != null && !assetDefinitionIds.contains(definitionId)) {
        throw BackupValidationException(
          'Transaction $id references a missing asset definition.',
        );
      }
      if (type == 'assetConversion') {
        final quantity = record['quantity'];
        if (quantity is! num || quantity <= 0) {
          throw BackupValidationException(
            'Asset transaction $id has an invalid quantity.',
          );
        }
      }
      if (type == 'income' || type == 'expense') {
        _requiredString(record, 'category', 'transactions');
        // `category` is a historical name snapshot, not a foreign-key ID.
        // A removed definition must not invalidate an otherwise valid ledger
        // row or prevent disaster-recovery export.
        final account = _requiredString(record, 'account', 'transactions');
        if (!accountNames.contains(account.toLowerCase())) {
          throw BackupValidationException(
            'Transaction $id references a missing account.',
          );
        }
      } else if (type == 'assetConversion') {
        final account = _cashAccountName(record);
        if (account.isNotEmpty &&
            !accountNames.contains(account.toLowerCase())) {
          throw BackupValidationException(
            'Asset transaction $id references a missing cash account.',
          );
        }
      }
    }

    final transactionsById = {
      for (final record in transactions) record['id'] as String: record,
    };
    final accountsById = {
      for (final record in accounts) record['id'] as String: record,
    };
    final activeLegIds = <String>{};
    for (final link in snapshot['transfer_links'] ?? const []) {
      final id = _requiredString(link, 'id', 'transfer_links');
      final outgoingId = _requiredString(
        link,
        'outgoing_transaction_id',
        'transfer_links',
      );
      final incomingId = _requiredString(
        link,
        'incoming_transaction_id',
        'transfer_links',
      );
      final sourceId = _requiredString(
        link,
        'source_account_id',
        'transfer_links',
      );
      final destinationId = _requiredString(
        link,
        'destination_account_id',
        'transfer_links',
      );
      final outgoing = transactionsById[outgoingId];
      final incoming = transactionsById[incomingId];
      final sourceAccount = accountsById[sourceId];
      final destinationAccount = accountsById[destinationId];
      final amount = link['amount'];
      final active = link['deleted_at'] == null;
      if (outgoingId == incomingId ||
          sourceId == destinationId ||
          outgoing == null ||
          incoming == null ||
          sourceAccount == null ||
          destinationAccount == null ||
          amount is! int ||
          amount <= 0 ||
          outgoing['transaction_type'] != 'expense' ||
          incoming['transaction_type'] != 'income' ||
          outgoing['amount'] != amount ||
          incoming['amount'] != amount ||
          outgoing['account'] != sourceAccount['name'] ||
          incoming['account'] != destinationAccount['name'] ||
          sourceAccount['currency_code'] !=
              destinationAccount['currency_code'] ||
          sourceAccount['currency_code'] != link['currency_code'] ||
          (active &&
              (!activeLegIds.add(outgoingId) ||
                  !activeLegIds.add(incomingId)))) {
        throw BackupValidationException(
          'Internal transfer $id is invalid or incomplete.',
        );
      }
    }

    final priceKeys = <String>{};
    for (final price in snapshot['manual_market_prices'] ?? const []) {
      final assetKey = _requiredString(
        price,
        'asset_key',
        'manual_market_prices',
      );
      if (!priceKeys.add(assetKey)) {
        throw BackupValidationException(
          'manual_market_prices contains duplicate asset key $assetKey.',
        );
      }
      if (price['price_minor'] is! int || (price['price_minor'] as int) <= 0) {
        throw const BackupValidationException(
          'A manual market price contains an invalid amount.',
        );
      }
    }
  }

  static List<ReferenceIntegrityIssue> referenceIssues(
    Map<String, List<Map<String, Object?>>> snapshot,
  ) {
    final categories = snapshot['categories'] ?? const [];
    final byName = <String, List<Map<String, Object?>>>{};
    for (final category in categories) {
      final name = (category['name'] as String? ?? '').trim().toLowerCase();
      if (name.isNotEmpty) (byName[name] ??= []).add(category);
    }
    final issues = <ReferenceIntegrityIssue>[];
    for (final transaction in snapshot['transactions'] ?? const []) {
      if (transaction['transaction_type'] != 'income' &&
          transaction['transaction_type'] != 'expense') {
        continue;
      }
      final id = transaction['id'] as String? ?? 'unknown';
      final category = (transaction['category'] as String? ?? '').trim();
      if (category.isEmpty) {
        issues.add(
          ReferenceIntegrityIssue(
            severity: ReferenceIssueSeverity.information,
            state: ReferenceState.nullValue,
            entityId: id,
            message: 'Transaction $id is uncategorized.',
          ),
        );
        continue;
      }
      final matches = byName[category.toLowerCase()] ?? const [];
      final sameBook = matches.where(
        (row) => row['book_id'] == transaction['book_id'],
      );
      if (sameBook.isNotEmpty) {
        if (sameBook.every((row) => row['deleted_at'] != null)) {
          issues.add(
            ReferenceIntegrityIssue(
              severity: ReferenceIssueSeverity.information,
              state: ReferenceState.softDeleted,
              entityId: id,
              message: 'Transaction $id uses a deleted historical category.',
            ),
          );
        }
        continue;
      }
      if (matches.isNotEmpty) {
        issues.add(
          ReferenceIntegrityIssue(
            severity: ReferenceIssueSeverity.fatal,
            state: ReferenceState.crossBook,
            entityId: id,
            message: 'Transaction $id has a category from another household.',
          ),
        );
      } else {
        issues.add(
          ReferenceIntegrityIssue(
            severity: ReferenceIssueSeverity.warning,
            state: ReferenceState.absent,
            entityId: id,
            message:
                'Transaction $id keeps a historical category that is no longer '
                'in this household.',
          ),
        );
      }
    }
    return issues;
  }

  static Map<String, Object?> financialSummary(
    Map<String, List<Map<String, Object?>>> snapshot,
  ) {
    final transactions = (snapshot['transactions'] ?? const [])
        .map(
          (record) => Transaction.fromRecord({
            ...record,
            'device_id': record['device_id'] ?? 'backup-device',
            'sync_status': record['sync_status'] ?? 'local_only',
          }),
        )
        .toList(growable: false);
    final activeTransactions = transactions
        .where((transaction) => transaction.deletedAt == null)
        .toList(growable: false);
    final accounts = (snapshot['accounts'] ?? const [])
        .map(Account.fromRecord)
        .toList(growable: false);
    final definitions = (snapshot['asset_definitions'] ?? const [])
        .map(
          (record) => AssetDefinition.fromRecord({
            ...record,
            'device_id': record['device_id'] ?? 'backup-device',
            'sync_status': record['sync_status'] ?? 'local_only',
          }),
        )
        .toList(growable: false);
    final prices = (snapshot['manual_market_prices'] ?? const [])
        .map(AssetMarketPrice.fromRecord)
        .toList(growable: false);

    final summary = FinancialSummary.forPeriod(
      transactions: activeTransactions,
      periodStart: DateTime(1900),
      periodEndExclusive: DateTime(3000),
      tithePolicy: TithePolicy.defaultPolicy,
      transferLinks: (snapshot['transfer_links'] ?? const []).map(
        InternalTransferLink.fromRecord,
      ),
    );
    final portfolio = AssetPortfolioCalculator.calculate(
      transactions: activeTransactions,
      assetDefinitions: definitions,
      marketPrices: prices,
    );
    final tithe = activeTransactions
        .where((transaction) => transaction.type == TransactionType.income)
        .fold<int>(
          0,
          (total, transaction) =>
              total +
              (transaction.amount *
                      TithePolicy.defaultPolicy.rateFor(transaction.date))
                  .round(),
        );
    final accountBalances = <String, int>{
      for (final account in accounts)
        account.id: AccountBalanceCalculator.calculate(
          account: account,
          transactions: activeTransactions,
        ),
    };
    final quantities = <String, String>{
      for (final holding in portfolio.holdings)
        holding.assetDefinitionId ?? holding.assetKey: _decimal(
          holding.quantity,
        ),
    };

    return {
      'accountBalances': accountBalances,
      'income': summary.periodIncome,
      'expenses': summary.periodExpenses,
      'cashFlow': summary.periodNetCashFlow,
      'tithe': tithe,
      'assetQuantities': quantities,
      'assetCostBasis': portfolio.totalCostBasis,
      'assetRealizedGains': portfolio.totalRealizedGain,
      'assetUnrealizedGains': portfolio.totalUnrealizedGain,
      'linkedFeeRelationships': activeTransactions
          .where((transaction) => transaction.relatedTransactionId != null)
          .length,
    };
  }

  static Map<String, int> deletedStateCounts(
    Map<String, List<Map<String, Object?>>> snapshot,
  ) => {
    for (final key in portableBackupEntityKeys)
      key: (snapshot[key] ?? const [])
          .where((record) => record['deleted_at'] != null)
          .length,
  };

  static Map<String, List<Map<String, Object?>>> prepareForRestore(
    Map<String, List<Map<String, Object?>>> snapshot, {
    bool remapAsCopy = false,
  }) {
    final source = sanitize(snapshot);
    final prepared = remapAsCopy ? _remapAsCopy(source) : source;
    final bookId = prepared['household']!.single['id'] as String;
    return {
      for (final entry in prepared.entries)
        entry.key: entry.value
            .map((record) {
              final restored = <String, Object?>{
                ...record,
                if (entry.key != 'household') 'book_id': bookId,
                if (entry.key != 'manual_market_prices') ...{
                  'device_id': 'restore-device',
                  'sync_status': 'local_only',
                },
                if (entry.key == 'household') 'remote_linked_at': null,
                if (entry.key == 'members') 'auth_user_id': null,
              };
              return restored;
            })
            .toList(growable: false),
    };
  }

  static Map<String, List<Map<String, Object?>>> _remapAsCopy(
    Map<String, List<Map<String, Object?>>> source,
  ) {
    const uuid = Uuid();
    final oldBook = source['household']!.single;
    final newBookId = uuid.v4();
    Map<String, String> ids(String key) => {
      for (final record in source[key] ?? const [])
        record['id'] as String: uuid.v4(),
    };

    final memberIds = ids('members');
    final accountIds = ids('accounts');
    final categoryIds = ids('categories');
    final projectIds = ids('projects');
    final transactionIds = ids('transactions');
    final transferLinkIds = ids('transfer_links');
    final definitionIds = ids('asset_definitions');
    final budgetIds = ids('budgets');
    final ruleIds = ids('transaction_import_rules');

    List<Map<String, Object?>> remap(
      String key,
      Map<String, String> ownIds,
    ) => (source[key] ?? const [])
        .map((record) {
          return <String, Object?>{
            ...record,
            'id': ownIds[record['id']],
            'book_id': newBookId,
            if (key == 'accounts' && record['owner_member_id'] != null)
              'owner_member_id': memberIds[record['owner_member_id']],
            if (key == 'transactions' && record['entered_by_member_id'] != null)
              'entered_by_member_id': memberIds[record['entered_by_member_id']],
            if (key == 'transactions' && record['project_id'] != null)
              'project_id': projectIds[record['project_id']],
            if (key == 'transactions' &&
                record['related_transaction_id'] != null)
              'related_transaction_id':
                  transactionIds[record['related_transaction_id']],
            if (key == 'transactions' && record['asset_definition_id'] != null)
              'asset_definition_id':
                  definitionIds[record['asset_definition_id']],
          };
        })
        .toList(growable: false);

    return {
      'household': [
        {
          ...oldBook,
          'id': newBookId,
          'name': '${oldBook['name']} (Restored copy)',
        },
      ],
      'members': remap('members', memberIds),
      'accounts': remap('accounts', accountIds),
      'categories': remap('categories', categoryIds),
      'projects': remap('projects', projectIds),
      'transactions': remap('transactions', transactionIds),
      'transfer_links': (source['transfer_links'] ?? const [])
          .map(
            (record) => <String, Object?>{
              ...record,
              'id': transferLinkIds[record['id']],
              'book_id': newBookId,
              'outgoing_transaction_id':
                  transactionIds[record['outgoing_transaction_id']],
              'incoming_transaction_id':
                  transactionIds[record['incoming_transaction_id']],
              'source_account_id': accountIds[record['source_account_id']],
              'destination_account_id':
                  accountIds[record['destination_account_id']],
            },
          )
          .toList(growable: false),
      'asset_definitions': remap('asset_definitions', definitionIds),
      'budgets': (source['budgets'] ?? const [])
          .map(
            (record) => <String, Object?>{
              ...record,
              'id': budgetIds[record['id']],
              'book_id': newBookId,
              'category_id': categoryIds[record['category_id']],
            },
          )
          .toList(growable: false),
      'transaction_import_rules':
          (source['transaction_import_rules'] ?? const [])
              .map(
                (record) => <String, Object?>{
                  ...record,
                  'id': ruleIds[record['id']],
                  'book_id': newBookId,
                  'category_id': categoryIds[record['category_id']],
                  if (record['account_id'] != null)
                    'account_id': accountIds[record['account_id']],
                },
              )
              .toList(growable: false),
      'manual_market_prices': (source['manual_market_prices'] ?? const [])
          .map(
            (record) => <String, Object?>{
              ...record,
              'book_id': newBookId,
              'asset_key':
                  definitionIds[record['asset_key']] ?? record['asset_key'],
            },
          )
          .toList(growable: false),
    };
  }

  static Set<String> _ids(List<Map<String, Object?>> records) =>
      records.map((record) => _requiredString(record, 'id', 'record')).toSet();

  static String _requiredString(
    Map<String, Object?> record,
    String key,
    String entity,
  ) {
    final value = record[key];
    if (value is! String || value.trim().isEmpty) {
      throw BackupValidationException(
        '$entity is missing required field $key.',
      );
    }
    return value.trim();
  }

  static String _cashAccountName(Map<String, Object?> record) {
    final account = (record['account'] as String? ?? '').trim();
    final route = account.split('->').map((value) => value.trim()).toList();
    if (route.length != 2) return account;
    return record['asset_action'] == 'sell' ? route.last : route.first;
  }

  static String _decimal(double value) =>
      value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');

  static bool _isForbiddenField(String field) {
    final value = field.toLowerCase();
    return _forbiddenFields.contains(value) ||
        value.contains('access_token') ||
        value.contains('refresh_token') ||
        value.contains('password') ||
        value.contains('api_key') ||
        value == 'otp' ||
        value.endsWith('_otp');
  }
}
