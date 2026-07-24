import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/app/data/default_asset_definitions.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_definition_controller.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/repositories/asset_definition_repository.dart';

void main() {
  group('AssetDefinitionController', () {
    test('default definitions preserve the current asset groups', () {
      final definitions = buildDefaultAssetDefinitions(
        timestamp: DateTime.utc(2026, 7, 22),
        deviceId: 'test-device',
      );

      expect(definitions, hasLength(3));

      expect(
        definitions.map((definition) => definition.displayName),
        containsAll(['Gold Holdings', 'Bitcoin Wallet', 'Inventory']),
      );

      final gold = definitions.firstWhere(
        (definition) => definition.kind == AssetKind.gold,
      );

      expect(gold.unit, 'gram');
      expect(gold.currencyCode, 'IDR');
      expect(gold.onlinePricingEnabled, isTrue);
      expect(gold.providerSymbol, 'XAU');
    });

    test('initialize ensures seeds and loads sorted definitions', () async {
      final repository = _FakeAssetDefinitionRepository();

      final controller = AssetDefinitionController(
        repository: repository,
        now: () => DateTime.utc(2026, 7, 22),
      );

      final seeds = buildDefaultAssetDefinitions(
        timestamp: DateTime.utc(2026, 7, 21),
        deviceId: 'test-device',
      );

      await controller.initialize(seeds: seeds);

      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.definitions, hasLength(3));

      expect(controller.names, [
        'Bitcoin Wallet',
        'Gold Holdings',
        'Inventory',
      ]);

      expect(repository.ensureSeedsCallCount, 1);
    });

    test('save creates a definition with local metadata', () async {
      final repository = _FakeAssetDefinitionRepository();

      final controller = AssetDefinitionController(
        repository: repository,
        now: () => DateTime.utc(2026, 7, 22, 12),
      );

      final input = _bbcaDefinition(
        createdAt: DateTime.utc(2020),
        updatedAt: DateTime.utc(2020),
        version: 8,
        syncStatus: 'local_only',
      );

      final saved = await controller.save(input);

      expect(saved.createdAt, DateTime.utc(2026, 7, 22, 12));
      expect(saved.updatedAt, DateTime.utc(2026, 7, 22, 12));
      expect(saved.version, 1);
      expect(saved.syncStatus, 'pending');

      expect(controller.definitions, hasLength(1));
      expect(controller.definitionById(saved.id), isNotNull);
      expect(controller.error, isNull);
    });

    test(
      'save preserves createdAt and increments version when editing',
      () async {
        final repository = _FakeAssetDefinitionRepository();

        final existing = _bbcaDefinition(
          createdAt: DateTime.utc(2026, 7, 1),
          updatedAt: DateTime.utc(2026, 7, 10),
          version: 3,
          syncStatus: 'local_only',
        );

        await repository.upsert(existing);

        final controller = AssetDefinitionController(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 22, 15),
        );

        await controller.initialize();

        final saved = await controller.save(
          existing.copyWith(displayName: 'BBCA', lotSize: 200),
        );

        expect(saved.createdAt, DateTime.utc(2026, 7, 1));
        expect(saved.updatedAt, DateTime.utc(2026, 7, 22, 15));
        expect(saved.version, 4);
        expect(saved.displayName, 'BBCA');
        expect(saved.lotSize, 200);
        expect(saved.syncStatus, 'pending');
      },
    );

    test('delete soft-deletes and removes the active definition', () async {
      final repository = _FakeAssetDefinitionRepository();
      final definition = _bbcaDefinition();

      await repository.upsert(definition);

      final controller = AssetDefinitionController(
        repository: repository,
        now: () => DateTime.utc(2026, 7, 22, 18),
      );

      await controller.initialize();

      expect(controller.definitions, hasLength(1));

      await controller.delete(definition);

      expect(controller.definitions, isEmpty);

      final deleted = await repository.getById(definition.id);

      expect(deleted, isNotNull);
      expect(deleted!.deletedAt, DateTime.utc(2026, 7, 22, 18));
      expect(deleted.version, 2);
      expect(deleted.syncStatus, 'pending');
    });

    test('invalid definition is rejected and error is exposed', () async {
      final repository = _FakeAssetDefinitionRepository();

      final controller = AssetDefinitionController(
        repository: repository,
        now: () => DateTime.utc(2026, 7, 22),
      );

      final invalid = _bbcaDefinition().copyWith(symbol: null, lotSize: 0);

      await expectLater(controller.save(invalid), throwsArgumentError);

      expect(controller.isSaving, isFalse);
      expect(controller.error, isNotNull);
      expect(repository.upsertCallCount, 0);
      expect(controller.definitions, isEmpty);
    });
  });
}

AssetDefinition _bbcaDefinition({
  DateTime? createdAt,
  DateTime? updatedAt,
  int version = 1,
  String syncStatus = 'local_only',
}) {
  return AssetDefinition(
    id: 'asset-bbca',
    displayName: 'Bank Central Asia',
    kind: AssetKind.stock,
    symbol: 'BBCA',
    providerCode: 'alpha_vantage',
    providerSymbol: 'BBCA.JK',
    exchangeCode: 'IDX',
    currencyCode: 'IDR',
    unit: 'share',
    lotSize: 100,
    onlinePricingEnabled: true,
    createdAt: createdAt ?? DateTime.utc(2026, 7, 21),
    updatedAt: updatedAt ?? DateTime.utc(2026, 7, 21),
    deletedAt: null,
    version: version,
    deviceId: 'test-device',
    syncStatus: syncStatus,
  );
}

class _FakeAssetDefinitionRepository implements AssetDefinitionRepository {
  final Map<String, AssetDefinition> _definitions = {};

  int ensureSeedsCallCount = 0;
  int upsertCallCount = 0;

  @override
  Future<List<AssetDefinition>> getAll({bool includeDeleted = false}) async {
    return _definitions.values
        .where((definition) => includeDeleted || definition.deletedAt == null)
        .toList();
  }

  @override
  Future<AssetDefinition?> getById(String id) async {
    return _definitions[id];
  }

  @override
  Future<void> upsert(AssetDefinition definition) async {
    upsertCallCount += 1;
    _definitions[definition.id] = definition;
  }

  @override
  Future<void> softDelete(String id, {required DateTime deletedAt}) async {
    final definition = _definitions[id];

    if (definition == null) {
      return;
    }

    _definitions[id] = definition.copyWith(
      deletedAt: deletedAt,
      updatedAt: deletedAt,
      version: definition.version + 1,
      syncStatus: 'pending',
    );
  }

  @override
  Future<void> ensureSeeds(Iterable<AssetDefinition> definitions) async {
    ensureSeedsCallCount += 1;

    for (final definition in definitions) {
      _definitions.putIfAbsent(definition.id, () => definition);
    }
  }
}
