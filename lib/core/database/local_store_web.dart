import 'dart:convert';

import 'package:uuid/uuid.dart';

class LocalStore {
  LocalStore({String? databasePath});

  static const schemaVersion = 15;
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
  String? _activeBookId;
  String? get activeBookId => _activeBookId;
  void setActiveBookId(String? value) => _activeBookId = value;
  void Function()? onSyncMutation;
  Future<void> initialize() async {}
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
    _assetMarketPrices.removeWhere(
      (item) => item['asset_key'] == record['asset_key'],
    );

    _assetMarketPrices.add(_withActiveBook(record));
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
        if (_assetDefinitions.any((item) => item['id'] == prepared['id'])) {
          prepared['id'] = 'web-asset-${DateTime.now().microsecondsSinceEpoch}';
        }
        _assetDefinitions.add(prepared);
      }
    }
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

  Future<void> applyRemoteSyncBatch(
    String bookId, {
    required List<Map<String, Object?>> changes,
    required int finalSequence,
  }) async {
    final snapshots = <List<Map<String, Object?>>>[
      for (final collection in [
        _books,
        _householdMembers,
        _accounts,
        _records,
        _assetDefinitions,
        _masterRecords,
      ])
        collection.map(Map<String, Object?>.of).toList(),
    ];
    final cursorSnapshot = _syncCursors.map(Map<String, Object?>.of).toList();
    final masterSnapshot = {
      for (final entry in _master.entries)
        entry.key: List<String>.of(entry.value),
    };
    try {
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
}
