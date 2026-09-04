import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_coordinator.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_models.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_repository.dart';
import 'package:pilgrim_tracker/features/sync/domain/sync_transport.dart';
import 'package:pilgrim_tracker/features/sync/presentation/controllers/sync_controller.dart';
import 'package:pilgrim_tracker/features/sync/presentation/widgets/sync_status_section.dart';

void main() {
  final linkedBook = FinancialBook(
    id: 'book',
    name: 'Linked',
    remoteLinkedAt: DateTime(2026, 7, 26),
  );

  test('not configured, signed out, and unlinked states are calm', () async {
    final repository = _FakeSyncRepository(
      state: SyncInitializationState.ready,
    );
    expect(
      (await SyncCoordinator(
        repository: repository,
        transport: const UnavailableSyncTransport(),
      ).inspect(linkedBook)).status,
      SyncStatus.notConfigured,
    );
    expect(
      (await SyncCoordinator(
        repository: repository,
        transport: _FakeTransport(authenticated: false),
      ).inspect(linkedBook)).status,
      SyncStatus.signedOut,
    );
    expect(
      (await SyncCoordinator(
        repository: repository,
        transport: _FakeTransport(),
      ).inspect(FinancialBook(id: 'local', name: 'Local'))).status,
      SyncStatus.localOnly,
    );
  });

  for (final entry in const {
    SyncInitializationState.notInitialized: SyncStatus.primaryUploadRequired,
    SyncInitializationState.primaryUploadRequired:
        SyncStatus.primaryUploadRequired,
    SyncInitializationState.secondaryDownloadRequired:
        SyncStatus.secondaryDownloadRequired,
  }.entries) {
    test('${entry.key.name} blocks incremental synchronization', () async {
      final transport = _FakeTransport();
      final coordinator = SyncCoordinator(
        repository: _FakeSyncRepository(state: entry.key),
        transport: transport,
      );
      final result = await coordinator.synchronize(linkedBook);
      expect(result.status, entry.value);
      expect(transport.pushCalls, 0);
      expect(transport.pullCalls, 0);
    });
  }

  test('ready run pushes, acknowledges, pulls, and advances cursor', () async {
    final operation = _operation();
    final repository = _FakeSyncRepository(
      state: SyncInitializationState.ready,
      operations: [operation],
    );
    final transport = _FakeTransport(
      pushResults: [
        PushOperationResult(
          operationId: operation.operationId,
          status: PushResultStatus.applied,
          serverVersion: 1,
          serverSequence: 7,
        ),
      ],
      pullBatch: PullBatch(
        changes: [
          RemoteChange(
            sequence: 7,
            entityType: 'transactions',
            entityId: 'transaction',
            serverVersion: 1,
            operationType: SyncOperationType.upsert,
            payload: const {'id': 'transaction', 'book_id': 'book'},
          ),
        ],
        finalSequence: 7,
      ),
    );
    final result = await SyncCoordinator(
      repository: repository,
      transport: transport,
    ).synchronize(linkedBook);

    expect(result.status, SyncStatus.synced);
    expect(result.pushedCount, 1);
    expect(result.pulledCount, 1);
    expect(repository.completed, [operation.operationId]);
    expect(repository.cursorSequence, 7);
  });

  test(
    'version conflict is persisted without overwriting local payload',
    () async {
      final operation = _operation();
      final repository = _FakeSyncRepository(
        state: SyncInitializationState.ready,
        operations: [operation],
      );
      final transport = _FakeTransport(
        pushResults: [
          PushOperationResult(
            operationId: operation.operationId,
            status: PushResultStatus.versionConflict,
            serverVersion: 4,
            serverPayload: const {'id': 'transaction', 'amount': 200},
          ),
        ],
      );

      final result = await SyncCoordinator(
        repository: repository,
        transport: transport,
      ).synchronize(linkedBook);
      expect(result.status, SyncStatus.conflict);
      expect(repository.conflicts, [operation.operationId]);
      expect(repository.completed, isEmpty);
    },
  );

  test(
    'network failure schedules retry and keeps local work pending',
    () async {
      final operation = _operation();
      final repository = _FakeSyncRepository(
        state: SyncInitializationState.ready,
        operations: [operation],
      );
      final transport = _FakeTransport(
        error: const SyncTransportException(
          SyncTransportErrorKind.network,
          'Offline.',
        ),
      );
      final result = await SyncCoordinator(
        repository: repository,
        transport: transport,
        now: () => DateTime(2026, 7, 26),
      ).synchronize(linkedBook);
      expect(result.status, SyncStatus.offline);
      expect(repository.retries, [operation.operationId]);
      expect(repository.completed, isEmpty);
    },
  );

  for (final entry in const {
    SyncTransportErrorKind.authentication: SyncStatus.signedOut,
    SyncTransportErrorKind.authorization: SyncStatus.error,
    SyncTransportErrorKind.validation: SyncStatus.error,
  }.entries) {
    test(
      '${entry.key.name} failure stops safely without a retry loop',
      () async {
        final operation = _operation();
        final repository = _FakeSyncRepository(
          state: SyncInitializationState.ready,
          operations: [operation],
        );
        final result = await SyncCoordinator(
          repository: repository,
          transport: _FakeTransport(
            error: SyncTransportException(entry.key, 'Sync stopped.'),
          ),
          now: () => DateTime(2026, 7, 26),
        ).synchronize(linkedBook);

        expect(result.status, entry.value);
        expect(repository.completed, isEmpty);
        expect(
          repository.retries,
          entry.key == SyncTransportErrorKind.authentication
              ? isEmpty
              : [operation.operationId],
        );
      },
    );
  }

  test('parallel sync requests use one transport run', () async {
    final gate = Completer<void>();
    final transport = _FakeTransport(pushGate: gate);
    final repository = _FakeSyncRepository(
      state: SyncInitializationState.ready,
      operations: [_operation()],
    );
    final coordinator = SyncCoordinator(
      repository: repository,
      transport: transport,
    );
    final first = coordinator.synchronize(linkedBook);
    final second = coordinator.synchronize(linkedBook);
    await Future<void>.delayed(Duration.zero);
    expect(transport.pushCalls, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(transport.pushCalls, 1);
  });

  test(
    'controller refreshes visible data after applying a remote pull',
    () async {
      var refreshCount = 0;
      final controller = SyncController(
        SyncCoordinator(
          repository: _FakeSyncRepository(state: SyncInitializationState.ready),
          transport: _FakeTransport(
            pullBatch: const PullBatch(
              changes: [
                RemoteChange(
                  sequence: 1,
                  entityType: 'transactions',
                  entityId: 'remote-transaction',
                  serverVersion: 1,
                  operationType: SyncOperationType.upsert,
                  payload: {'id': 'remote-transaction', 'book_id': 'book'},
                ),
              ],
              finalSequence: 1,
            ),
          ),
        ),
        onRemoteDataApplied: () async => refreshCount++,
      );
      addTearDown(controller.dispose);
      await controller.setBook(linkedBook, runWhenReady: false);

      await controller.syncNow();

      expect(controller.result.pulledCount, 1);
      expect(refreshCount, 1);
    },
  );

  test(
    'controller coalesces a trigger during sync into one follow-up run',
    () async {
      final gate = Completer<void>();
      final transport = _FakeTransport(pushGate: gate);
      final controller = SyncController(
        SyncCoordinator(
          repository: _FakeSyncRepository(
            state: SyncInitializationState.ready,
            operations: [_operation()],
          ),
          transport: transport,
        ),
      );
      addTearDown(controller.dispose);
      await controller.setBook(linkedBook, runWhenReady: false);

      final first = controller.syncNow();
      while (transport.pushCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.syncNow();
      await controller.syncNow();
      gate.complete();
      await first;

      expect(transport.pushCalls, 1);
      expect(transport.pullCalls, 2);
      expect(controller.status, SyncStatus.synced);
    },
  );

  testWidgets('startup, foreground, and mutation triggers stay coalesced', (
    tester,
  ) async {
    final transport = _FakeTransport();
    final controller = SyncController(
      SyncCoordinator(
        repository: _FakeSyncRepository(state: SyncInitializationState.ready),
        transport: transport,
      ),
    );
    addTearDown(controller.dispose);

    await controller.setBook(linkedBook);
    expect(transport.pullCalls, 1);

    controller.scheduleSync();
    controller.scheduleSync();
    controller.onResume();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(transport.pullCalls, 2);
    expect(controller.status, SyncStatus.synced);
  });

  testWidgets('initial upload warning disables Sync now', (tester) async {
    final controller = SyncController(
      SyncCoordinator(
        repository: _FakeSyncRepository(
          state: SyncInitializationState.primaryUploadRequired,
        ),
        transport: _FakeTransport(),
      ),
    );
    addTearDown(controller.dispose);
    await controller.setBook(linkedBook);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SyncStatusSection(controller: controller)),
      ),
    );
    expect(find.text('Initial upload required'), findsOneWidget);
    expect(
      find.byKey(const Key('sync-initial-upload-warning')),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('sync-now-button')),
    );
    expect(button.onPressed, isNull);
  });
}

