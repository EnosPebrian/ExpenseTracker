import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/core/master_data/system_category.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const bookId = 'a2000000-0000-0000-0000-000000000001';

Future<LocalStore> createStore() async {
  final store = LocalStore(databasePath: inMemoryDatabasePath);
  await store.initialize();
  store.setActiveBookId(bookId);
  return store;
}

Map<String, Object?> category({
  required String id,
  String name = 'Tithe',
  String type = 'expense',
  String targetBook = bookId,
  int? deletedAt,
}) {
  final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
  return {
    'id': id,
    'book_id': targetBook,
    'name': name,
    'category_type': type,
    'created_at': now,
    'updated_at': now,
    'deleted_at': deletedAt,
    'version': 1,
    'device_id': 'test',
    'sync_status': 'local_only',
  };
}

void main() {
  group('BETA-08L system category local store', () {
    test('ensure missing creates exact canonical category', () async {
      final store = await createStore();
      addTearDown(store.close);
      expect(await store.ensureSystemCategories(bookId), isTrue);
      final rows = await store.getCategoryRecords(bookId: bookId);
      expect(rows, hasLength(1));
      expect(rows.single['id'], SystemCategoryIds.tithe(bookId));
      expect(rows.single['name'], 'Tithe');
      expect(rows.single['category_type'], 'expense');
    });

    test('repeated ensure is idempotent', () async {
      final store = await createStore();
      addTearDown(store.close);
      await store.ensureSystemCategories(bookId);
      expect(await store.ensureSystemCategories(bookId), isFalse);
      expect(await store.getCategoryRecords(bookId: bookId), hasLength(1));
    });

    test('repeated ensure creates no duplicate outbox operation', () async {
      final store = await createStore();
      addTearDown(store.close);
      final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      await store.db.insert('books', {
        'id': bookId,
        'name': 'Linked household',
        'base_currency_code': 'IDR',
        'remote_linked_at': now,
        'created_at': now,
        'updated_at': now,
        'version': 1,
        'device_id': 'test',
        'sync_status': 'synced',
      });
      await store.ensureSystemCategories(bookId);
      await store.ensureSystemCategories(bookId);
      final rows = await store.db.query(
        'sync_outbox',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['categories', SystemCategoryIds.tithe(bookId)],
      );
      expect(rows, hasLength(1));
    });

    test('existing valid canonical category is a no-op', () async {
      final store = await createStore();
      addTearDown(store.close);
      await store.db.insert(
        'categories',
        category(id: SystemCategoryIds.tithe(bookId)),
      );
      expect(await store.ensureSystemCategories(bookId), isFalse);
      expect(await store.db.query('sync_outbox'), isEmpty);
    });

    test('malformed canonical name is rejected without duplicate', () async {
      final store = await createStore();
      addTearDown(store.close);
      await store.db.insert(
        'categories',
        category(id: SystemCategoryIds.tithe(bookId), name: 'Wrong'),
      );
      await expectLater(
        store.ensureSystemCategories(bookId),
        throwsA(isA<SystemCategoryIntegrityException>()),
      );
      expect(await store.getCategoryRecords(bookId: bookId), hasLength(1));
    });

    test('malformed canonical type is rejected', () async {
      final store = await createStore();
      addTearDown(store.close);
      await store.db.insert(
        'categories',
        category(id: SystemCategoryIds.tithe(bookId), type: 'income'),
      );
      await expectLater(
        store.ensureSystemCategories(bookId),
        throwsA(isA<SystemCategoryIntegrityException>()),
      );
    });

    test('soft-deleted canonical category is rejected', () async {
      final store = await createStore();
      addTearDown(store.close);
      await store.db.insert(
        'categories',
        category(
          id: SystemCategoryIds.tithe(bookId),
          deletedAt: DateTime(2026, 2, 1).millisecondsSinceEpoch,
        ),
      );
      await expectLater(
        store.ensureSystemCategories(bookId),
        throwsA(isA<SystemCategoryIntegrityException>()),
      );
    });

    test(
      'custom same-name category is preserved beside System Tithe',
      () async {
        final store = await createStore();
        addTearDown(store.close);
        await store.db.insert('categories', category(id: 'custom-tithe'));
        await store.ensureSystemCategories(bookId);
        final rows = await store.getCategoryRecords(bookId: bookId);
        expect(rows, hasLength(2));
        expect(rows.map((row) => row['id']), contains('custom-tithe'));
      },
    );

    test('canonical rename is rejected at persistence boundary', () async {
      final store = await createStore();
      addTearDown(store.close);
      await store.ensureSystemCategories(bookId);
      await expectLater(
        store.saveMasterName(
          'categories',
          'Giving',
          previousName: 'Tithe',
          recordId: SystemCategoryIds.tithe(bookId),
          categoryType: 'expense',
        ),
        throwsA(isA<SystemCategoryIntegrityException>()),
      );
      expect(
        (await store.getCategoryRecords(bookId: bookId))
            .where((row) => row['id'] == SystemCategoryIds.tithe(bookId))
            .single['name'],
        'Tithe',
      );
    });

    test('custom same-name category can be renamed by stable ID', () async {
      final store = await createStore();
      addTearDown(store.close);
      await store.db.insert('categories', category(id: 'custom-tithe'));
      await store.ensureSystemCategories(bookId);
      await store.saveMasterName(
        'categories',
        'Giving',
        previousName: 'Tithe',
        recordId: 'custom-tithe',
        categoryType: 'expense',
      );
      final rows = await store.getCategoryRecords(bookId: bookId);
      expect(
        rows.where((row) => row['id'] == 'custom-tithe').single['name'],
        'Giving',
      );
      expect(
        rows
            .where((row) => row['id'] == SystemCategoryIds.tithe(bookId))
            .single['name'],
        'Tithe',
      );
    });
  });
}
