import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/app/data/default_asset_definitions.dart';
import 'package:pilgrim_tracker/features/assets/controllers/asset_definition_controller.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/repositories/asset_definition_repository.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_definition_integrity_policy.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

void main() {
  group('AssetDefinitionController', () {
    test('default definitions include core assets and initial currencies', () {
      final definitions = buildDefaultAssetDefinitions(
        timestamp: DateTime.utc(2026, 7, 22),
        deviceId: 'test-device',
      );

      expect(definitions, hasLength(5));

      expect(
        definitions.map((definition) => definition.displayName),
        containsAll([
          'Gold Holdings',
          'Bitcoin Wallet',
          'Inventory',
          'US Dollar Cash',
          'Singapore Dollar Cash',
        ]),
      );

      final gold = definitions.firstWhere(
        (definition) => definition.kind == AssetKind.gold,
      );

      expect(gold.unit, 'gram');
      expect(gold.currencyCode, 'IDR');
      expect(gold.onlinePricingEnabled, isTrue);
      expect(gold.providerSymbol, 'XAU');

      final foreignCurrencies = definitions
          .where((definition) => definition.kind == AssetKind.foreignCurrency)
          .toList();

      expect(foreignCurrencies, hasLength(2));

      final currenciesBySymbol = {
        for (final definition in foreignCurrencies)
          definition.normalizedSymbol!: definition,
      };

      final usd = currenciesBySymbol['USD']!;
      final sgd = currenciesBySymbol['SGD']!;

      expect(usd.id, 'asset-usd');
      expect(usd.displayName, 'US Dollar Cash');
      expect(usd.normalizedProviderCode, 'ALPHA_VANTAGE');
      expect(usd.providerSymbol, 'USD/IDR');
      expect(usd.currencyCode, 'IDR');
      expect(usd.unit, 'usd');
      expect(usd.lotSize, 1);
      expect(usd.onlinePricingEnabled, isTrue);
      expect(usd.marketPriceKey, 'USD');
      expect(usd.quoteSymbol, 'USD/IDR');
      expect(usd.validate(), isEmpty);

      expect(sgd.id, 'asset-sgd');
      expect(sgd.displayName, 'Singapore Dollar Cash');
      expect(sgd.normalizedProviderCode, 'ALPHA_VANTAGE');
      expect(sgd.providerSymbol, 'SGD/IDR');
      expect(sgd.currencyCode, 'IDR');
      expect(sgd.unit, 'sgd');
      expect(sgd.lotSize, 1);
      expect(sgd.onlinePricingEnabled, isTrue);
      expect(sgd.marketPriceKey, 'SGD');
      expect(sgd.quoteSymbol, 'SGD/IDR');
      expect(sgd.validate(), isEmpty);
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
      expect(controller.definitions, hasLength(5));

      expect(controller.names, [
        'Bitcoin Wallet',
        'Gold Holdings',
        'Inventory',
        'Singapore Dollar Cash',
        'US Dollar Cash',
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

      await expectLater(
        controller.save(invalid),
        throwsA(isA<AssetDefinitionIntegrityException>()),
      );

      expect(controller.isSaving, isFalse);
      expect(controller.error, isNotNull);
      expect(repository.upsertCallCount, 0);
      expect(controller.definitions, isEmpty);
    });

    test(
      'conflicting candidate is not persisted and exposes field error',
      () async {
        final repository = _FakeAssetDefinitionRepository();
        await repository.upsert(_bbcaDefinition());
        final initialWrites = repository.upsertCallCount;
        final controller = AssetDefinitionController(repository: repository);

        await expectLater(
          controller.save(
            _bbcaDefinition().copyWith(
              id: 'asset-bbca-copy',
              displayName: 'BBCA Copy',
              providerSymbol: 'OTHER',
            ),
          ),
          throwsA(isA<AssetDefinitionIntegrityException>()),
        );

        expect(repository.upsertCallCount, initialWrites);
        expect(
          controller.fieldError(AssetDefinitionIntegrityField.symbol),
          contains('already exists'),
        );
      },
    );

    test('conflicting edit is blocked while editing itself succeeds', () async {
      final repository = _FakeAssetDefinitionRepository();
      final bbca = _bbcaDefinition();
      final bbri = bbca.copyWith(
        id: 'asset-bbri',
        displayName: 'Bank Rakyat Indonesia',
        symbol: 'BBRI',
        providerSymbol: 'BBRI.JK',
      );
      await repository.upsert(bbca);
      await repository.upsert(bbri);
      final controller = AssetDefinitionController(repository: repository);

      final edited = await controller.save(
        bbca.copyWith(displayName: 'Bank Central Asia Tbk'),
      );
      expect(edited.displayName, 'Bank Central Asia Tbk');

      await expectLater(
        controller.save(bbri.copyWith(symbol: 'BBCA', providerSymbol: 'OTHER')),
        throwsA(isA<AssetDefinitionIntegrityException>()),
      );
      expect((await repository.getById(bbri.id))?.symbol, 'BBRI');
    });

    test('archived definitions participate in conflict checks', () async {
      final repository = _FakeAssetDefinitionRepository();
      await repository.upsert(
        _bbcaDefinition().copyWith(deletedAt: DateTime.utc(2026, 7, 23)),
      );
      final controller = AssetDefinitionController(repository: repository);

      await expectLater(
        controller.save(
          _bbcaDefinition().copyWith(
            id: 'asset-bbca-new',
            providerSymbol: 'OTHER',
          ),
        ),
        throwsA(isA<AssetDefinitionIntegrityException>()),
      );
      expect(controller.error, contains('archived'));
    });

    test('field errors clear after correction', () async {
      final repository = _FakeAssetDefinitionRepository();
      await repository.upsert(_bbcaDefinition());
      final controller = AssetDefinitionController(repository: repository);

      await expectLater(
        controller.save(
          _bbcaDefinition().copyWith(id: 'asset-copy', providerSymbol: 'OTHER'),
        ),
        throwsA(isA<AssetDefinitionIntegrityException>()),
      );
      expect(controller.integrityResult, isNotNull);

      controller.clearValidationErrors();

      expect(controller.integrityResult, isNull);
      expect(controller.error, isNull);
    });

    test(
      'seed bootstrap stays idempotent and rejects seed conflicts',
      () async {
        final repository = _FakeAssetDefinitionRepository();
        final controller = AssetDefinitionController(repository: repository);
        final seed = _bbcaDefinition();

        await controller.initialize(seeds: [seed]);
        await controller.initialize(seeds: [seed]);

        expect(repository.getAll(), completion(hasLength(1)));

        await controller.initialize(
          seeds: [
            seed.copyWith(
              id: 'asset-conflicting-seed',
              providerSymbol: 'OTHER',
            ),
          ],
        );

        expect(repository.getAll(), completion(hasLength(1)));
        expect(controller.error, contains('already exists'));
      },
    );

    test(
      'unused definition archives and restores with the same metadata',
      () async {
        final repository = _FakeAssetDefinitionRepository();
        final definition = _bbcaDefinition();
        await repository.upsert(definition);
        final controller = AssetDefinitionController(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 24),
        );
        await controller.initialize();

        await controller.archive(definition);

        expect(controller.definitions, isEmpty);
        expect(controller.archivedDefinitions.single.id, definition.id);
        expect(controller.archivedDefinitions.single.version, 2);

        await controller.archive(definition);
        expect(controller.archivedDefinitions.single.version, 2);

        final restored = await controller.restore(definition);
        expect(restored.id, definition.id);
        expect(restored.createdAt, definition.createdAt);
        expect(restored.providerSymbol, definition.providerSymbol);
        expect(restored.version, 3);
        expect(controller.definitions.single.id, definition.id);
        expect(controller.archivedDefinitions, isEmpty);

        final repeated = await controller.restore(restored);
        expect(repeated.id, definition.id);
        expect(
          repository.getAll(includeDeleted: true),
          completion(hasLength(1)),
        );
      },
    );

    test(
      'open holding blocks archive but fully sold history allows it',
      () async {
        final repository = _FakeAssetDefinitionRepository();
        final definition = _bbcaDefinition();
        await repository.upsert(definition);
        final transactions = <Transaction>[
          _assetTransaction(definition: definition, quantity: 500),
        ];
        final controller = AssetDefinitionController(
          repository: repository,
          transactionsProvider: () async => transactions,
        );
        await controller.initialize();

        await expectLater(
          controller.archive(definition),
          throwsA(isA<AssetDefinitionLifecycleException>()),
        );
        expect(controller.definitions, hasLength(1));

        transactions.add(
          _assetTransaction(
            id: 'sell',
            definition: definition,
            quantity: 500,
            action: AssetAction.sell,
          ),
        );
        await controller.archive(definition);

        expect(controller.archivedDefinitions.single.id, definition.id);
        expect(transactions, hasLength(2));
      },
    );

    test(
      'linked definition allows safe edits and preserves snapshots',
      () async {
        final repository = _FakeAssetDefinitionRepository();
        final definition = _bbcaDefinition();
        final transaction = _assetTransaction(definition: definition);
        await repository.upsert(definition);
        final controller = AssetDefinitionController(
          repository: repository,
          transactionsProvider: () async => [transaction],
        );
        await controller.initialize();

        final saved = await controller.save(
          definition.copyWith(
            displayName: 'BCA Tbk',
            providerCode: 'manual_provider',
            providerSymbol: 'BCA',
            onlinePricingEnabled: false,
          ),
        );

        expect(saved.displayName, 'BCA Tbk');
        expect(saved.providerCode, 'MANUAL_PROVIDER');
        expect(transaction.assetName, 'Bank Central Asia');
        expect(transaction.assetSymbol, 'BBCA');
      },
    );

    test('linked identity edit and archived edit are blocked', () async {
      final repository = _FakeAssetDefinitionRepository();
      final definition = _bbcaDefinition();
      final transactions = [_assetTransaction(definition: definition)];
      await repository.upsert(definition);
      final controller = AssetDefinitionController(
        repository: repository,
        transactionsProvider: () async => transactions,
      );
      await controller.initialize();

      await expectLater(
        controller.save(definition.copyWith(symbol: 'BBRI')),
        throwsA(isA<AssetDefinitionLifecycleException>()),
      );
      expect(controller.error, contains('Symbol cannot be changed'));
      expect((await repository.getById(definition.id))?.symbol, 'BBCA');

      await repository.softDelete(
        definition.id,
        deletedAt: DateTime.utc(2026, 7, 24),
      );
      await expectLater(
        controller.save(definition.copyWith(displayName: 'Changed')),
        throwsA(isA<AssetDefinitionLifecycleException>()),
      );
      expect(controller.error, contains('Restore this asset'));
    });

    test('linked safe-field edits still run D13A provider checks', () async {
      final repository = _FakeAssetDefinitionRepository();
      final definition = _bbcaDefinition();
      final other = definition.copyWith(
        id: 'asset-bbri',
        displayName: 'Bank Rakyat Indonesia',
        symbol: 'BBRI',
        providerSymbol: 'BBRI.JK',
      );
      await repository.upsert(definition);
      await repository.upsert(other);
      final controller = AssetDefinitionController(
        repository: repository,
        transactionsProvider: () async => [
          _assetTransaction(definition: definition),
        ],
      );
      await controller.initialize();

      await expectLater(
        controller.save(definition.copyWith(providerSymbol: 'BBRI.JK')),
        throwsA(isA<AssetDefinitionIntegrityException>()),
      );
      expect(controller.error, contains('already used'));
    });

    test('restore is blocked by active symbol or provider conflicts', () async {
      final repository = _FakeAssetDefinitionRepository();
      final archived = _bbcaDefinition().copyWith(
        id: 'asset-archived',
        deletedAt: DateTime.utc(2026, 7, 23),
      );
      await repository.upsert(archived);
      await repository.upsert(_bbcaDefinition());
      final controller = AssetDefinitionController(repository: repository);
      await controller.initialize();

      await expectLater(
        controller.restore(archived),
        throwsA(isA<AssetDefinitionIntegrityException>()),
      );
      expect(controller.error, contains('Cannot restore'));
      expect((await repository.getById(archived.id))?.isDeleted, isTrue);

      final providerOnly = archived.copyWith(
        symbol: 'BBRI',
        providerSymbol: 'BBCA.JK',
      );
      await repository.upsert(providerOnly);
      await expectLater(
        controller.restore(providerOnly),
        throwsA(isA<AssetDefinitionIntegrityException>()),
      );
      expect(controller.error, contains('already used'));
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

Transaction _assetTransaction({
  String id = 'buy',
  required AssetDefinition definition,
  double quantity = 100,
  AssetAction action = AssetAction.buy,
}) {
  return Transaction(
    id: id,
    title: '${action.name} ${definition.displayName}',
    category: 'Asset conversion',
    account: 'Cash -> ${definition.displayName}',
    date: DateTime.utc(2026, 7, 24),
    amount: (quantity * 1000).round(),
    type: TransactionType.assetConversion,
    quantity: quantity,
    unit: definition.unit,
    unitPrice: 1000,
    assetDefinitionId: definition.id,
    assetName: definition.displayName,
    assetSymbol: definition.symbol,
    assetAction: action,
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
