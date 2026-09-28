import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/core/database/sync_outbox_order.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/sync/data/local_sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/data/supabase_sync_transport.dart';
import 'package:pilgrim_tracker/features/sync/domain/conflict_resolution_service.dart';
import 'package:pilgrim_tracker/features/sync/domain/conflict_merge_policy.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_coordinator.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_models.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_transport.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/presentation/controllers/sync_conflict_controller.dart';
import 'package:pilgrim_tracker/features/sync/presentation/screens/conflict_review_screen.dart';
import 'package:pilgrim_tracker/features/sync/presentation/controllers/sync_controller.dart';
import 'package:pilgrim_tracker/features/sync/presentation/widgets/sync_status_section.dart';

final book = FinancialBook(
  id: 'book',
  name: 'Shared',
  remoteLinkedAt: DateTime(2026, 9, 27),
);
final stamp = DateTime(2026, 9, 27).millisecondsSinceEpoch;
Map<String, Object?> row(
  String id, {
  int version = 1,
  String title = 'Local',
}) => {
  'id': id,
  'book_id': 'book',
  'title': title,
  'category': 'Food',
  'account': 'Cash',
  'transaction_date': stamp,
  'amount': 100,
  'transaction_type': 'expense',
  'created_at': stamp,
  'updated_at': stamp,
  'version': version,
  'device_id': 'A',
  'sync_status': 'pending',
};
Map<String, Object?> operation(
  Map<String, Object?> payload, {
  String type = 'transactions',
}) => {
  'operation_id': 'op-${payload['id']}-${payload['version']}',
  'book_id': 'book',
  'entity_type': type,
  'entity_id': payload['id'],
  'operation_type': 'upsert',
  'base_version': (payload['version'] as int) - 1,
  'payload_json': jsonEncode(payload),
  'created_at': stamp,
  'updated_at': stamp,
  'status': 'pending',
  'attempt_count': 0,
};
Future<LocalStore> database() async {
  final dir = await Directory.systemTemp.createTemp('beta09a-');
  final store = LocalStore(databasePath: p.join(dir.path, 'sync.db'));
  await store.initialize();
  await store.setSyncInitializationState('book', 'ready');
  addTearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  return store;
}

