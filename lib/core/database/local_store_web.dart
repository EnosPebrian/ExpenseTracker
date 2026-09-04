import 'dart:convert';

import 'package:uuid/uuid.dart';

class LocalStore {
  LocalStore({String? databasePath});

  static const schemaVersion = 25;
  static final List<Map<String, Object?>> _records = [];
  static final List<Map<String, Object?>> _assetMarketPrices = [];
  static final List<Map<String, Object?>> _assetDefinitions = [];
  static final List<Map<String, Object?>> _accounts = [];
  static final List<Map<String, Object?>> _localProfiles = [];
  static final List<Map<String, Object?>> _books = [];
  static final List<Map<String, Object?>> _householdMembers = [];
  static Map<String, Object?>? _localSession;
  static final Map<String, List<String>> _master = {};
  static final List<Map<String, Object?>> _masterRecords = [];
  static final List<Map<String, Object?>> _syncOutbox = [];
  static final List<Map<String, Object?>> _syncCursors = [];
  static final List<Map<String, Object?>> _syncConflicts = [];
  static final List<Map<String, Object?>> _monthlyCategoryBudgets = [];
  static final List<Map<String, Object?>> _transactionImportRules = [];
  static final List<Map<String, Object?>> _transferLinks = [];
  static final List<Map<String, Object?>> _importReviewSessions = [];
  static final List<Map<String, Object?>> _importReviewDrafts = [];
  String? _activeBookId;
  String? get activeBookId => _activeBookId;
  void setActiveBookId(String? value) => _activeBookId = value;
  void Function()? onSyncMutation;
  Future<void> initialize() async {}
  Future<int> getSchemaVersion() async => schemaVersion;
  Future<List<Map<String, Object?>>> getTransactions({
    bool includeDeleted = false,
    String? bookId,
  }) async => List.unmodifiable(
    _records.where(
      (record) =>
          _inBook(record, bookId) &&
          (includeDeleted || record['deleted_at'] == null),
    ),
  );

  Future<Map<String, Object?>?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async {
    for (final record in _records) {
      if (record['related_transaction_id'] == parentTransactionId &&
          record['relation_type'] == 'assetFeeExpense' &&
          (includeDeleted || record['deleted_at'] == null)) {
        return Map<String, Object?>.of(record);
      }
    }
    return null;
  }

  Future<void> upsertTransaction(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    final prepared = _withActiveBook(record);
    _records.removeWhere((item) => item['id'] == record['id']);
    _records.add(prepared);
    if (enqueueSync) {
      _enqueueSyncOperation('transactions', prepared);
      onSyncMutation?.call();
    }
  }

  Future<void> insertTransactionsAtomic(
    List<Map<String, Object?>> records,
  ) async {
    if (records.isEmpty) return;
    final recordSnapshot = _records.map(Map<String, Object?>.of).toList();
    final outboxSnapshot = _syncOutbox.map(Map<String, Object?>.of).toList();
    try {
      final incomingIds = <Object?>{};
      for (final record in records) {
        if (!incomingIds.add(record['id']) ||
            _records.any((item) => item['id'] == record['id'])) {
          throw StateError('A transaction with this stable identity exists.');
        }
        final prepared = _withActiveBook(record);
        _records.add(prepared);
        _enqueueSyncOperation('transactions', prepared);
      }
    } catch (_) {
      _records
        ..clear()
        ..addAll(recordSnapshot);
      _syncOutbox
        ..clear()
        ..addAll(outboxSnapshot);
      rethrow;
    }
    onSyncMutation?.call();
  }

  Future<List<Map<String, Object?>>> getTransferLinks({
    bool includeDeleted = false,
    String? bookId,
  }) async => List.unmodifiable(
    _transferLinks
        .where(
          (record) =>
              _inBook(record, bookId) &&
              (includeDeleted || record['deleted_at'] == null),
        )
        .map(Map<String, Object?>.of),
  );

  Future<void> saveInternalTransferAtomic({
    required List<Map<String, Object?>> transactions,
    required Map<String, Object?> link,
    bool enqueueSync = true,
    Map<String, int> expectedTransactionVersions = const {},
    Set<String> requireNewTransactionIds = const {},
  }) async {
    final transactionSnapshot = _records.map(Map<String, Object?>.of).toList();
    final linkSnapshot = _transferLinks.map(Map<String, Object?>.of).toList();
    final outboxSnapshot = _syncOutbox.map(Map<String, Object?>.of).toList();
    try {
      for (final entry in expectedTransactionVersions.entries) {
        final matches = _records.where((item) => item['id'] == entry.key);
        if (matches.length != 1 ||
            (matches.single['version'] as num).toInt() != entry.value) {
          throw StateError('This transfer candidate changed. Review again.');
        }
      }
      if (requireNewTransactionIds.any(
        (id) => _records.any((item) => item['id'] == id),
      )) {
        throw StateError('This transfer candidate changed. Review again.');
      }
      for (final record in transactions) {
        final prepared = _withActiveBook(record);
        _records.removeWhere((item) => item['id'] == prepared['id']);
        _records.add(prepared);
        if (enqueueSync) {
          _enqueueSyncOperation(
            'transactions',
            prepared,
            operationType: prepared['deleted_at'] == null ? 'upsert' : 'delete',
          );
        }
      }
      final preparedLink = _withActiveBook(link);
      _transferLinks.removeWhere((item) => item['id'] == preparedLink['id']);
      _transferLinks.add(preparedLink);
      _validateActiveTransferLinks(preparedLink['book_id'] as String);
      if (enqueueSync) {
        _enqueueSyncOperation(
          'transfer_links',
          preparedLink,
          operationType: preparedLink['deleted_at'] == null
              ? 'upsert'
              : 'delete',
        );
      }
    } catch (_) {
      _records
        ..clear()
        ..addAll(transactionSnapshot);
      _transferLinks
        ..clear()
        ..addAll(linkSnapshot);
      _syncOutbox
        ..clear()
        ..addAll(outboxSnapshot);
      rethrow;
    }
    if (enqueueSync) onSyncMutation?.call();
  }

  Future<void> softDeleteTransaction(
    String id,
    int deletedAt, {
    int? version,
  }) async {
    final index = _records.indexWhere((item) => item['id'] == id);
    if (index >= 0) {
      _records[index] = {
        ..._records[index],
        'deleted_at': deletedAt,
        'updated_at': deletedAt,
        'sync_status': 'pending',
        ...?version == null ? null : {'version': version},
      };
      _enqueueSyncOperation(
        'transactions',
        _records[index],
        operationType: 'delete',
      );
      onSyncMutation?.call();
    }
  }

