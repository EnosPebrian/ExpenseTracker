import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:pilgrim_tracker/features/transactions/data/repositories/local_transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';

class _TestDatabase {
  _TestDatabase({
    required this.directory,
    required this.path,
    required this.store,
  });

  final Directory directory;
  final String path;

  LocalStore store;

  LocalTransactionRepository get repository {
    return LocalTransactionRepository(store);
  }

  static Future<_TestDatabase> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'pilgrim_tracker_transactions_',
    );

    final path = p.join(directory.path, 'transactions.db');

    final store = LocalStore(databasePath: path);

    await store.initialize();

    return _TestDatabase(directory: directory, path: path, store: store);
  }

  Future<void> reopen() async {
    await store.close();

    store = LocalStore(databasePath: path);

    await store.initialize();
  }

  Future<List<Map<String, Object?>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final database = await databaseFactoryFfi.openDatabase(path);

    try {
      return await database.query(
        table,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
      );
    } finally {
      await database.close();
    }
  }

  Future<void> dispose() async {
    await store.close();

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

Transaction _sampleTransaction({
  String id = 'transaction-001',
  String title = 'Groceries',
  int amount = 125000,
  TransactionType type = TransactionType.expense,
  double? quantity,
  String? unit,
  int? unitPrice,
  String? assetDefinitionId,
  String? assetName,
  AssetAction? assetAction,
  String? assetSymbol,
}) {
  final timestamp = DateTime(2026, 7, 19, 9, 30);

  return Transaction(
    id: id,
    projectId: 'life',
    title: title,
    category: type == TransactionType.assetConversion
        ? 'Asset conversion'
        : 'Konsumsi',
    account: type == TransactionType.assetConversion
        ? 'Cash Enos -> Gold Holdings'
        : 'Cash Enos',
    date: timestamp,
    amount: amount,
    type: type,
    quantity: quantity,
    unit: unit,
    unitPrice: unitPrice,
    assetDefinitionId: assetDefinitionId,
    assetName: assetName,
    assetAction: assetAction,
    assetSymbol: assetSymbol,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

void main() {
  test('created transaction survives database close and reopen', () async {
    final database = await _TestDatabase.create();

    addTearDown(database.dispose);

    final created = await CreateTransaction(database.repository)(
      _sampleTransaction(),
    );

    await database.reopen();

    final loaded = await GetTransactions(database.repository)();

    expect(loaded, hasLength(1));

    final transaction = loaded.single;

    expect(transaction.id, created.id);
    expect(transaction.projectId, 'life');
    expect(transaction.title, 'Groceries');
    expect(transaction.category, 'Konsumsi');
    expect(transaction.account, 'Cash Enos');
    expect(transaction.amount, 125000);
    expect(transaction.type, TransactionType.expense);
    expect(transaction.date, DateTime(2026, 7, 19, 9, 30));
    expect(transaction.createdAt, created.createdAt);
    expect(transaction.updatedAt, created.updatedAt);
    expect(transaction.version, 1);
    expect(transaction.syncStatus, 'pending');
  });

  test('update preserves UUID and increments persisted version', () async {
    final database = await _TestDatabase.create();

    addTearDown(database.dispose);

    final repository = database.repository;

    final created = await CreateTransaction(repository)(_sampleTransaction());

    final updated = await UpdateTransaction(repository)(
      created.copyWith(title: 'Weekly groceries', amount: 175000),
    );

    final loaded = await GetTransactions(repository)();

    expect(loaded, hasLength(1));

    final transaction = loaded.single;

    expect(transaction.id, created.id);
    expect(transaction.id, updated.id);
    expect(transaction.title, 'Weekly groceries');
    expect(transaction.amount, 175000);
    expect(transaction.version, 2);
    expect(transaction.syncStatus, 'pending');
    expect(
      transaction.updatedAt.millisecondsSinceEpoch,
      greaterThanOrEqualTo(created.updatedAt.millisecondsSinceEpoch),
    );
  });

  test('soft delete hides transaction and persists delete metadata', () async {
    final database = await _TestDatabase.create();

    addTearDown(database.dispose);

    final repository = database.repository;

    final created = await CreateTransaction(repository)(_sampleTransaction());

    await DeleteTransaction(repository)(created);

    expect(await GetTransactions(repository)(), isEmpty);

    final rows = await database.query(
      'transactions',
      columns: ['id', 'deleted_at', 'version', 'sync_status'],
      where: 'id = ?',
      whereArgs: [created.id],
    );

    expect(rows, hasLength(1));
    expect(rows.single['id'], created.id);
    expect(rows.single['deleted_at'], isNotNull);
    expect(rows.single['version'], 2);
    expect(rows.single['sync_status'], 'pending');
  });

  test('asset conversion fields survive SQLite round trip', () async {
    final database = await _TestDatabase.create();

    addTearDown(database.dispose);

    final created = await CreateTransaction(database.repository)(
      _sampleTransaction(
        id: 'asset-conversion-001',
        title: 'Gold acquisition',
        amount: 50000000,
        type: TransactionType.assetConversion,
        quantity: 20.5,
        unit: 'gram',
        unitPrice: 2439024,
        assetName: 'Gold Holdings',
        assetDefinitionId: 'asset-gold',
        assetAction: AssetAction.buy,
      ),
    );

    await database.reopen();

    final loaded = await GetTransactions(database.repository)();

    expect(loaded, hasLength(1));

    final transaction = loaded.single;

    expect(transaction.id, created.id);
    expect(transaction.type, TransactionType.assetConversion);
    expect(transaction.account, 'Cash Enos -> Gold Holdings');
    expect(transaction.quantity, 20.5);
    expect(transaction.unit, 'gram');
    expect(transaction.unitPrice, 2439024);
    expect(transaction.assetDefinitionId, 'asset-gold');
    expect(transaction.assetName, 'Gold Holdings');
    expect(transaction.assetAction, AssetAction.buy);
    expect(transaction.amount, 50000000);
  });

  test('duplicate returned to UI matches the persisted record', () async {
    final database = await _TestDatabase.create();

    addTearDown(database.dispose);

    final repository = database.repository;

    final original = await CreateTransaction(repository)(_sampleTransaction());

    final duplicate = await DuplicateTransaction(repository)(original);

    final loaded = await GetTransactions(repository)();

    expect(loaded, hasLength(2));
    expect(duplicate.id, isNot(original.id));
    expect(duplicate.projectId, original.projectId);
    expect(duplicate.amount, original.amount);
    expect(duplicate.version, 1);
    expect(duplicate.syncStatus, 'pending');

    final persistedDuplicate = loaded.singleWhere(
      (transaction) => transaction.id == duplicate.id,
    );

    expect(persistedDuplicate.syncStatus, duplicate.syncStatus);
    expect(persistedDuplicate.version, duplicate.version);
    expect(persistedDuplicate.amount, duplicate.amount);
  });
}