Future<void> save(LocalStore store, Map<String, Object?> payload) =>
    store.db.transaction((txn) async {
      await txn.insert(
        'transactions',
        payload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('sync_outbox', operation(payload));
    });
Future<SyncConflict> conflict(LocalStore store, Server server) async {
  final local = row('edit', version: 2);
  await save(store, local);
  server.add(row('edit', version: 2, title: 'Cloud'));
  final repo = LocalSyncRepository(store as dynamic);
  await SyncCoordinator(repository: repo, transport: server).synchronize(book);
  return (await repo.conflicts('book')).single;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'A atomic import, conflict, B offline then converges without echo or skipped cursor',
    () async {
      final a = await database();
      final b = await database();
      final server = Server();
      final c = await conflict(a, server);
      final aRepo = LocalSyncRepository(a as dynamic);
      final bRepo = LocalSyncRepository(b as dynamic);
      // One import transaction exceeds the RPC page size.
      await a.db.transaction((txn) async {
        for (var i = 0; i < 125; i++) {
          final payload = row('import-$i');
          await txn.insert('transactions', payload);
          await txn.insert('sync_outbox', operation(payload));
        }
      });
      final sync = SyncCoordinator(repository: aRepo, transport: server);
      final result = await sync.synchronize(book);
      expect(result.status, SyncStatus.conflict);
      expect(result.pushedCount, 125);
      expect(await a.getUnresolvedSyncConflictCount('book'), 1);
      expect(
        (await a.getTransactions()).firstWhere(
          (r) => r['id'] == 'edit',
        )['title'],
        'Local',
      );
      final before = (await a.getSyncCursor('book'))!['last_server_sequence'];
      server.add(row('between'));
      final gate = Completer<void>();
      server.gate = gate;
      final resolver = ConflictResolutionService(
        repository: aRepo,
        transport: server,
      );
      final resolution = resolver.resolve(
        c,
        ConflictResolutionType.manualMerge,
        mergedPayload: {
          ...c.serverPayload!,
          'title': 'Local',
          'note': 'Reviewed',
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(await a.getUnresolvedSyncConflictCount('book'), 1);
      gate.complete();
      await resolution;
      expect((await a.getSyncCursor('book'))!['last_server_sequence'], before);
      expect(await a.getUnresolvedSyncConflictCount('book'), 0);
      expect((await sync.synchronize(book)).status, SyncStatus.synced);
      expect(
        (await a.getTransactions()).any((r) => r['id'] == 'between'),
        isTrue,
      );
      final bSync = SyncCoordinator(repository: bRepo, transport: server);
      expect((await bSync.synchronize(book)).status, SyncStatus.synced);
      final rows = await b.getTransactions();
      expect(rows.length, 127);
      expect(rows.firstWhere((r) => r['id'] == 'edit')['note'], 'Reviewed');
      expect((await bSync.synchronize(book)).pulledCount, 0);
      expect(await b.getPendingSyncCount('book'), 0);
      expect(await a.getPendingSyncCount('book'), 0);
      expect(await b.db.query('sync_outbox'), isEmpty);
    },
  );

  test(
    'network response loss and restart replay the saved intent/operation exactly once',
    () async {
      final store = await database();
      final server = Server();
      final c = await conflict(store, server);
      final repo = LocalSyncRepository(store as dynamic);
      server.loseResponse = true;
      await expectLater(
        ConflictResolutionService(repository: repo, transport: server).resolve(
          c,
          ConflictResolutionType.manualMerge,
          mergedPayload: {...c.serverPayload!, 'title': 'Reviewed'},
        ),
        throwsA(isA<SyncTransportException>()),
      );
      final pending = (await repo.conflicts('book')).single;
      expect(pending.resolutionIntent, isNotNull);
      final id = pending.resolutionOperationId;
      await store.close();
      await store.initialize();
      // A recreated service must replay the saved choice, not the clicked shortcut.
      await ConflictResolutionService(
        repository: repo,
        transport: server,
      ).resolve(
        (await repo.conflicts('book')).single,
        ConflictResolutionType.keepServer,
      );
      expect(server.resolutions.keys, [id]);
      expect((await store.getTransactions()).single['title'], 'Reviewed');
      expect(await repo.conflicts('book'), isEmpty);
    },
  );

  for (final rejection in ['validationError', 'staleResolution']) {
    test(
      '$rejection retains conflict and allows a newly reviewed decision',
      () async {
        final store = await database();
        final server = Server();
        final c = await conflict(store, server);
        server.rejection = rejection;
        if (rejection == 'staleResolution') {
          server.add(row('edit', version: 3, title: 'New cloud'));
        }
        final repo = LocalSyncRepository(store as dynamic);
        final service = ConflictResolutionService(
          repository: repo,
          transport: server,
        );
        await expectLater(
          service.resolve(c, ConflictResolutionType.keepDevice),
          throwsStateError,
        );
        final retained = (await repo.conflicts('book')).single;
        expect(retained.resolutionIntent, isNull);
        expect((await store.getTransactions()).single['title'], 'Local');
        if (rejection == 'staleResolution') expect(retained.serverVersion, 3);
        server.rejection = null;
        await service.resolve(retained, ConflictResolutionType.keepServer);
        expect(await repo.conflicts('book'), isEmpty);
      },
    );
  }

  test(
    'resolving state survives interruption; local apply failure does not clear conflict',
    () async {
      final store = await database();
      final server = Server();
      final c = await conflict(store, server);
      final repo = LocalSyncRepository(store as dynamic);
      await repo.prepareResolution(c.id, 'saved-operation', {
        'type': 'keepDevice',
        'payload': c.localPayload,
      });
      // Equivalent to an app death after durable prepare but before HTTP.
      await store.close();
      await store.initialize();
      await ConflictResolutionService(
        repository: repo,
        transport: server,
      ).resolve(
        (await repo.conflicts('book')).single,
        ConflictResolutionType.keepServer,
      );
      expect(server.resolutions.keys, ['saved-operation']);
      expect((await store.getTransactions()).single['title'], 'Local');
    },
  );

  test(
    'dirty/older remote rows cannot replace local intent; cursor consumes unrelated rows',
    () async {
      final store = await database();
      await save(store, row('dirty', version: 3));
      await store.db.insert('transactions', row('newer', version: 5));
      await store.applyRemoteSyncBatch(
        'book',
        changes: [
          for (final payload in [
            row('dirty', title: 'Remote'),
            row('newer'),
            row('other'),
          ])
            {
              'entity_type': 'transactions',
              'entity_id': payload['id'],
              'payload': payload,
            },
        ],
        finalSequence: 20,
      );
      final rows = await store.getTransactions();
      expect(rows.firstWhere((r) => r['id'] == 'dirty')['version'], 3);
      expect(rows.firstWhere((r) => r['id'] == 'newer')['version'], 5);
      expect(rows.length, 3);
      expect((await store.getSyncCursor('book'))!['last_server_sequence'], 20);
    },
  );

  test(
    'web resolution does not advance cursor past unconsumed records',
    () async {
      final store = web.LocalStore();
      await store.initialize();
      const bookId = 'web-09a';
      await store.setSyncInitializationState(bookId, 'ready');
      final payload = {...row('web-edit'), 'book_id': bookId};
      await store.recordSyncConflict({
        'book_id': bookId,
        'entity_type': 'transactions',
        'entity_id': 'web-edit',
        'operation_id': 'web-op',
        'base_version': 0,
        'server_version': 1,
        'local_payload_json': jsonEncode(payload),
        'server_payload_json': jsonEncode(payload),
        'resolution_status': 'unresolved',
      });
      final c = (await store.getSyncConflicts(bookId)).single;
      await store.beginSyncConflictResolution(c['id'] as String, 'web-resolve');
      await store.completeSyncConflictResolution(
        c['id'] as String,
        resolution: 'keepServer',
        canonicalPayload: payload,
        serverSequence: 99,
      );
      expect((await store.getSyncCursor(bookId))!['last_server_sequence'], 0);
    },
  );

  test(
    'dependencies precede import transactions and blocked parents prevent child push',
    () {
      final asset = operation({
        ...row('asset'),
        'version': 1,
      }, type: 'asset_definitions');
      final trade = operation({
        ...row('trade'),
        'asset_definition_id': 'asset',
      });
      final settlement = operation({
        ...row('settlement'),
        'trade_ids_json': '["trade"]',
      }, type: 'brokerage_settlements');
      final ordered = SyncOutboxOrder.eligible(
        [settlement, trade, asset],
        now: stamp,
        limit: 50,
      );
      expect(ordered.map((r) => r['entity_id']), ['asset']);
      expect(
        SyncOutboxOrder.eligible(
          [settlement, trade],
          now: stamp,
          limit: 50,
        ).map((r) => r['entity_id']),
        ['trade'],
      );
      expect(
        SyncOutboxOrder.eligible(
          [settlement],
          now: stamp,
          limit: 50,
        ).map((r) => r['entity_id']),
        ['settlement'],
      );
      expect(
        SyncOutboxOrder.eligible(
          [
            settlement,
            trade,
            {...asset, 'status': 'conflict'},
          ],
          now: stamp,
          limit: 50,
        ),
        isEmpty,
      );
    },
  );

  test('transaction category stable ID round-trips through transport', () {
    final payload = {...row('tx'), 'category_id': 'category'};
    expect(
      SupabaseSyncTransport.toLocalPayload(
        'transactions',
        SupabaseSyncTransport.toRemotePayload('transactions', payload),
      )['category_id'],
      'category',
    );
  });

  test(
    'simultaneous A/B edits converge after explicit resolution without echo',
    () async {
      final a = await database();
      final b = await database();
      final server = Server()..add(row('simultaneous'));
      final ar = LocalSyncRepository(a as dynamic);
      final br = LocalSyncRepository(b as dynamic);
      final ac = SyncCoordinator(repository: ar, transport: server);
      final bc = SyncCoordinator(repository: br, transport: server);
      await ac.synchronize(book);
      await bc.synchronize(book);
      await save(a, row('simultaneous', version: 2, title: 'Device A'));
      await save(b, row('simultaneous', version: 2, title: 'Device B'));
      await Future.wait([ac.synchronize(book), bc.synchronize(book)]);
      final conflictsA = await ar.conflicts('book');
      final conflictsB = await br.conflicts('book');
      expect(conflictsA.length + conflictsB.length, 1);
      final resolverRepo = conflictsA.isEmpty ? br : ar;
      final pending = (await resolverRepo.conflicts('book')).single;
      await ConflictResolutionService(
        repository: resolverRepo,
        transport: server,
      ).resolve(pending, ConflictResolutionType.keepDevice);
      await ac.synchronize(book);
      await bc.synchronize(book);
      expect(
        (await a.getTransactions()).single['title'],
        (await b.getTransactions()).single['title'],
      );
      expect(await a.getPendingSyncCount('book'), 0);
      expect(await b.getPendingSyncCount('book'), 0);
    },
  );

  test(
    'local apply rejection rolls back and retains accepted resolution for retry',
    () async {
      final store = await database();
      final server = Server();
      final c = await conflict(store, server);
      final repo = LocalSyncRepository(store as dynamic);
      await store.db.execute(
        "CREATE TRIGGER reject_resolution BEFORE INSERT ON transactions "
        "WHEN NEW.title = 'Reviewed' BEGIN SELECT RAISE(ABORT, 'fixture rejection'); END",
      );
      final service = ConflictResolutionService(
        repository: repo,
        transport: server,
      );
      await expectLater(
        service.resolve(
          c,
          ConflictResolutionType.manualMerge,
          mergedPayload: {...c.serverPayload!, 'title': 'Reviewed'},
        ),
        throwsA(anything),
      );
      expect(await repo.conflicts('book'), hasLength(1));
      expect((await store.getTransactions()).single['title'], 'Local');
      expect(await store.getPendingSyncCount('book'), 1);
      await store.db.execute('DROP TRIGGER reject_resolution');
      await service.resolve(
        (await repo.conflicts('book')).single,
        ConflictResolutionType.keepServer,
      );
      expect((await store.getTransactions()).single['title'], 'Reviewed');
      expect(server.resolutions.length, 1);
    },
  );

  test(
    'a newer local edit during resolution is not discarded by the older acknowledgement',
    () async {
      final store = await database();
      final server = Server();
      final c = await conflict(store, server);
      final repo = LocalSyncRepository(store as dynamic);
      await save(store, row('edit', version: 3, title: 'Later local edit'));
      await ConflictResolutionService(
        repository: repo,
        transport: server,
      ).resolve(c, ConflictResolutionType.keepServer);
      expect(
        (await store.getTransactions()).single['title'],
        'Later local edit',
      );
      expect(await store.getPendingSyncCount('book'), 1);
      await SyncCoordinator(
        repository: repo,
        transport: server,
      ).synchronize(book);
      expect(server.records['edit']!['title'], 'Later local edit');
    },
  );

  test('linked/system records cannot form a financial hybrid', () {
    final c = SyncConflict(
      id: 'c',
      bookId: 'book',
      entityType: 'transactions',
      entityId: 'tx',
      operationId: 'o',
      baseVersion: 1,
      serverVersion: 2,
      localPayload: {...row('tx'), 'brokerage_account_id': 'broker'},
      serverPayload: {
        ...row('tx'),
        'amount': 200,
        'brokerage_account_id': 'broker',
      },
      createdAt: DateTime.now(),
    );
    expect(ConflictMergePolicy.fields(c), isEmpty);
    expect(
      () => ConflictMergePolicy.validateTransaction(c, {
        ...c.localPayload!,
        'amount': 150,
      }),
      throwsStateError,
    );
  });

  testWidgets('offline status does not hide persisted conflict review', (
    tester,
  ) async {
    final controller = SyncController(
      SyncCoordinator(repository: UnusedSyncRepository(), transport: Server()),
    );
    addTearDown(controller.dispose);
    controller.conflictCount = 1;
    controller.result = const SyncRunResult(status: SyncStatus.offline);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusSection(
            controller: controller,
            onReviewConflicts: () => opened = true,
          ),
        ),
      ),
    );
    expect(find.textContaining('Conflicts: 1'), findsOneWidget);
    await tester.tap(find.text('Review conflicts'));
    expect(opened, isTrue);
  });

  testWidgets(
    'manual merge opens explicit choices and network failure stays visible',
    (tester) async {
      final server = Server();
      final c = SyncConflict(
        id: 'ui-conflict',
        bookId: 'book',
        entityType: 'transactions',
        entityId: 'edit',
        operationId: 'ui-op',
        baseVersion: 1,
        serverVersion: 2,
        localPayload: row('edit'),
        serverPayload: row('edit', title: 'Cloud'),
        createdAt: DateTime.now(),
      );
      server.add(c.serverPayload!);
      final controller = SyncConflictController(
        service: ConflictResolutionService(
          repository: MemoryConflicts(c),
          transport: server,
        ),
      );
      await controller.setBook('book');
      await tester.pumpWidget(
        MaterialApp(home: ConflictReviewScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge manually'));
      await tester.pumpAndSettle();
      expect(find.text('Merge transaction fields'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply reviewed merge'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Local: Local'));
      await tester.pump();
      server.loseResponse = true;
      await tester.tap(find.text('Apply reviewed merge'));
      await tester.pumpAndSettle();
      expect(find.text('Merge transaction fields'), findsOneWidget);
      expect(controller.count, 1);
      expect(find.textContaining('Resolution failed'), findsWidgets);
    },
  );
}

class UnusedSyncRepository implements SyncRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryConflicts implements SyncConflictRepository {
  MemoryConflicts(this.conflict);
  SyncConflict? conflict;
  @override
  Future<List<SyncConflict>> conflicts(String bookId) async => [?conflict];
  @override
  Future<bool> beginResolution(String id, String operation) async => true;
  @override
  Future<void> failResolution(String id) async {}
  @override
  Future<void> completeResolution(
    String id, {
    required String resolution,
    required Map<String, Object?> canonicalPayload,
    required int serverSequence,
  }) async {
    conflict = null;
  }
}

class Server implements SyncTransport, ConflictResolutionTransport {
  final records = <String, Map<String, Object?>>{};
  final changes = <RemoteChange>[];
  final resolutions = <String, ConflictResolutionResult>{};
  Completer<void>? gate;
  bool loseResponse = false;
  String? rejection;
  @override
  bool get isConfigured => true;
  @override
  bool get isAuthenticated => true;
  void add(Map<String, Object?> payload) {
    records[payload['id'] as String] = {...payload};
    changes.add(
      RemoteChange(
        sequence: changes.length + 1,
        entityType: 'transactions',
        entityId: payload['id'] as String,
        serverVersion: payload['version'] as int,
        operationType: SyncOperationType.upsert,
        payload: {...payload},
      ),
    );
  }

  @override
  Future<List<PushOperationResult>> push(
    String bookId,
    List<SyncOperation> operations,
  ) async => [for (final op in operations) _push(op)];
  PushOperationResult _push(SyncOperation op) {
    final current = records[op.entityId];
    if ((current?['version'] ?? 0) != op.baseVersion) {
      return PushOperationResult(
        operationId: op.operationId,
        status: PushResultStatus.versionConflict,
        serverVersion: current?['version'] as int?,
        serverPayload: current,
      );
    }
    add({...op.payload!, 'version': op.baseVersion + 1});
    return PushOperationResult(
      operationId: op.operationId,
      status: PushResultStatus.applied,
      serverVersion: op.baseVersion + 1,
      serverSequence: changes.length,
    );
  }

  @override
  Future<PullBatch> pull(
    String bookId, {
    required int afterSequence,
    int limit = 100,
  }) async {
    final rows = changes
        .where((c) => c.sequence > afterSequence)
        .take(limit)
        .map(
          (c) => RemoteChange(
            sequence: c.sequence,
            entityType: c.entityType,
            entityId: c.entityId,
            serverVersion: records[c.entityId]!['version'] as int,
            operationType: c.operationType,
            payload: records[c.entityId]!,
          ),
        )
        .toList();
    return PullBatch(
      changes: rows,
      finalSequence: rows.lastOrNull?.sequence ?? afterSequence,
    );
  }

  @override
  Future<ConflictResolutionResult> resolveConflict({
    required SyncConflict conflict,
    required String resolutionOperationId,
    required ConflictResolutionType resolutionType,
    Map<String, Object?>? resolvedPayload,
  }) async {
    await gate?.future;
    if (resolutions.containsKey(resolutionOperationId)) {
      return resolutions[resolutionOperationId]!;
    }
    if (rejection != null) {
      return ConflictResolutionResult(
        status: rejection!,
        canonicalPayload: records[conflict.entityId],
      );
    }
    if (resolutionType != ConflictResolutionType.keepServer) {
      add({...resolvedPayload!, 'version': conflict.serverVersion + 1});
    }
    final result = ConflictResolutionResult(
      status: 'resolved',
      canonicalPayload: records[conflict.entityId],
      serverSequence: changes.length,
    );
    resolutions[resolutionOperationId] = result;
    if (loseResponse) {
      loseResponse = false;
      throw const SyncTransportException(
        SyncTransportErrorKind.network,
        'Lost response',
      );
    }
    return result;
  }
}
