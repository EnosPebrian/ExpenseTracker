class LocalStore {
  LocalStore({String? databasePath});

  static final List<Map<String, Object?>> _records = [];
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