SyncOperation _operation() => SyncOperation(
  operationId: 'operation',
  bookId: 'book',
  entityType: 'transactions',
  entityId: 'transaction',
  operationType: SyncOperationType.upsert,
  baseVersion: 0,
  payload: const {'id': 'transaction', 'book_id': 'book', 'amount': 100},
  createdAt: DateTime(2026, 7, 26),
  updatedAt: DateTime(2026, 7, 26),
  attemptCount: 0,
  status: SyncOutboxStatus.pending,
);

class _FakeSyncRepository implements SyncRepository {
  _FakeSyncRepository({required this.state, this.operations = const []});

  final SyncInitializationState state;
  final List<SyncOperation> operations;
  final completed = <String>[];
  final retries = <String>[];
  final conflicts = <String>[];
  var cursorSequence = 0;

  @override
  Future<SyncCursor?> getCursor(String bookId) async => SyncCursor(
    bookId: bookId,
    lastServerSequence: cursorSequence,
    initializationState: state,
    updatedAt: DateTime(2026, 7, 26),
  );

  @override
  Future<List<SyncOperation>> getEligibleOperations(
    String bookId, {
    int limit = 50,
  }) async => operations
      .where((item) => !completed.contains(item.operationId))
      .take(limit)
      .toList();

  @override
  Future<int> pendingCount(String bookId) async =>
      operations.where((item) => !completed.contains(item.operationId)).length;

