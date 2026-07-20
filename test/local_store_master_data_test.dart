import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<LocalStore> _createStore() async {
  final store = LocalStore(databasePath: inMemoryDatabasePath);

  await store.initialize();

  return store;
}

void main() {
  test('category rename only updates the selected category type', () async {
    final store = await _createStore();
    addTearDown(store.close);

    await store.ensureMasterSeeds('categories', const [
      'Other',
    ], categoryType: 'expense');

    await store.ensureMasterSeeds('categories', const [
      'Other',
    ], categoryType: 'income');

    await store.saveMasterName(
      'categories',
      'Dining',
      previousName: 'Other',
      categoryType: 'expense',
    );

    expect(await store.getMasterNames('categories', categoryType: 'expense'), [
      'Dining',
    ]);

    expect(await store.getMasterNames('categories', categoryType: 'income'), [
      'Other',
    ]);

    final rows = await store.db.query(
      'categories',
      columns: ['version', 'sync_status'],
      where: 'name = ? AND category_type = ?',
      whereArgs: ['Dining', 'expense'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['version'], 2);
    expect(rows.single['sync_status'], 'pending');
  });

  test('successive renames continue incrementing record version', () async {
    final store = await _createStore();
    addTearDown(store.close);

    await store.ensureMasterSeeds('accounts', const ['Cash']);

    await store.saveMasterName('accounts', 'Wallet', previousName: 'Cash');

    await store.saveMasterName('accounts', 'Pocket', previousName: 'Wallet');

    final rows = await store.db.query(
      'accounts',
      columns: ['name', 'version', 'sync_status'],
      where: 'name = ?',
      whereArgs: ['Pocket'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Pocket');
    expect(rows.single['version'], 3);
    expect(rows.single['sync_status'], 'pending');
  });

  test('category rename without category type is rejected', () async {
    final store = await _createStore();
    addTearDown(store.close);

    await store.ensureMasterSeeds('categories', const [
      'Other',
    ], categoryType: 'expense');

    await expectLater(
      store.saveMasterName('categories', 'Dining', previousName: 'Other'),
      throwsA(isA<ArgumentError>()),
    );

    expect(await store.getMasterNames('categories', categoryType: 'expense'), [
      'Other',
    ]);
  });
}
