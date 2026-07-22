import '../../../../core/database/local_store.dart';
import '../../domain/entities/asset_definition.dart';
import '../../domain/repositories/asset_definition_repository.dart';

class LocalAssetDefinitionRepository implements AssetDefinitionRepository {
  LocalAssetDefinitionRepository(this.store);

  final LocalStore store;

  @override
  Future<List<AssetDefinition>> getAll({bool includeDeleted = false}) async {
    final records = await store.getAssetDefinitions(
      includeDeleted: includeDeleted,
    );

    return records.map(AssetDefinition.fromRecord).toList();
  }

  @override
  Future<AssetDefinition?> getById(String id) async {
    final record = await store.getAssetDefinitionById(id);

    if (record == null) {
      return null;
    }

    return AssetDefinition.fromRecord(record);
  }

  @override
  Future<void> upsert(AssetDefinition definition) {
    _validate(definition);

    return store.upsertAssetDefinition(definition.toRecord());
  }

  @override
  Future<void> softDelete(String id, {required DateTime deletedAt}) {
    return store.softDeleteAssetDefinition(
      id,
      deletedAt.toUtc().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> ensureSeeds(Iterable<AssetDefinition> definitions) {
    final values = definitions.toList();

    for (final definition in values) {
      _validate(definition);
    }

    return store.ensureAssetDefinitionSeeds(
      values.map((definition) => definition.toRecord()).toList(),
    );
  }

  void _validate(AssetDefinition definition) {
    final errors = definition.validate();

    if (errors.isEmpty) {
      return;
    }

    throw ArgumentError.value(definition, 'definition', errors.join(' '));
  }
}