  @override
  Future<void> recoverInterrupted(String bookId) async {}
  @override
  Future<void> markSending(Iterable<String> operationIds) async {}

  @override
  Future<void> markCompleted(String operationId, int? serverVersion) async {
    completed.add(operationId);
  }

  @override
  Future<void> scheduleRetry(
    String operationId, {
    required String errorCode,
    required String safeMessage,
    required DateTime nextAttemptAt,
  }) async {
    if (!retries.contains(operationId)) retries.add(operationId);
  }

  @override
  Future<void> recordConflict(
    SyncOperation operation,
    PushOperationResult result,
  ) async {
    conflicts.add(operation.operationId);
  }

  @override
  Future<int> unresolvedConflictCount(String bookId) async => conflicts.length;

  @override
  Future<void> applyRemoteBatch(String bookId, PullBatch batch) async {
    cursorSequence = batch.finalSequence;
  }

  @override
  Future<void> setInitializationState(
    String bookId,
    SyncInitializationState state,
  ) async {}
}

class _FakeTransport implements SyncTransport {
  _FakeTransport({
    this.authenticated = true,
    this.pushResults = const [],
    this.pullBatch = const PullBatch(changes: [], finalSequence: 0),
    this.error,
    this.pushGate,
  });

  final bool authenticated;
  final List<PushOperationResult> pushResults;
  final PullBatch pullBatch;
  final SyncTransportException? error;
  final Completer<void>? pushGate;
  int pushCalls = 0;
  int pullCalls = 0;

  @override
  bool get isConfigured => true;
  @override
  bool get isAuthenticated => authenticated;

  @override
  Future<List<PushOperationResult>> push(
    String bookId,
    List<SyncOperation> operations,
  ) async {
    pushCalls++;
    if (pushGate != null) await pushGate!.future;
    if (error != null) throw error!;
    if (pushResults.isNotEmpty) return pushResults;
    return [
      for (final operation in operations)
        PushOperationResult(
          operationId: operation.operationId,
          status: PushResultStatus.applied,
          serverVersion: operation.baseVersion + 1,
        ),
    ];
  }

  @override
  Future<PullBatch> pull(
    String bookId, {
    required int afterSequence,
    int limit = 100,
  }) async {
    pullCalls++;
    if (error != null) throw error!;
    return pullBatch.changes.isEmpty
        ? PullBatch(changes: const [], finalSequence: afterSequence)
        : pullBatch;
  }
}
