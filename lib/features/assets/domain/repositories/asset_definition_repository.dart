import '../entities/asset_definition.dart';

abstract interface class AssetDefinitionRepository {
  Future<List<AssetDefinition>> getAll({bool includeDeleted = false});

  Future<AssetDefinition?> getById(String id);

  Future<void> upsert(AssetDefinition definition);

  Future<void> softDelete(String id, {required DateTime deletedAt});

  Future<void> ensureSeeds(Iterable<AssetDefinition> definitions);
}