  Future<void> saveAssetFeeChange({
    required Map<String, Object?> parent,
    Map<String, Object?>? linkedExpense,
    Map<String, Object?>? obsoleteLinkedExpense,
  }) async {
    final snapshot = _records.map(Map<String, Object?>.of).toList();
    final outboxSnapshot = _syncOutbox.map(Map<String, Object?>.of).toList();
    try {
      await upsertTransaction(parent);
      if (linkedExpense != null) {
        await upsertTransaction(linkedExpense);
      }
      if (obsoleteLinkedExpense != null &&
          obsoleteLinkedExpense['id'] != linkedExpense?['id']) {
        await upsertTransaction(obsoleteLinkedExpense);
      }
    } catch (_) {
      _records
        ..clear()
        ..addAll(snapshot);
      _syncOutbox
        ..clear()
        ..addAll(outboxSnapshot);
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> getAssetMarketPrices({
    String? bookId,
  }) async {
    return List.unmodifiable(
      _assetMarketPrices
          .where((record) => _inBook(record, bookId))
          .map(Map<String, Object?>.of),
    );
  }

  Future<void> upsertAssetMarketPrice(Map<String, Object?> record) async {
    final scoped = _withActiveBook(record);
    final prepared = {
      ...scoped,
      'book_id': scoped['book_id'] ?? 'legacy-default-book',
    };
    _assetMarketPrices.removeWhere(
      (item) =>
          item['asset_key'] == prepared['asset_key'] &&
          item['book_id'] == prepared['book_id'],
    );

    _assetMarketPrices.add(prepared);
  }

  Future<List<Map<String, Object?>>> getAssetDefinitions({
    bool includeDeleted = false,
    String? bookId,
  }) async {
    final records = _assetDefinitions
        .where(
          (record) =>
              _inBook(record, bookId) &&
              (includeDeleted || record['deleted_at'] == null),
        )
        .map(Map<String, Object?>.of)
        .toList();

    records.sort((first, second) {
      final firstName = (first['display_name'] as String).toLowerCase();
      final secondName = (second['display_name'] as String).toLowerCase();

      return firstName.compareTo(secondName);
    });

    return List.unmodifiable(records);
  }

  Future<Map<String, Object?>?> getAssetDefinitionById(String id) async {
    final index = _assetDefinitions.indexWhere((record) => record['id'] == id);

    if (index < 0) {
      return null;
    }

    return Map<String, Object?>.of(_assetDefinitions[index]);
  }

  Future<void> upsertAssetDefinition(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    final prepared = _withActiveBook(record);
    _assetDefinitions.removeWhere((item) => item['id'] == record['id']);
    _assetDefinitions.add(prepared);
    if (enqueueSync) {
      _enqueueSyncOperation('asset_definitions', prepared);
      onSyncMutation?.call();
    }
  }

  Future<void> softDeleteAssetDefinition(String id, int deletedAt) async {
    final index = _assetDefinitions.indexWhere((record) => record['id'] == id);

    if (index < 0) {
      return;
    }

    final current = _assetDefinitions[index];
    final currentVersion = current['version'];

    _assetDefinitions[index] = {
      ...current,
      'deleted_at': deletedAt,
      'updated_at': deletedAt,
      'version': currentVersion is num ? currentVersion.toInt() + 1 : 1,
      'sync_status': 'pending',
    };
    _enqueueSyncOperation(
      'asset_definitions',
      _assetDefinitions[index],
      operationType: 'delete',
    );
    onSyncMutation?.call();
  }

  Future<void> ensureAssetDefinitionSeeds(
    List<Map<String, Object?>> records,
  ) async {
    for (final record in records) {
      final prepared = _withActiveBook(record);
      final exists = _assetDefinitions.any(
        (item) =>
            item['id'] == prepared['id'] &&
            item['book_id'] == prepared['book_id'],
      );

      if (!exists) {
        final matchingId = _assetDefinitions
            .where((item) => item['id'] == prepared['id'])
            .firstOrNull;
        if (matchingId != null &&
            matchingId['book_id'] != prepared['book_id']) {
          final equivalentInActiveBook = _assetDefinitions.any(
            (item) =>
                item['book_id'] == prepared['book_id'] &&
                _sameAssetDefinitionSeed(item, prepared),
          );
          if (equivalentInActiveBook) continue;
          if (matchingId['book_id'] == null && prepared['book_id'] != null) {
            matchingId['book_id'] = prepared['book_id'];
            continue;
          }
          prepared['id'] = 'web-asset-${DateTime.now().microsecondsSinceEpoch}';
        }
        _assetDefinitions.add(prepared);
      }
    }
  }

  Future<Map<String, List<Map<String, Object?>>>> createHouseholdBackupSnapshot(
    String bookId,
  ) async {
    List<Map<String, Object?>> records(
      Iterable<Map<String, Object?>> source, {
      bool Function(Map<String, Object?> record)? where,
    }) {
      final result = source
          .where(
            (record) =>
                record['book_id'] == bookId && (where?.call(record) ?? true),
          )
          .map(Map<String, Object?>.of)
          .toList();
      result.sort((left, right) {
        final leftId = (left['id'] ?? left['asset_key'] ?? '').toString();
        final rightId = (right['id'] ?? right['asset_key'] ?? '').toString();
        return leftId.compareTo(rightId);
      });
      return result;
    }

    final household = _books
        .where((book) => book['id'] == bookId)
        .map(Map<String, Object?>.of)
        .toList();
    if (household.isEmpty) {
      throw StateError('The selected household no longer exists.');
    }
    return {
      'household': household,
      'members': records(_householdMembers),
      'accounts': records(_accounts),
      'categories': records(
        _masterRecords,
        where: (record) => record['_entity_type'] == 'categories',
      ),
      'projects': records(
        _masterRecords,
        where: (record) => record['_entity_type'] == 'projects',
      ),
      'transactions': records(_records),
      'transfer_links': records(_transferLinks),
      'asset_definitions': records(_assetDefinitions),
      'budgets': records(_monthlyCategoryBudgets),
      'transaction_import_rules': records(_transactionImportRules),
      'manual_market_prices': records(
        _assetMarketPrices,
        where: (record) =>
            record['is_manual'] == 1 || record['is_manual'] == true,
      ),
    };
  }

  Future<void> activateHouseholdBackupSnapshot(
    Map<String, List<Map<String, Object?>>> snapshot, {
    String? replaceBookId,
    bool idempotent = false,
  }) async {
    final households = snapshot['household'] ?? const [];
    if (households.length != 1) {
      throw StateError('A restore must contain exactly one household.');
    }
    final restoredBookId = households.single['id'] as String;
    if (replaceBookId != null && replaceBookId != restoredBookId) {
      throw StateError('Replacement requires a matching household ID.');
    }
    final members = snapshot['members'] ?? const [];
    final activeMember = members.cast<Map<String, Object?>>().firstWhere(
      (member) => member['deleted_at'] == null && member['role'] == 'owner',
      orElse: () => members.cast<Map<String, Object?>>().firstWhere(
        (member) => member['deleted_at'] == null,
        orElse: () => throw StateError(
          'The restored household needs at least one active member.',
        ),
      ),
    );

    final snapshots = <List<Map<String, Object?>>, List<Map<String, Object?>>>{
      _records: _records.map(Map<String, Object?>.of).toList(),
      _transferLinks: _transferLinks.map(Map<String, Object?>.of).toList(),
      _assetMarketPrices: _assetMarketPrices
          .map(Map<String, Object?>.of)
          .toList(),
      _assetDefinitions: _assetDefinitions
          .map(Map<String, Object?>.of)
          .toList(),
      _accounts: _accounts.map(Map<String, Object?>.of).toList(),
      _books: _books.map(Map<String, Object?>.of).toList(),
      _householdMembers: _householdMembers
          .map(Map<String, Object?>.of)
          .toList(),
      _masterRecords: _masterRecords.map(Map<String, Object?>.of).toList(),
      _syncOutbox: _syncOutbox.map(Map<String, Object?>.of).toList(),
      _syncCursors: _syncCursors.map(Map<String, Object?>.of).toList(),
      _syncConflicts: _syncConflicts.map(Map<String, Object?>.of).toList(),
      _monthlyCategoryBudgets: _monthlyCategoryBudgets
          .map(Map<String, Object?>.of)
          .toList(),
      _transactionImportRules: _transactionImportRules
          .map(Map<String, Object?>.of)
          .toList(),
    };
    final sessionSnapshot = _localSession == null
        ? null
        : Map<String, Object?>.of(_localSession!);
    final activeBookSnapshot = _activeBookId;
    final masterSnapshot = {
      for (final entry in _master.entries)
        entry.key: List<String>.of(entry.value),
    };
    try {
      if (replaceBookId != null) {
        for (final collection in [
          _records,
          _transferLinks,
          _assetMarketPrices,
          _assetDefinitions,
          _accounts,
          _householdMembers,
          _masterRecords,
          _monthlyCategoryBudgets,
          _transactionImportRules,
        ]) {
          collection.removeWhere(
            (record) => record['book_id'] == replaceBookId,
          );
        }
        _books.removeWhere((book) => book['id'] == replaceBookId);
        _syncOutbox.removeWhere((record) => record['book_id'] == replaceBookId);
        _syncCursors.removeWhere(
          (record) => record['book_id'] == replaceBookId,
        );
        _syncConflicts.removeWhere(
          (record) => record['book_id'] == replaceBookId,
        );
      }

      void addAll(List<Map<String, Object?>> target, String key) {
        for (final record in snapshot[key] ?? const []) {
          final id = record['id'];
          final index = id == null
              ? -1
              : target.indexWhere((item) => item['id'] == id);
          if (index >= 0) {
            if (idempotent && _backupRecordsEqual(target[index], record)) {
              continue;
            }
            throw StateError('A restored record ID already exists locally.');
          }
          target.add(Map<String, Object?>.of(record));
        }
      }

      void addMaster(String key) {
        final type = key == 'categories' ? 'categories' : 'projects';
        for (final record in snapshot[key] ?? const []) {
          final index = _masterRecords.indexWhere(
            (item) => item['id'] == record['id'],
          );
          if (index >= 0) {
            if (idempotent &&
                _backupRecordsEqual(_masterRecords[index], record)) {
              continue;
            }
            throw StateError(
              'A restored $key record ID already exists locally.',
            );
          }
          _masterRecords.add({...record, '_entity_type': type});
        }
      }

      addAll(_books, 'household');
      addAll(_householdMembers, 'members');
      addAll(_accounts, 'accounts');
      addMaster('categories');
      addAll(_monthlyCategoryBudgets, 'budgets');
      addAll(_transactionImportRules, 'transaction_import_rules');
      addMaster('projects');
      addAll(_assetDefinitions, 'asset_definitions');
      for (final record in snapshot['manual_market_prices'] ?? const []) {
        final index = _assetMarketPrices.indexWhere(
          (item) =>
              item['book_id'] == record['book_id'] &&
              item['asset_key'] == record['asset_key'],
        );
        if (index >= 0) {
          if (idempotent &&
              _backupRecordsEqual(_assetMarketPrices[index], record)) {
            continue;
          }
          throw StateError(
            'A restored market-price key already exists locally.',
          );
        }
        _assetMarketPrices.add(Map<String, Object?>.of(record));
      }
      addAll(_records, 'transactions');
      addAll(_transferLinks, 'transfer_links');

      _activeBookId = restoredBookId;
      _localSession = {
        'id': 1,
        'active_profile_id': sessionSnapshot?['active_profile_id'],
        'active_book_id': restoredBookId,
        'active_member_id': activeMember['id'],
        'onboarding_completed': sessionSnapshot?['onboarding_completed'] ?? 1,
      };
      _master.removeWhere((key, _) => key.startsWith('$restoredBookId:'));
      for (final record in _masterRecords.where(
        (record) =>
            record['book_id'] == restoredBookId && record['deleted_at'] == null,
      )) {
        final entity = record['_entity_type'] as String;
        final categoryType = entity == 'categories'
            ? record['category_type'] as String?
            : null;
        _master
            .putIfAbsent(_key(entity, categoryType), () => [])
            .add(record['name'] as String);
      }
    } catch (_) {
      for (final entry in snapshots.entries) {
        entry.key
          ..clear()
          ..addAll(entry.value);
      }
      _localSession = sessionSnapshot;
      _activeBookId = activeBookSnapshot;
      _master
        ..clear()
        ..addAll(masterSnapshot);
      rethrow;
    }
  }

  Future<int> recoverHouseholdBackupRecords(
    String bookId,
    Map<String, List<Map<String, Object?>>> records, {
    required bool enqueueSync,
  }) async {
    final snapshots = <List<Map<String, Object?>>, List<Map<String, Object?>>>{
      _records: _records.map(Map<String, Object?>.of).toList(),
      _transferLinks: _transferLinks.map(Map<String, Object?>.of).toList(),
      _assetDefinitions: _assetDefinitions
          .map(Map<String, Object?>.of)
          .toList(),
      _accounts: _accounts.map(Map<String, Object?>.of).toList(),
      _masterRecords: _masterRecords.map(Map<String, Object?>.of).toList(),
      _monthlyCategoryBudgets: _monthlyCategoryBudgets
          .map(Map<String, Object?>.of)
          .toList(),
      _transactionImportRules: _transactionImportRules
          .map(Map<String, Object?>.of)
          .toList(),
      _syncOutbox: _syncOutbox.map(Map<String, Object?>.of).toList(),
    };
    final targets = <String, List<Map<String, Object?>>>{
      'accounts': _accounts,
      'categories': _masterRecords,
      'projects': _masterRecords,
      'asset_definitions': _assetDefinitions,
      'budgets': _monthlyCategoryBudgets,
      'transaction_import_rules': _transactionImportRules,
      'transactions': _records,
      'transfer_links': _transferLinks,
    };
    try {
      if (!_books.any(
        (book) => book['id'] == bookId && book['deleted_at'] == null,
      )) {
        throw StateError('The active household is unavailable.');
      }
      final plannedIds = {
        for (final entry in records.entries)
          entry.key: {for (final row in entry.value) row['id']},
      };
      bool current(String type, Object? id) =>
          id == null ||
          (targets[type] ?? const []).any(
            (row) => row['id'] == id && row['book_id'] == bookId,
          );
      final accountNames = {
        for (final row in _accounts.where((row) => row['book_id'] == bookId))
          (row['name'] as String).trim().toLowerCase(),
        for (final row in records['accounts'] ?? const [])
          (row['name'] as String).trim().toLowerCase(),
      };
      for (final entry in records.entries) {
        final target = targets[entry.key];
        if (target == null) throw StateError('Unsupported recovery entity.');
        for (final row in entry.value) {
          if (row['id'] is! String ||
              row['book_id'] != bookId ||
              row['deleted_at'] != null ||
              target.any((item) => item['id'] == row['id'])) {
            throw StateError('Recovery record is no longer missing.');
          }
        }
      }
      for (final row in records['accounts'] ?? const []) {
        final memberId = row['owner_member_id'];
        if (memberId != null &&
            !_householdMembers.any(
              (member) =>
                  member['id'] == memberId && member['book_id'] == bookId,
            )) {
          throw StateError('A recovered account references a missing member.');
        }
      }
      for (final row in records['budgets'] ?? const []) {
        if (!current('categories', row['category_id']) &&
            !(plannedIds['categories'] ?? const {}).contains(
              row['category_id'],
            )) {
          throw StateError('A recovered budget references a missing category.');
        }
        if (_monthlyCategoryBudgets.any(
          (item) =>
              item['book_id'] == bookId &&
              item['deleted_at'] == null &&
              item['category_id'] == row['category_id'] &&
              item['month_start'] == row['month_start'],
        )) {
          throw StateError(
            'A current budget already uses this category and month.',
          );
        }
      }
      for (final row in records['transaction_import_rules'] ?? const []) {
        if (!current('categories', row['category_id']) &&
            !(plannedIds['categories'] ?? const {}).contains(
              row['category_id'],
            )) {
          throw StateError(
            'A recovered import rule references a missing category.',
          );
        }
        if (!current('accounts', row['account_id']) &&
            !(plannedIds['accounts'] ?? const {}).contains(row['account_id'])) {
          throw StateError(
            'A recovered import rule references a missing account.',
          );
        }
      }
      for (final row in records['transactions'] ?? const []) {
        final account = (row['account'] as String? ?? '').trim().toLowerCase();
        if (account.isNotEmpty && !accountNames.contains(account)) {
          throw StateError(
            'A recovered transaction references a missing account.',
          );
        }
        for (final dependency in <(String, Object?)>[
          ('projects', row['project_id']),
          ('asset_definitions', row['asset_definition_id']),
          ('transactions', row['related_transaction_id']),
        ]) {
          if (!current(dependency.$1, dependency.$2) &&
              !(plannedIds[dependency.$1] ?? const {}).contains(
                dependency.$2,
              )) {
            throw StateError('A recovered transaction dependency is missing.');
          }
        }
        final memberId = row['entered_by_member_id'];
        if (memberId != null &&
            !_householdMembers.any(
              (member) =>
                  member['id'] == memberId && member['book_id'] == bookId,
            )) {
          throw StateError(
            'A recovered transaction references a missing member.',
          );
        }
      }
      for (final row in records['transfer_links'] ?? const []) {
        for (final dependency in <(String, Object?)>[
          ('transactions', row['outgoing_transaction_id']),
          ('transactions', row['incoming_transaction_id']),
          ('accounts', row['source_account_id']),
          ('accounts', row['destination_account_id']),
        ]) {
          if (!current(dependency.$1, dependency.$2) &&
              !(plannedIds[dependency.$1] ?? const {}).contains(
                dependency.$2,
              )) {
            throw StateError(
              'A recovered internal transfer dependency is missing.',
            );
          }
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final key in const [
        'categories',
        'projects',
        'accounts',
        'asset_definitions',
        'budgets',
        'transaction_import_rules',
        'transactions',
        'transfer_links',
      ]) {
        for (final source in records[key] ?? const []) {
          final saved = <String, Object?>{
            ...source,
            'book_id': bookId,
            'updated_at': now,
            'version': 1,
            'device_id': 'backup-recovery',
            'sync_status': enqueueSync ? 'pending' : 'local_only',
            if (key == 'categories' || key == 'projects') '_entity_type': key,
          };
          targets[key]!.add(saved);
          if (enqueueSync) {
            _enqueueSyncOperation(
              key == 'budgets' ? 'monthly_category_budgets' : key,
              _withoutInternalFields(saved),
            );
          }
        }
      }
      _rebuildMasterValues('categories', null);
      _rebuildMasterValues('projects', null);
    } catch (_) {
      for (final entry in snapshots.entries) {
        entry.key
          ..clear()
          ..addAll(entry.value);
      }
      rethrow;
    }
    if (enqueueSync && records.values.any((rows) => rows.isNotEmpty)) {
      onSyncMutation?.call();
    }
    return getPendingSyncCount(bookId);
  }

  Future<void> close() async {}

  Future<List<Map<String, Object?>>> getAccounts({
    bool includeDeleted = false,
    String? bookId,
  }) async {
    final records =
        _accounts
            .where(
              (record) =>
                  _inBook(record, bookId) &&
                  (includeDeleted || record['deleted_at'] == null),
            )
            .map(Map<String, Object?>.of)
            .toList()
          ..sort(
            (first, second) => (first['name'] as String)
                .toLowerCase()
                .compareTo((second['name'] as String).toLowerCase()),
          );
    return List.unmodifiable(records);
  }

  Future<void> upsertAccount(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    final prepared = _withActiveBook(record);
    final name = (record['name'] as String).trim();
    final id = record['id'];
    final duplicate = _accounts.any(
      (item) =>
          item['deleted_at'] == null &&
          item['book_id'] == prepared['book_id'] &&
          item['id'] != id &&
          (item['name'] as String).trim().toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) throw StateError('$name already exists.');
    _accounts.removeWhere((item) => item['id'] == id);
    final saved = {...prepared, 'name': name};
    _accounts.add(saved);
    if (enqueueSync) {
      _enqueueSyncOperation('accounts', saved);
      onSyncMutation?.call();
    }
  }

  Future<void> ensureAccountSeeds(
    List<String> names, {
    String currencyCode = 'IDR',
  }) async {
    if ((await getAccounts()).isNotEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var index = 0; index < names.length; index++) {
      await upsertAccount({
        'id': 'web-seed-account-$index',
        'book_id': _activeBookId,
        'name': names[index],
        'account_type': 'asset',
        'currency_code': currencyCode.trim().toUpperCase(),
        'opening_balance': 0,
        'opening_balance_date': null,
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'local-device',
        'sync_status': 'local_only',
      });
    }
  }

  Future<List<Map<String, Object?>>> getLocalProfiles() async {
    return List.unmodifiable(_localProfiles.map(Map<String, Object?>.of));
  }

  Future<Map<String, Object?>?> getActiveLocalProfile() async {
    final activeId = _localSession?['active_profile_id'];
    final activeIndex = _localProfiles.indexWhere(
      (record) => record['id'] == activeId,
    );
    if (activeIndex >= 0) {
      return Map<String, Object?>.of(_localProfiles[activeIndex]);
    }
    return _localProfiles.isEmpty
        ? null
        : Map<String, Object?>.of(_localProfiles.first);
  }

  Future<void> upsertLocalProfile(Map<String, Object?> record) async {
    _localProfiles.removeWhere((item) => item['id'] == record['id']);
    _localProfiles.add(Map<String, Object?>.of(record));
  }

  Future<Map<String, Object?>?> getLocalSession() async {
    return _localSession == null
        ? null
        : Map<String, Object?>.of(_localSession!);
  }

  Future<void> saveLocalSession({
    required String? activeProfileId,
    required bool onboardingCompleted,
    String? activeBookId,
    String? activeMemberId,
  }) async {
    _localSession = {
      'id': 1,
      'active_profile_id': activeProfileId,
      'active_book_id': activeBookId,
      'active_member_id': activeMemberId,
      'onboarding_completed': onboardingCompleted ? 1 : 0,
    };
  }

  String _key(String entity, String? categoryType) =>
      '${_activeBookId ?? 'unscoped'}:$entity:${categoryType ?? ''}';
  Future<List<String>> getMasterNames(
    String entity, {
    String? categoryType,
  }) async {
    if (entity == 'accounts') {
      return (await getAccounts())
          .map((record) => record['name'] as String)
          .toList();
    }
    return List.of(_master[_key(entity, categoryType)] ?? const []);
  }

  Future<List<Map<String, Object?>>> getProjectRecords() async {
    final records =
        _masterRecords
            .where(
              (record) =>
                  record['_entity_type'] == 'projects' &&
                  record['book_id'] == _activeBookId &&
                  record['deleted_at'] == null,
            )
            .map(Map<String, Object?>.of)
            .toList()
          ..sort(
            (left, right) => (left['name'] as String).toLowerCase().compareTo(
              (right['name'] as String).toLowerCase(),
            ),
          );
    return List.unmodifiable(records);
  }

  Future<List<Map<String, Object?>>> getCategoryRecords({
    bool includeDeleted = false,
    String? categoryType,
    String? bookId,
  }) async {
    final scope = bookId ?? _activeBookId;
    final records =
        _masterRecords
            .where(
              (record) =>
                  record['_entity_type'] == 'categories' &&
                  (scope == null || record['book_id'] == scope) &&
                  (includeDeleted || record['deleted_at'] == null) &&
                  (categoryType == null ||
                      record['category_type'] == categoryType),
            )
            .map(_withoutInternalFields)
            .toList()
          ..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );
    return List.unmodifiable(records);
  }

  Future<List<Map<String, Object?>>> getBudgetCopyCategoryRecords(
    Iterable<String> categoryIds,
  ) async {
    final ids = categoryIds.toSet();
    return _masterRecords
        .where(
          (record) =>
              record['_entity_type'] == 'categories' &&
              ids.contains(record['id']),
        )
        .map(_withoutInternalFields)
        .toList();
  }

  Future<List<Map<String, Object?>>> getMonthlyCategoryBudgets({
    bool includeDeleted = false,
    String? bookId,
    String? monthStart,
  }) async => List.unmodifiable(
    _monthlyCategoryBudgets
        .where(
          (record) =>
              _inBook(record, bookId) &&
              (includeDeleted || record['deleted_at'] == null) &&
              (monthStart == null || record['month_start'] == monthStart),
        )
        .map(Map<String, Object?>.of),
  );

  Future<Map<String, Object?>> upsertMonthlyCategoryBudget(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    var prepared = _withActiveBook(record);
    final bookId = prepared['book_id'];
    final note = prepared['note'] as String?;
    final monthStart = prepared['month_start'] as String;
    final parsedMonth = DateTime.tryParse(monthStart);
    if (bookId == null || (prepared['limit_minor'] as num).toInt() <= 0) {
      throw StateError('A positive household budget is required.');
    }
    if (note != null && note.length > 120) {
      throw StateError('A budget note cannot exceed 120 characters.');
    }
    if (!RegExp(r'^\d{4}-\d{2}-01$').hasMatch(monthStart) ||
        parsedMonth == null ||
        parsedMonth.day != 1) {
      throw StateError('A budget month must use YYYY-MM-01.');
    }
    final book = _books.where((item) => item['id'] == bookId);
    if (book.isEmpty ||
        prepared['currency_code'] != book.single['base_currency_code']) {
      throw StateError('Budgets must use the household base currency.');
    }
    final sameId = _monthlyCategoryBudgets.where(
      (item) => item['id'] == prepared['id'],
    );
    if (sameId.isNotEmpty &&
        (sameId.single['book_id'] != bookId ||
            sameId.single['category_id'] != prepared['category_id'] ||
            sameId.single['month_start'] != prepared['month_start'] ||
            sameId.single['currency_code'] != prepared['currency_code'])) {
      throw StateError('Budget identity fields cannot be changed.');
    }
    final category = _masterRecords.where(
      (category) =>
          category['_entity_type'] == 'categories' &&
          category['id'] == prepared['category_id'] &&
          category['book_id'] == bookId &&
          category['category_type'] == 'expense',
    );
    if (category.isEmpty ||
        (sameId.isEmpty && category.single['deleted_at'] != null)) {
      throw StateError('The budget category is invalid for this household.');
    }
    final duplicate = _monthlyCategoryBudgets.indexWhere(
      (item) =>
          item['id'] != prepared['id'] &&
          item['book_id'] == bookId &&
          item['category_id'] == prepared['category_id'] &&
          item['month_start'] == prepared['month_start'] &&
          item['deleted_at'] == null,
    );
    if (duplicate >= 0) {
      throw StateError('A budget already exists for this category and month.');
    }
    var index = _monthlyCategoryBudgets.indexWhere(
      (item) => item['id'] == prepared['id'],
    );
    if (index < 0) {
      final deleted = _monthlyCategoryBudgets.indexWhere(
        (item) =>
            item['book_id'] == bookId &&
            item['category_id'] == prepared['category_id'] &&
            item['month_start'] == prepared['month_start'] &&
            item['deleted_at'] != null,
      );
      if (deleted >= 0) {
        final deletedRecord = _monthlyCategoryBudgets[deleted];
        final requestedVersion = (prepared['version'] as num).toInt();
        final restoredVersion = (deletedRecord['version'] as num).toInt() + 1;
        prepared = {
          ...prepared,
          'id': deletedRecord['id'],
          'created_at': deletedRecord['created_at'],
          'deleted_at': null,
          'version': requestedVersion > restoredVersion
              ? requestedVersion
              : restoredVersion,
        };
        index = deleted;
      }
    }
    if (index >= 0) _monthlyCategoryBudgets.removeAt(index);
    _monthlyCategoryBudgets.add(prepared);
    if (enqueueSync) {
      _enqueueSyncOperation('monthly_category_budgets', prepared);
      onSyncMutation?.call();
    }
    return Map<String, Object?>.of(prepared);
  }

  Future<List<Map<String, Object?>>> copyMonthlyCategoryBudgets(
    List<Map<String, Object?>> records,
  ) async {
    if (records.isEmpty) return const [];
    final budgetSnapshot = _monthlyCategoryBudgets
        .map(Map<String, Object?>.of)
        .toList();
    final outboxSnapshot = _syncOutbox.map(Map<String, Object?>.of).toList();
    final copied = <Map<String, Object?>>[];
    try {
      for (final record in records) {
        final prepared = _withActiveBook(record);
        final bookId = prepared['book_id'];
        if (_monthlyCategoryBudgets.any(
          (item) => item['id'] == prepared['id'],
        )) {
          throw StateError('A generated budget identity already exists.');
        }
        final category = _masterRecords.where(
          (item) =>
              item['_entity_type'] == 'categories' &&
              item['id'] == prepared['category_id'],
        );
        if (category.isEmpty) {
          throw StateError('A copied budget references a missing category.');
        }
        if (category.single['book_id'] != bookId) {
          throw StateError('A copied budget references another household.');
        }
        if (category.single['category_type'] != 'expense' ||
            category.single['deleted_at'] != null) {
          throw StateError('A copied budget category is unavailable.');
        }
        final duplicate = _monthlyCategoryBudgets.any(
          (item) =>
              item['book_id'] == bookId &&
              item['category_id'] == prepared['category_id'] &&
              item['month_start'] == prepared['month_start'] &&
              item['deleted_at'] == null,
        );
        if (duplicate) continue;
        copied.add(
          await upsertMonthlyCategoryBudget(prepared, enqueueSync: false),
        );
      }
      for (final record in copied) {
        _enqueueSyncOperation('monthly_category_budgets', record);
      }
    } catch (_) {
      _monthlyCategoryBudgets
        ..clear()
        ..addAll(budgetSnapshot);
      _syncOutbox
        ..clear()
        ..addAll(outboxSnapshot);
      rethrow;
    }
    if (copied.isNotEmpty) onSyncMutation?.call();
    return copied;
  }

  Future<void> softDeleteMonthlyCategoryBudget(String id, int deletedAt) async {
    final index = _monthlyCategoryBudgets.indexWhere(
      (item) => item['id'] == id,
    );
    if (index < 0) return;
    final saved = <String, Object?>{
      ..._monthlyCategoryBudgets[index],
      'deleted_at': deletedAt,
      'updated_at': deletedAt,
      'version': (_monthlyCategoryBudgets[index]['version'] as num).toInt() + 1,
      'sync_status': 'pending',
    };
    _monthlyCategoryBudgets[index] = saved;
    _enqueueSyncOperation(
      'monthly_category_budgets',
      saved,
      operationType: 'delete',
    );
    onSyncMutation?.call();
  }

  Future<List<Map<String, Object?>>> getImportReviewSessions({
    bool includeDeleted = false,
    String? bookId,
    String? state,
  }) async {
    final rows = _importReviewSessions
        .where(
          (row) =>
              _inBook(row, bookId) &&
              (includeDeleted || row['deleted_at'] == null) &&
              (state == null || row['state'] == state),
        )
        .map(Map<String, Object?>.of)
        .toList();
    rows.sort(
      (a, b) => (b['updated_at'] as num).compareTo(a['updated_at'] as num),
    );
    return rows;
  }

  Future<List<Map<String, Object?>>> getImportReviewDrafts({
    required String sessionId,
    bool includeDeleted = false,
  }) async {
    final rows = _importReviewDrafts
        .where(
          (row) =>
              row['session_id'] == sessionId &&
              (includeDeleted || row['deleted_at'] == null),
        )
        .map(Map<String, Object?>.of)
        .toList();
    rows.sort(
      (a, b) => (a['source_index'] as num).compareTo(b['source_index'] as num),
    );
    return rows;
  }

  Future<List<Map<String, Object?>>> getAllImportReviewDrafts({
    required String bookId,
    bool includeDeleted = false,
  }) async {
    final rows = _importReviewDrafts
        .where(
          (row) =>
              row['book_id'] == bookId &&
              (includeDeleted || row['deleted_at'] == null),
        )
        .map(Map<String, Object?>.of)
        .toList();
    rows.sort((a, b) {
      final session = (a['session_id'] as String).compareTo(
        b['session_id'] as String,
      );
      if (session != 0) return session;
      final source = (a['source_index'] as num).compareTo(
        b['source_index'] as num,
      );
      return source != 0
          ? source
          : (a['id'] as String).compareTo(b['id'] as String);
    });
    return rows;
  }

  Future<void> saveImportReviewSessionAtomic({
    required Map<String, Object?> session,
    required List<Map<String, Object?>> drafts,
    bool enqueueSync = true,
  }) async {
    final sessionSnapshot = _importReviewSessions
        .map(Map<String, Object?>.of)
        .toList();
    final draftSnapshot = _importReviewDrafts
        .map(Map<String, Object?>.of)
        .toList();
    final outboxSnapshot = _syncOutbox.map(Map<String, Object?>.of).toList();
    try {
      final prepared = _withActiveBook(session);
      final bookId = prepared['book_id'] as String?;
      if (bookId == null) {
        throw StateError('An import session requires a household.');
      }
      final existing = _importReviewSessions.where(
        (row) => row['id'] == prepared['id'],
      );
      if (existing.isNotEmpty) {
        if (existing.single['book_id'] != bookId ||
            existing.single['source_fingerprint'] !=
                prepared['source_fingerprint']) {
          throw StateError('Import session identity cannot change.');
        }
        final previousState = existing.single['state'] as String;
        final nextState = prepared['state'] as String;
        final validTransition =
            previousState == nextState ||
            (previousState == 'pendingReview' &&
                (nextState == 'readyToCommit' || nextState == 'discarded')) ||
            (previousState == 'readyToCommit' && nextState == 'completed');
        if (!validTransition) {
          throw StateError('Invalid import review lifecycle transition.');
        }
      }
      final memberId = prepared['created_by_member_id'] as String?;
      if (memberId != null &&
          !_householdMembers.any(
            (row) =>
                row['id'] == memberId &&
                row['book_id'] == bookId &&
                row['deleted_at'] == null,
          )) {
        throw StateError('The import creator is unavailable.');
      }
      final accountId = prepared['destination_account_id'] as String?;
      if (accountId != null &&
          !_accounts.any(
            (row) =>
                row['id'] == accountId &&
                row['book_id'] == bookId &&
                row['deleted_at'] == null,
          )) {
        throw StateError('The import account is unavailable.');
      }
      _importReviewSessions.removeWhere((row) => row['id'] == prepared['id']);
      _importReviewSessions.add(prepared);
      if (enqueueSync) {
        _enqueueSyncOperation('import_review_sessions', prepared);
      }
      for (final value in drafts) {
        final draft = _withActiveBook(value);
        if (draft['book_id'] != bookId ||
            draft['session_id'] != prepared['id']) {
          throw StateError(
            'An import draft must belong to its session household.',
          );
        }
        final categoryId = draft['category_id'] as String?;
        if (categoryId != null &&
            !_masterRecords.any(
              (row) =>
                  row['_entity_type'] == 'categories' &&
                  row['id'] == categoryId &&
                  row['book_id'] == bookId &&
                  row['deleted_at'] == null &&
                  row['category_type'] == draft['transaction_type'],
            )) {
          throw StateError('The import category is unavailable.');
        }
        final transactionId = draft['deterministic_transaction_id'] as String?;
        final identityAccountId =
            draft['deterministic_transaction_account_id'] as String?;
        if ((transactionId == null) != (identityAccountId == null)) {
          throw StateError(
            'Import transaction identity and account binding must be resolved together.',
          );
        }
        if (identityAccountId != null &&
            (identityAccountId != accountId ||
                !_accounts.any(
                  (row) =>
                      row['id'] == identityAccountId &&
                      row['book_id'] == bookId &&
                      row['deleted_at'] == null,
                ))) {
          throw StateError(
            'The import identity account belongs to another household.',
          );
        }
        final existingDraft = _importReviewDrafts
            .where((row) => row['id'] == draft['id'])
            .firstOrNull;
        if (existingDraft != null) {
          if (existingDraft['session_id'] != draft['session_id'] ||
              existingDraft['book_id'] != draft['book_id'] ||
              existingDraft['source_row_identity'] !=
                  draft['source_row_identity'] ||
              existingDraft['source_row_key'] != draft['source_row_key']) {
            throw StateError('Import draft source identity cannot change.');
          }
          if (existing.single['state'] == 'completed' &&
              (existingDraft['deterministic_transaction_id'] != transactionId ||
                  existingDraft['deterministic_transaction_account_id'] !=
                      identityAccountId)) {
            throw StateError(
              'A completed import transaction identity cannot change.',
            );
          }
        }
        _importReviewDrafts.removeWhere((row) => row['id'] == draft['id']);
        _importReviewDrafts.add(draft);
        if (enqueueSync) _enqueueSyncOperation('import_review_drafts', draft);
      }
    } catch (_) {
      _importReviewSessions
        ..clear()
        ..addAll(sessionSnapshot);
      _importReviewDrafts
        ..clear()
        ..addAll(draftSnapshot);
      _syncOutbox
        ..clear()
        ..addAll(outboxSnapshot);
      rethrow;
    }
    if (enqueueSync) onSyncMutation?.call();
  }

  Future<void> discardImportReviewSession(
    String sessionId,
    int discardedAt, {
    bool enqueueSync = true,
  }) async {
    final index = _importReviewSessions.indexWhere(
      (row) => row['id'] == sessionId,
    );
    if (index < 0 || _importReviewSessions[index]['deleted_at'] != null) return;
    if (_importReviewSessions[index]['state'] != 'pendingReview') {
      throw StateError('Only a pending import can be discarded.');
    }
    final session = <String, Object?>{
      ..._importReviewSessions[index],
      'state': 'discarded',
      'deleted_at': discardedAt,
      'updated_at': discardedAt,
      'version': (_importReviewSessions[index]['version'] as num).toInt() + 1,
      'sync_status': 'pending',
    };
    _importReviewSessions[index] = session;
    for (
      var draftIndex = 0;
      draftIndex < _importReviewDrafts.length;
      draftIndex++
    ) {
      final current = _importReviewDrafts[draftIndex];
      if (current['session_id'] != sessionId || current['deleted_at'] != null) {
        continue;
      }
      final draft = <String, Object?>{
        ...current,
        'deleted_at': discardedAt,
        'updated_at': discardedAt,
        'version': (current['version'] as num).toInt() + 1,
        'sync_status': 'pending',
      };
      _importReviewDrafts[draftIndex] = draft;
      if (enqueueSync) {
        _enqueueSyncOperation(
          'import_review_drafts',
          draft,
          operationType: 'delete',
        );
      }
    }
    if (enqueueSync) {
      _enqueueSyncOperation(
        'import_review_sessions',
        session,
        operationType: 'delete',
      );
      onSyncMutation?.call();
    }
  }

  Future<List<Map<String, Object?>>> getTransactionImportRules({
    bool includeDeleted = false,
    bool activeOnly = false,
    String? bookId,
  }) async {
    final scope = bookId ?? _activeBookId;
    final rows =
        _transactionImportRules
            .where(
              (row) =>
                  (scope == null || row['book_id'] == scope) &&
                  (includeDeleted || row['deleted_at'] == null) &&
                  (!activeOnly || row['enabled'] == 1),
            )
            .map(Map<String, Object?>.of)
            .toList()
          ..sort((a, b) {
            final priority = (b['priority'] as num).compareTo(
              a['priority'] as num,
            );
            if (priority != 0) return priority;
            return (a['name'] as String).compareTo(b['name'] as String);
          });
    return rows;
  }

  Future<Map<String, Object?>> upsertTransactionImportRule(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    var prepared = _withActiveBook(record);
    final bookId = prepared['book_id'] as String?;
    if (bookId == null || (prepared['pattern_key'] as String).isEmpty) {
      throw StateError('An import rule requires a household and pattern.');
    }
    final category = _masterRecords.where(
      (row) =>
          row['id'] == prepared['category_id'] &&
          row['book_id'] == bookId &&
          row['category_type'] == prepared['transaction_type'],
    );
    if (category.isEmpty) {
      throw StateError(
        'The import rule category belongs to another household or type.',
      );
    }
    final accountId = prepared['account_id'] as String?;
    if (accountId != null &&
        !_accounts.any(
          (row) => row['id'] == accountId && row['book_id'] == bookId,
        )) {
      throw StateError('The import rule account belongs to another household.');
    }
    bool sameSemantic(Map<String, Object?> row) =>
        row['book_id'] == bookId &&
        row['transaction_type'] == prepared['transaction_type'] &&
        row['match_field'] == prepared['match_field'] &&
        row['match_operator'] == prepared['match_operator'] &&
        row['pattern_key'] == prepared['pattern_key'] &&
        row['account_id'] == accountId;
    if (_transactionImportRules.any(
      (row) =>
          sameSemantic(row) &&
          row['deleted_at'] == null &&
          row['id'] != prepared['id'],
    )) {
      throw StateError('An active import rule with this match already exists.');
    }
    final sameId = _transactionImportRules.indexWhere(
      (row) => row['id'] == prepared['id'],
    );
    if (sameId >= 0 && _transactionImportRules[sameId]['book_id'] != bookId) {
      throw StateError('An import rule cannot move between households.');
    }
    var index = sameId;
    if (index < 0) {
      index = _transactionImportRules.indexWhere(
        (row) => sameSemantic(row) && row['deleted_at'] != null,
      );
      if (index >= 0) {
        final deleted = _transactionImportRules[index];
        prepared = {
          ...prepared,
          'id': deleted['id'],
          'created_at': deleted['created_at'],
          'deleted_at': null,
          'version': (deleted['version'] as num).toInt() + 1,
        };
      }
    }
    if (index >= 0) _transactionImportRules.removeAt(index);
    _transactionImportRules.add(prepared);
    if (enqueueSync) {
      _enqueueSyncOperation('transaction_import_rules', prepared);
      onSyncMutation?.call();
    }
    return Map<String, Object?>.of(prepared);
  }

  Future<void> softDeleteTransactionImportRule(
    String id,
    int deletedAt, {
    bool enqueueSync = true,
  }) async {
    final index = _transactionImportRules.indexWhere((row) => row['id'] == id);
    if (index < 0 || _transactionImportRules[index]['deleted_at'] != null) {
      return;
    }
    final saved = <String, Object?>{
      ..._transactionImportRules[index],
      'deleted_at': deletedAt,
      'updated_at': deletedAt,
      'version': (_transactionImportRules[index]['version'] as num).toInt() + 1,
      'sync_status': 'pending',
    };
    _transactionImportRules[index] = saved;
    if (enqueueSync) {
      _enqueueSyncOperation(
        'transaction_import_rules',
        saved,
        operationType: 'delete',
      );
      onSyncMutation?.call();
    }
  }

  Future<void> ensureMasterSeeds(
    String entity,
    List<String> names, {
    String? categoryType,
  }) async {
    if (entity == 'accounts') {
      await ensureAccountSeeds(names);
      return;
    }
    _master.putIfAbsent(_key(entity, categoryType), () => List.of(names));
  }

  Future<void> saveMasterName(
    String entity,
    String name, {
    String? previousName,
    String? categoryType,
  }) async {
    if (entity == 'accounts') {
      final records = await getAccounts();
      if (previousName != null) {
        final index = records.indexWhere(
          (record) => record['name'] == previousName,
        );
        if (index >= 0) {
          final record = records[index];
          await upsertAccount({
            ...record,
            'name': name,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
            'version': (record['version'] as num).toInt() + 1,
            'sync_status': 'pending',
          });
          return;
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await upsertAccount({
        'id': 'web-account-$now',
        'book_id': _activeBookId,
        'name': name,
        'account_type': 'asset',
        'currency_code': 'IDR',
        'opening_balance': 0,
        'opening_balance_date': null,
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'local-device',
        'sync_status': 'pending',
      });
      return;
    }
    if (entity == 'categories' &&
        previousName != null &&
        categoryType == null) {
      throw ArgumentError.value(
        categoryType,
        'categoryType',
        'Category type is required when renaming a category.',
      );
    }
    final values = _master.putIfAbsent(_key(entity, categoryType), () => []);
    final index = previousName == null ? -1 : values.indexOf(previousName);
    Map<String, Object?> saved;
    if (index >= 0) {
      values[index] = name;
      final recordIndex = _masterRecords.indexWhere(
        (record) =>
            record['book_id'] == _activeBookId &&
            record['name'] == previousName &&
            (entity != 'categories' || record['category_type'] == categoryType),
      );
      final existing = recordIndex < 0
          ? <String, Object?>{}
          : _masterRecords.removeAt(recordIndex);
      final now = DateTime.now().millisecondsSinceEpoch;
      saved = {
        ...existing,
        'id': existing['id'] ?? const Uuid().v4(),
        'book_id': _activeBookId,
        'name': name,
        'created_at': existing['created_at'] ?? now,
        'updated_at': now,
        'version': ((existing['version'] as num?)?.toInt() ?? 0) + 1,
        'device_id': existing['device_id'] ?? 'web-device',
        'sync_status': 'pending',
        if (entity == 'projects') 'status': existing['status'] ?? 'active',
        if (entity == 'categories') 'category_type': categoryType ?? 'expense',
        '_entity_type': entity,
      };
    } else if (!values.contains(name)) {
      values.add(name);
      final now = DateTime.now().millisecondsSinceEpoch;
      saved = {
        'id': const Uuid().v4(),
        'book_id': _activeBookId,
        'name': name,
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'web-device',
        'sync_status': 'pending',
        if (entity == 'projects') 'status': 'active',
        if (entity == 'categories') 'category_type': categoryType ?? 'expense',
        '_entity_type': entity,
      };
    } else {
      return;
    }
    _masterRecords.add(saved);
    _enqueueSyncOperation(entity, _withoutInternalFields(saved));
    onSyncMutation?.call();
  }

  Future<List<Map<String, Object?>>> getFinancialBooks({
    bool includeDeleted = false,
  }) async => List.unmodifiable(
    _books
        .where((book) => includeDeleted || book['deleted_at'] == null)
        .map(Map<String, Object?>.of),
  );

  Future<void> upsertFinancialBook(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    _books.removeWhere((book) => book['id'] == record['id']);
    _books.add(Map<String, Object?>.of(record));
    if (enqueueSync) {
      _enqueueSyncOperation('books', record);
      onSyncMutation?.call();
    }
  }

  Future<List<Map<String, Object?>>> getHouseholdMembers({
    String? bookId,
    bool includeDeleted = false,
  }) async => List.unmodifiable(
    _householdMembers
        .where(
          (member) =>
              _inBook(member, bookId) &&
              (includeDeleted || member['deleted_at'] == null),
        )
        .map(Map<String, Object?>.of),
  );

  Future<void> upsertHouseholdMember(
    Map<String, Object?> record, {
    bool enqueueSync = true,
  }) async {
    final prepared = _withActiveBook(record);
    final name = (prepared['display_name'] as String).trim();
    if (prepared['book_id'] == null) {
      throw StateError('An active household is required.');
    }
    final duplicate = _householdMembers.any(
      (member) =>
          member['id'] != prepared['id'] &&
          member['book_id'] == prepared['book_id'] &&
          member['deleted_at'] == null &&
          (member['display_name'] as String).toLowerCase() ==
              name.toLowerCase(),
    );
    if (duplicate) throw StateError('$name already exists.');
    _householdMembers.removeWhere((member) => member['id'] == prepared['id']);
    final saved = {...prepared, 'display_name': name};
    _householdMembers.add(saved);
    if (enqueueSync) {
      _enqueueSyncOperation('household_members', saved);
      onSyncMutation?.call();
    }
  }

  Future<void> softDeleteHouseholdMember(String id) async {
    if (_accounts.any(
      (account) =>
          account['owner_member_id'] == id && account['deleted_at'] == null,
    )) {
      throw StateError('Move this member\'s accounts to Joint before removal.');
    }
    final index = _householdMembers.indexWhere((member) => member['id'] == id);
    if (index < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _householdMembers[index] = {
      ..._householdMembers[index],
      'deleted_at': now,
      'updated_at': now,
      'version':
          ((_householdMembers[index]['version'] as num?)?.toInt() ?? 0) + 1,
      'sync_status': 'pending',
    };
    _enqueueSyncOperation(
      'household_members',
      _householdMembers[index],
      operationType: 'delete',
    );
    onSyncMutation?.call();
  }

  Future<void> ensureHouseholdForProfile(Map<String, Object?> profile) async {
    var bookId = _localSession?['active_book_id'] as String?;
    var memberId = _localSession?['active_member_id'] as String?;
    if (bookId == null || !_books.any((book) => book['id'] == bookId)) {
      bookId = _books.isEmpty
          ? 'web-book-${DateTime.now().microsecondsSinceEpoch}'
          : _books.first['id'] as String;
      if (_books.isEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await upsertFinancialBook({
          'id': bookId,
          'name': 'My Household',
          'base_currency_code': profile['default_currency_code'] ?? 'IDR',
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'device_id': 'local-device',
          'sync_status': 'local_only',
        });
      }
    }
    setActiveBookId(bookId);
    final members = await getHouseholdMembers(bookId: bookId);
    if (memberId == null ||
        !members.any((member) => member['id'] == memberId)) {
      memberId = members.isEmpty
          ? 'web-member-${DateTime.now().microsecondsSinceEpoch}'
          : members.first['id'] as String;
      if (members.isEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await upsertHouseholdMember({
          'id': memberId,
          'book_id': bookId,
          'display_name': profile['display_name'],
          'role': 'owner',
          'created_at': now,
          'updated_at': now,
          'version': 1,
          'device_id': 'local-device',
          'sync_status': 'local_only',
        });
      }
    }
    await saveLocalSession(
      activeProfileId: profile['id'] as String,
      onboardingCompleted:
          (_localSession?['onboarding_completed'] as num?)?.toInt() == 1,
      activeBookId: bookId,
      activeMemberId: memberId,
    );
  }

  void _enqueueSyncOperation(
    String entityType,
    Map<String, Object?> record, {
    String? operationType,
  }) {
    final bookId = entityType == 'books'
        ? record['id'] as String?
        : record['book_id'] as String?;
    final entityId = record['id'] as String?;
    if (bookId == null || entityId == null) return;
    final linked = _books.any(
      (book) => book['id'] == bookId && book['remote_linked_at'] != null,
    );
    if (!linked) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final version = (record['version'] as num?)?.toInt() ?? 1;
    _syncOutbox.add({
      'operation_id': const Uuid().v4(),
      'book_id': bookId,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation_type':
          operationType ?? (record['deleted_at'] == null ? 'upsert' : 'delete'),
      'base_version': version > 0 ? version - 1 : 0,
      'payload_json': jsonEncode(record),
      'created_at': now,
      'updated_at': now,
      'attempt_count': 0,
      'next_attempt_at': null,
      'last_error_code': null,
      'last_error_message': null,
      'status': 'pending',
    });
  }

  Future<Map<String, Object?>?> getSyncCursor(String bookId) async {
    final index = _syncCursors.indexWhere((item) => item['book_id'] == bookId);
    return index < 0 ? null : Map<String, Object?>.of(_syncCursors[index]);
  }

  Future<void> updateInitialSyncCursor(Map<String, Object?> fields) async {
    final bookId = fields['book_id'] as String;
    final index = _syncCursors.indexWhere((item) => item['book_id'] == bookId);
    final existing = index < 0
        ? const <String, Object?>{}
        : _syncCursors.removeAt(index);
    _syncCursors.add({
      ...existing,
      'book_id': bookId,
      'last_server_sequence': existing['last_server_sequence'] ?? 0,
      ...fields,
      'updated_at':
          fields['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, Object?>>> getInitialSyncEntityRecords(
    String entityType,
    String bookId,
  ) async => _syncCollection(entityType)
      .where(
        (record) => entityType == 'books'
            ? record['id'] == bookId
            : record['book_id'] == bookId,
      )
      .map(_withoutInternalFields)
      .toList();

  int get initialSyncOutboxBoundary => _syncOutbox.length;

  Future<void> completeInitialSyncUpload(
    String bookId,
    int boundary,
    int finalSequence,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (
      var index = 0;
      index < boundary.clamp(0, _syncOutbox.length);
      index++
    ) {
      final operation = _syncOutbox[index];
      if (operation['book_id'] == bookId && operation['status'] != 'conflict') {
        _syncOutbox[index] = {
          ...operation,
          'status': 'completed',
          'updated_at': now,
        };
      }
    }
    await updateInitialSyncCursor({
      'book_id': bookId,
      'last_server_sequence': finalSequence,
      'initialization_state': 'ready',
      'completed_at': now,
      'last_error_code': null,
      'last_error_message': null,
    });
  }

  Future<void> setSyncInitializationState(String bookId, String state) async {
    final index = _syncCursors.indexWhere((item) => item['book_id'] == bookId);
    final existing = index < 0
        ? const <String, Object?>{}
        : _syncCursors.removeAt(index);
    _syncCursors.add({
      ...existing,
      'book_id': bookId,
      'last_server_sequence': existing['last_server_sequence'] ?? 0,
      'initialization_state': state,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, Object?>>> getEligibleSyncOperations(
    String bookId, {
    int limit = 50,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _syncOutbox
        .where(
          (item) =>
              item['book_id'] == bookId &&
              (item['status'] == 'pending' || item['status'] == 'retry') &&
              ((item['next_attempt_at'] as num?)?.toInt() ?? 0) <= now,
        )
        .take(limit.clamp(1, 100))
        .map(Map<String, Object?>.of)
        .toList();
  }

  Future<int> getPendingSyncCount(String bookId) async => _syncOutbox
      .where(
        (item) => item['book_id'] == bookId && item['status'] != 'completed',
      )
      .length;

  Future<Map<String, int>> getSyncOutboxStatusCounts(String bookId) async {
    final counts = <String, int>{};
    for (final item in _syncOutbox.where((row) => row['book_id'] == bookId)) {
      final status = item['status'] as String;
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> recoverInterruptedSyncOperations(String bookId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var index = 0; index < _syncOutbox.length; index++) {
      final item = _syncOutbox[index];
      if (item['book_id'] == bookId && item['status'] == 'sending') {
        _syncOutbox[index] = {
          ...item,
          'status': 'retry',
          'next_attempt_at': now,
          'updated_at': now,
          'last_error_code': 'interrupted',
        };
      }
    }
  }

  Future<void> markSyncOperationsSending(List<String> operationIds) async {
    _updateOutbox(
      operationIds,
      (item) => {
        ...item,
        'status': 'sending',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> completeSyncOperation(
    String operationId, {
    int? serverVersion,
  }) async {
    final operationIndex = _syncOutbox.indexWhere(
      (item) => item['operation_id'] == operationId,
    );
    if (operationIndex < 0) return;
    final operation = Map<String, Object?>.of(_syncOutbox[operationIndex]);
    _updateOutbox(
      [operationId],
      (item) => {
        ...item,
        'status': 'completed',
        'next_attempt_at': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
    final hasNewerPending = _syncOutbox.any(
      (item) =>
          item['operation_id'] != operationId &&
          item['entity_type'] == operation['entity_type'] &&
          item['entity_id'] == operation['entity_id'] &&
          item['status'] != 'completed' &&
          (item['created_at'] as num).toInt() >
              (operation['created_at'] as num).toInt(),
    );
    if (!hasNewerPending) {
      final collection = _syncCollection(operation['entity_type'] as String);
      final recordIndex = collection.indexWhere(
        (item) => item['id'] == operation['entity_id'],
      );
      if (recordIndex >= 0) {
        final localVersion =
            (collection[recordIndex]['version'] as num?)?.toInt() ?? 0;
        collection[recordIndex] = {
          ...collection[recordIndex],
          'sync_status': 'synced',
          if (serverVersion != null && serverVersion > localVersion)
            'version': serverVersion,
        };
      }
    }
  }

  Future<void> scheduleSyncRetry(
    String operationId, {
    required String errorCode,
    required String safeMessage,
    required int nextAttemptAt,
  }) async {
    final terminal =
        errorCode == 'unauthorized' ||
        errorCode.toLowerCase().contains('validation');
    _updateOutbox(
      [operationId],
      (item) => {
        ...item,
        'status': terminal ? 'conflict' : 'retry',
        'attempt_count': ((item['attempt_count'] as num?)?.toInt() ?? 0) + 1,
        'next_attempt_at': nextAttemptAt,
        'last_error_code': errorCode,
        'last_error_message': safeMessage,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> recordSyncConflict(Map<String, Object?> record) async {
    if (!_syncConflicts.any(
      (item) =>
          item['operation_id'] == record['operation_id'] &&
          item['resolved_at'] == null,
    )) {
      _syncConflicts.add({
        'id': const Uuid().v4(),
        ...record,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'resolved_at': null,
        'resolution': null,
      });
    }
    _updateOutbox(
      [record['operation_id'] as String],
      (item) => {
        ...item,
        'status': 'conflict',
        'last_error_code': 'version_conflict',
      },
    );
  }

  Future<int> getUnresolvedSyncConflictCount(String bookId) async =>
      _syncConflicts
          .where(
            (item) => item['book_id'] == bookId && item['resolved_at'] == null,
          )
          .length;

  Future<List<Map<String, Object?>>> getSyncConflicts(String bookId) async =>
      _syncConflicts
          .where(
            (item) =>
                item['book_id'] == bookId &&
                item['resolution_status'] != 'resolved' &&
                item['resolved_at'] == null,
          )
          .map(Map<String, Object?>.of)
          .toList()
        ..sort(
          (a, b) => (a['created_at'] as num).compareTo(b['created_at'] as num),
        );

  Future<bool> beginSyncConflictResolution(
    String id,
    String operationId,
  ) async {
    final index = _syncConflicts.indexWhere(
      (item) =>
          item['id'] == id &&
          (item['resolution_status'] == null ||
              item['resolution_status'] == 'unresolved' ||
              item['resolution_status'] == 'resolutionFailed'),
    );
    if (index < 0) return false;
    _syncConflicts[index] = {
      ..._syncConflicts[index],
      'resolution_status': 'resolving',
      'resolution_operation_id': operationId,
    };
    return true;
  }

  Future<void> failSyncConflictResolution(String id) async {
    final index = _syncConflicts.indexWhere(
      (item) => item['id'] == id && item['resolution_status'] == 'resolving',
    );
    if (index >= 0) {
      _syncConflicts[index] = {
        ..._syncConflicts[index],
        'resolution_status': 'resolutionFailed',
      };
    }
  }

  Future<void> completeSyncConflictResolution(
    String id, {
    required String resolution,
    required Map<String, Object?> canonicalPayload,
    required int serverSequence,
  }) async {
    final index = _syncConflicts.indexWhere(
      (item) => item['id'] == id && item['resolution_status'] == 'resolving',
    );
    if (index < 0) throw StateError('Conflict is no longer resolving.');
    final conflict = _syncConflicts[index];
    final collection = _syncCollection(conflict['entity_type'] as String);
    final collectionSnapshot = collection.map(Map<String, Object?>.of).toList();
    try {
      collection.removeWhere((item) => item['id'] == conflict['entity_id']);
      collection.add({...canonicalPayload, 'sync_status': 'synced'});
      _validateActiveTransferLinks(conflict['book_id'] as String);
    } catch (_) {
      collection
        ..clear()
        ..addAll(collectionSnapshot);
      rethrow;
    }
    _updateOutbox([
      conflict['operation_id'] as String,
    ], (item) => {...item, 'status': 'completed'});
    _syncConflicts[index] = {
      ...conflict,
      'resolution_status': 'resolved',
      'resolution': resolution,
      'resolved_at': DateTime.now().millisecondsSinceEpoch,
    };
    final cursor = _syncCursors.indexWhere(
      (item) => item['book_id'] == conflict['book_id'],
    );
    if (cursor >= 0) {
      _syncCursors[cursor] = {
        ..._syncCursors[cursor],
        'last_server_sequence': serverSequence,
      };
    }
  }

  Future<void> applyRemoteSyncBatch(
    String bookId, {
    required List<Map<String, Object?>> changes,
    required int finalSequence,
    bool replaceExisting = false,
  }) async {
    final snapshots = <List<Map<String, Object?>>>[
      for (final collection in [
        _books,
        _householdMembers,
        _accounts,
        _records,
        _assetDefinitions,
        _masterRecords,
        _monthlyCategoryBudgets,
        _transactionImportRules,
        _transferLinks,
        _importReviewSessions,
        _importReviewDrafts,
        _assetMarketPrices,
        _syncOutbox,
        _syncConflicts,
      ])
        collection.map(Map<String, Object?>.of).toList(),
    ];
    final cursorSnapshot = _syncCursors.map(Map<String, Object?>.of).toList();
    final masterSnapshot = {
      for (final entry in _master.entries)
        entry.key: List<String>.of(entry.value),
    };
    try {
      if (replaceExisting) {
        for (final collection in [
          _householdMembers,
          _accounts,
          _records,
          _assetDefinitions,
          _masterRecords,
          _monthlyCategoryBudgets,
          _transactionImportRules,
          _transferLinks,
          _importReviewSessions,
          _importReviewDrafts,
          _assetMarketPrices,
        ]) {
          collection.removeWhere((record) => record['book_id'] == bookId);
        }
        _books.removeWhere((record) => record['id'] == bookId);
        _syncOutbox.removeWhere((record) => record['book_id'] == bookId);
        _syncConflicts.removeWhere((record) => record['book_id'] == bookId);
      }
      for (final change in changes) {
        final entityType = change['entity_type'] as String;
        final payload = Map<String, Object?>.of(
          (change['payload'] as Map).cast<String, Object?>(),
        );
        if (payload['id'] != change['entity_id']) {
          throw StateError('Remote entity identity mismatch.');
        }
        if ((entityType == 'books' && payload['id'] != bookId) ||
            (entityType != 'books' && payload['book_id'] != bookId)) {
          throw StateError('Remote book scope mismatch.');
        }
        final collection = _syncCollection(entityType);
        final index = collection.indexWhere(
          (item) => item['id'] == payload['id'],
        );
        final existing = index < 0
            ? const <String, Object?>{}
            : collection.removeAt(index);
        collection.add({
          ...existing,
          ...payload,
          'sync_status': 'synced',
          if (entityType == 'categories' || entityType == 'projects')
            '_entity_type': entityType,
        });
        if (entityType == 'categories' || entityType == 'projects') {
          _rebuildMasterValues(entityType, payload['category_type'] as String?);
        }
      }
      _validateActiveTransferLinks(bookId);
      await setSyncInitializationState(bookId, 'ready');
      final cursorIndex = _syncCursors.indexWhere(
        (item) => item['book_id'] == bookId,
      );
      _syncCursors[cursorIndex] = {
        ..._syncCursors[cursorIndex],
        'last_server_sequence': finalSequence,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
    } catch (_) {
      final collections = [
        _books,
        _householdMembers,
        _accounts,
        _records,
        _assetDefinitions,
        _masterRecords,
        _monthlyCategoryBudgets,
        _transactionImportRules,
        _transferLinks,
        _importReviewSessions,
        _importReviewDrafts,
        _assetMarketPrices,
        _syncOutbox,
        _syncConflicts,
      ];
      for (var index = 0; index < collections.length; index++) {
        collections[index]
          ..clear()
          ..addAll(snapshots[index]);
      }
      _syncCursors
        ..clear()
        ..addAll(cursorSnapshot);
      _master
        ..clear()
        ..addAll(masterSnapshot);
      rethrow;
    }
  }

  void _validateActiveTransferLinks(String bookId) {
    final transactions = {
      for (final row in _records.where((row) => row['book_id'] == bookId))
        row['id']: row,
    };
    final accounts = {
      for (final row in _accounts.where((row) => row['book_id'] == bookId))
        row['id']: row,
    };
    final legIds = <Object?>{};
    for (final link in _transferLinks.where(
      (row) => row['book_id'] == bookId && row['deleted_at'] == null,
    )) {
      final outgoing = transactions[link['outgoing_transaction_id']];
      final incoming = transactions[link['incoming_transaction_id']];
      final source = accounts[link['source_account_id']];
      final destination = accounts[link['destination_account_id']];
      final amount = (link['amount'] as num?)?.toInt();
      final validIdentity =
          legIds.add(link['outgoing_transaction_id']) &&
          legIds.add(link['incoming_transaction_id']);
      if (outgoing == null ||
          incoming == null ||
          source == null ||
          destination == null ||
          outgoing['deleted_at'] != null ||
          incoming['deleted_at'] != null ||
          source['deleted_at'] != null ||
          destination['deleted_at'] != null ||
          outgoing['transaction_type'] != 'expense' ||
          incoming['transaction_type'] != 'income' ||
          amount == null ||
          amount <= 0 ||
          outgoing['amount'] != amount ||
          incoming['amount'] != amount ||
          outgoing['account'] != source['name'] ||
          incoming['account'] != destination['name'] ||
          source['currency_code'] != destination['currency_code'] ||
          source['currency_code'] != link['currency_code'] ||
          link['source_account_id'] == link['destination_account_id'] ||
          link['outgoing_transaction_id'] == link['incoming_transaction_id'] ||
          !validIdentity) {
        throw StateError(
          'Remote internal transfer ${link['id']} is invalid or incomplete.',
        );
      }
    }
  }

  void _rebuildMasterValues(String entityType, String? categoryType) {
    _master[_key(entityType, categoryType)] = _masterRecords
        .where(
          (record) =>
              record['_entity_type'] == entityType &&
              record['book_id'] == _activeBookId &&
              record['deleted_at'] == null &&
              (entityType != 'categories' ||
                  record['category_type'] == categoryType),
        )
        .map((record) => record['name'] as String)
        .toList();
  }

  void _updateOutbox(
    Iterable<String> ids,
    Map<String, Object?> Function(Map<String, Object?>) update,
  ) {
    final target = ids.toSet();
    for (var index = 0; index < _syncOutbox.length; index++) {
      if (target.contains(_syncOutbox[index]['operation_id'])) {
        _syncOutbox[index] = update(_syncOutbox[index]);
      }
    }
  }

  List<Map<String, Object?>> _syncCollection(String entityType) =>
      switch (entityType) {
        'books' => _books,
        'household_members' => _householdMembers,
        'accounts' => _accounts,
        'categories' || 'projects' => _masterRecords,
        'transactions' => _records,
        'asset_definitions' => _assetDefinitions,
        'monthly_category_budgets' => _monthlyCategoryBudgets,
        'transaction_import_rules' => _transactionImportRules,
        'transfer_links' => _transferLinks,
        'import_review_sessions' => _importReviewSessions,
        'import_review_drafts' => _importReviewDrafts,
        _ => throw ArgumentError.value(entityType, 'entityType'),
      };

  Map<String, Object?> _withoutInternalFields(Map<String, Object?> value) => {
    for (final entry in value.entries)
      if (!entry.key.startsWith('_')) entry.key: entry.value,
  };

  bool _inBook(Map<String, Object?> record, String? requestedBookId) {
    final scope = requestedBookId ?? _activeBookId;
    return scope == null || record['book_id'] == scope;
  }

  Map<String, Object?> _withActiveBook(Map<String, Object?> record) => {
    ...record,
    if (record['book_id'] == null && _activeBookId != null)
      'book_id': _activeBookId,
  };

  bool _sameAssetDefinitionSeed(
    Map<String, Object?> existing,
    Map<String, Object?> seed,
  ) {
    for (final field in const [
      'display_name',
      'asset_kind',
      'symbol',
      'provider_code',
      'provider_symbol',
      'exchange_code',
      'currency_code',
      'unit',
      'lot_size',
      'online_pricing_enabled',
    ]) {
      if (existing[field] != seed[field]) return false;
    }
    return existing['deleted_at'] == null;
  }
}

bool _backupRecordsEqual(
  Map<String, Object?> stored,
  Map<String, Object?> incoming,
) {
  for (final entry in incoming.entries) {
    if (entry.key == '_entity_type') continue;
    final left = stored[entry.key];
    final right = entry.value;
    if (left is num && right is bool) {
      if (left != (right ? 1 : 0)) return false;
    } else if (left is bool && right is num) {
      if ((left ? 1 : 0) != right) return false;
    } else if (left != right) {
      return false;
    }
  }
  return true;
}
