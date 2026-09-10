import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart'
    as native;
import 'package:pilgrim_tracker/core/database/local_store_web.dart' as web;
import 'package:pilgrim_tracker/features/backup/data/portable_backup_codec.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_metadata.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_import_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/edit/transaction_form.dart';

import 'support/beta06_fixture.dart';

void main() {
  test('metadata normalizes, round-trips, clears, and validates centrally', () {
    final value = _transaction(
      reference: '  INV-123  ',
      note: 'Dinner, "shared"\nwith Grace 👋',
    );
    expect(value.reference, 'INV-123');
    expect(value.note, 'Dinner, "shared"\nwith Grace 👋');
    expect(Transaction.fromRecord(value.toRecord()).reference, 'INV-123');
    expect(Transaction.fromRecord(value.toRecord()).note, value.note);
    expect(value.copyWith(reference: '   ', note: '\n\t').reference, isNull);
    expect(value.copyWith(reference: '   ', note: '\n\t').note, isNull);
    expect(
      () => validateTransaction(_transaction(reference: 'x' * 257)),
      throwsA(isA<TransactionValidationException>()),
    );
    expect(
      () => validateTransaction(_transaction(note: 'x' * 4001)),
      throwsA(isA<TransactionValidationException>()),
    );
    expect(TransactionMetadataPolicy.referenceMaxLength, 256);
    expect(TransactionMetadataPolicy.noteMaxLength, 4000);
  });

  test('SQLite v26 upgrades to current and preserves null metadata', () async {
    final directory = await Directory.systemTemp.createTemp('beta08m0-');
    final path = '${directory.path}/test.db';
    final store = native.LocalStore(databasePath: path);
    await store.initialize();
    await store.upsertTransaction(
      _transaction().toRecord(),
      enqueueSync: false,
    );
    await store.db.execute('ALTER TABLE transactions DROP COLUMN note');
    await store.db.execute('ALTER TABLE transactions DROP COLUMN reference');
    await store.db.execute('PRAGMA user_version = 26');
    await store.close();

    await store.initialize();
    expect(await store.getSchemaVersion(), native.LocalStore.schemaVersion);
    final columns = (await store.db.rawQuery(
      'PRAGMA table_info(transactions)',
    )).map((row) => row['name']).toSet();
    expect(columns, containsAll(['note', 'reference']));
    final row = (await store.getTransactions()).single;
    expect(row['id'], 'transaction-m0');
    expect(row['amount'], 125000);
    expect(row['note'], isNull);
    expect(row['reference'], isNull);
    await store.close();
    await directory.delete(recursive: true);
  });

  for (final platform in ['native', 'web']) {
    test(
      '$platform persists metadata and preserves omitted remote fields',
      () async {
        final directory = await Directory.systemTemp.createTemp('beta08m0-');
        final bookId = 'book-beta08m0-$platform';
        final dynamic store = platform == 'native'
            ? native.LocalStore(databasePath: '${directory.path}/test.db')
            : web.LocalStore();
        await store.initialize();
        await store.activateHouseholdBackupSnapshot(
          HouseholdBackupIntegrity.prepareForRestore(
            beta06Snapshot(bookId: bookId),
          ),
          replaceBookId: bookId,
        );
        final initial = _transaction(
          bookId: bookId,
          note: 'Trip dinner with Grace',
          reference: 'INV-123',
        );
        await store.upsertTransaction(initial.toRecord(), enqueueSync: false);
        final legacy =
            initial.copyWith(title: 'Updated by old client').toRecord()
              ..remove('note')
              ..remove('reference');
        await store.applyRemoteSyncBatch(
          bookId,
          changes: [
            {
              'entity_type': 'transactions',
              'entity_id': initial.id,
              'payload': legacy,
            },
          ],
          finalSequence: 1,
        );
        var row = (await store.getTransactions(
          includeDeleted: true,
        )).firstWhere((item) => item['id'] == initial.id);
        expect(row['note'], 'Trip dinner with Grace');
        expect(row['reference'], 'INV-123');

        await store.applyRemoteSyncBatch(
          bookId,
          changes: [
            {
              'entity_type': 'transactions',
              'entity_id': initial.id,
              'payload': {...legacy, 'note': null, 'reference': null},
            },
          ],
          finalSequence: 2,
        );
        row = (await store.getTransactions(
          includeDeleted: true,
        )).firstWhere((item) => item['id'] == initial.id);
        expect(row['note'], isNull);
        expect(row['reference'], isNull);
        await store.close();
        await directory.delete(recursive: true);
      },
    );
  }

  test('v6 backup preserves metadata and v5 restores it as null', () async {
    final snapshot = beta06Snapshot();
    snapshot['transactions']!.first['note'] = 'Line one\nLine two, "quoted" 👋';
    snapshot['transactions']!.first['reference'] = 'BANK-42';
    final codec = PortableBackupCodec(databaseSchemaVersion: 27);

    final v6 = await codec.encode(
      snapshot: snapshot,
      password: 'test-password',
      formatVersion: 6,
    );
    final restoredV6 = await codec.decode(v6.bytes, 'test-password');
    expect(v6.manifest.formatVersion, 6);
    expect(
      restoredV6.snapshot['transactions']!.first['note'],
      'Line one\nLine two, "quoted" 👋',
    );
    expect(restoredV6.snapshot['transactions']!.first['reference'], 'BANK-42');

    final v5 = await codec.encode(
      snapshot: snapshot,
      password: 'test-password',
      formatVersion: 5,
    );
    final restoredV5 = await codec.decode(v5.bytes, 'test-password');
    expect(restoredV5.manifest.formatVersion, 5);
    expect(restoredV5.snapshot['transactions']!.first['note'], isNull);
    expect(restoredV5.snapshot['transactions']!.first['reference'], isNull);

    final clone = HouseholdBackupIntegrity.prepareForRestore(
      restoredV6.snapshot,
      remapAsCopy: true,
    );
    expect(
      clone['transactions']!.first['note'],
      restoredV6.snapshot['transactions']!.first['note'],
    );
    expect(clone['transactions']!.first['reference'], 'BANK-42');
  });

  test('existing simple CSV finalization persists edited metadata', () async {
    final repository = _BatchRepository();
    final account = Account(id: 'account', bookId: 'book', name: 'Bank');
    final controller = TransactionImportController(
      pickFile: () async => SelectedCsvFile(
        name: 'input.csv',
        bytes: utf8.encode(
          'date,description,amount,type,category,reference,note\n'
          '2026-08-01,Lunch,125000,expense,Groceries,OLD,"first note"',
        ),
      ),
      importBatch: ImportTransactionsBatch(repository),
      existingTransactions: () async => repository.saved,
      accounts: [account],
      expenseCategories: const ['Groceries'],
      incomeCategories: const ['Salary'],
      activeBookId: 'book',
      activeMemberId: 'member',
    );
    controller.selectAccount(account);
    await controller.selectCsv();
    await controller.analyze();
    final draft = controller.preview!.drafts.single;
    controller.editDraft(
      draft.transactionId,
      reference: ' NEW-REF ',
      note: 'edited, "quoted"\nmultiline 👋',
    );
    await controller.commit();
    expect(repository.saved.single.reference, 'NEW-REF');
    expect(repository.saved.single.note, 'edited, "quoted"\nmultiline 👋');
    controller.dispose();
  });

  testWidgets('full transaction edit sets and clears metadata', (tester) async {
    Transaction? submitted;
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );
    Future<void> pump(Transaction transaction) async {
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: TransactionForm(
              transaction: transaction,
              options: const TransactionFormOptions(
                accounts: ['Cash'],
                expenseCategories: ['Groceries'],
                incomeCategories: ['Salary'],
                projects: [],
              ),
              onSubmit: (value) async => submitted = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(_transaction());
    await tester.enterText(
      find.byKey(const Key('transaction-reference-field')),
      '  INV-123  ',
    );
    await tester.enterText(
      find.byKey(const Key('transaction-note-field')),
      'Line one\nLine two',
    );
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(submitted!.reference, 'INV-123');
    expect(submitted!.note, 'Line one\nLine two');

    final saved = submitted!;
    submitted = null;
    await pump(saved);
    await tester.enterText(
      find.byKey(const Key('transaction-reference-field')),
      '   ',
    );
    await tester.enterText(
      find.byKey(const Key('transaction-note-field')),
      '\n\t',
    );
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(submitted!.reference, isNull);
    expect(submitted!.note, isNull);
  });

  test('metadata does not change financial identity or amount', () {
    final original = _transaction();
    final edited = original.copyWith(note: 'memo', reference: 'REF');
    expect(edited.id, original.id);
    expect(edited.amount, original.amount);
    expect(edited.type, original.type);
    expect(edited.account, original.account);
    expect(edited.categoryId, original.categoryId);
  });
}

Transaction _transaction({
  String bookId = 'book-beta06',
  String? note,
  String? reference,
}) => Transaction(
  id: 'transaction-m0',
  bookId: bookId,
  enteredByMemberId: 'member-owner',
  title: 'Groceries',
  category: 'Groceries',
  account: 'Cash',
  date: DateTime.utc(2026, 9, 8),
  amount: 125000,
  type: TransactionType.expense,
  note: note,
  reference: reference,
);

class _BatchRepository implements TransactionBatchRepository {
  final List<Transaction> saved = [];

  @override
  Future<void> saveAllAtomic(List<Transaction> transactions) async {
    saved.addAll(transactions);
  }
}
