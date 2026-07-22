class LocalStore {
  LocalStore({String? databasePath});

  static final List<Map<String, Object?>> _records = [];
  static final List<Map<String, Object?>> _assetMarketPrices = [];
  static final List<Map<String, Object?>> _assetDefinitions = [];
  static final Map<String, List<String>> _master = {};
  Future<void> initialize() async {}
  Future<List<Map<String, Object?>>> getTransactions() async =>
      List.unmodifiable(_records);
  Future<void> upsertTransaction(Map<String, Object?> record) async {
    _records.removeWhere((item) => item['id'] == record['id']);
    _records.add(Map.of(record));
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
        'sync_status': 'pending',
        ...?version == null ? null : {'version': version},
      };
    }
  }

  Future<List<Map<String, Object?>>> getAssetMarketPrices() async {
    return List.unmodifiable(_assetMarketPrices.map(Map<String, Object?>.of));
  }

  Future<void> upsertAssetMarketPrice(Map<String, Object?> record) async {
    _assetMarketPrices.removeWhere(
      (item) => item['asset_key'] == record['asset_key'],
    );

    _assetMarketPrices.add(Map<String, Object?>.of(record));
  }

  Future<List<Map<String, Object?>>> getAssetDefinitions({
    bool includeDeleted = false,
  }) async {
    final records = _assetDefinitions
        .where((record) => includeDeleted || record['deleted_at'] == null)
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

  Future<void> upsertAssetDefinition(Map<String, Object?> record) async {
    _assetDefinitions.removeWhere((item) => item['id'] == record['id']);

    _assetDefinitions.add(Map<String, Object?>.of(record));
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
  }

  Future<void> ensureAssetDefinitionSeeds(
    List<Map<String, Object?>> records,
  ) async {
    for (final record in records) {
      final exists = _assetDefinitions.any(
        (item) => item['id'] == record['id'],
      );

      if (!exists) {
        _assetDefinitions.add(Map<String, Object?>.of(record));
      }
    }
  }

  Future<void> close() async {}

  String _key(String entity, String? categoryType) =>
      '$entity:${categoryType ?? ''}';
  Future<List<String>> getMasterNames(
    String entity, {
    String? categoryType,
  }) async => List.of(_master[_key(entity, categoryType)] ?? const []);
  Future<void> ensureMasterSeeds(
    String entity,
    List<String> names, {
    String? categoryType,
  }) async =>
      _master.putIfAbsent(_key(entity, categoryType), () => List.of(names));
  Future<void> saveMasterName(
    String entity,
    String name, {
    String? previousName,
    String? categoryType,
  }) async {
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
    if (index >= 0) {
      values[index] = name;
    } else if (!values.contains(name)) {
      values.add(name);
    }
  }
}
