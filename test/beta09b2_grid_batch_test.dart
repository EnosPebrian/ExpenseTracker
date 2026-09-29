import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/data/grid_clipboard_codec.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_grid_batch.dart';
import 'package:pilgrim_tracker/features/transactions/domain/services/transaction_grid_policy.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/grid/transaction_grid.dart';
import 'beta09b1_transaction_grid_test.dart' as fixture;

void main() {
  test(
    'reviewed category identity is rechecked against current catalog',
    () async {
      final row = fixture.row();
      var calls = 0;
      final plan = TransactionGridBatch.plan(
        rows: [row],
        fields: [TransactionGridField.category],
        values: [
          ['Food'],
        ],
        policy: fixture.policy(),
      );
      final result = await GridBatchCommit.apply(
        plan,
        current: (_) => row,
        save: (_) async {
          calls++;
        },
        currentPolicy: () => const TransactionGridPolicy(
          accounts: [],
          expenseCategories: {'Food': 'replacement-id'},
          incomeCategories: {},
          projects: {},
        ),
      );
      expect(calls, 0);
      expect(result.single.message, contains('changed since review'));
    },
  );
  testWidgets('Shift selection copies visible rows and filters never write', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    var writes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionGrid(
            rows: [
              fixture.row(),
              fixture.row(1).copyWith(account: 'Bank'),
            ],
            policy: fixture.policy(),
            onSave: (_) async {
              writes++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Expense 0'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Expense 1'));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Copy selection'));
    await tester.pumpAndSettle();
    expect(GridClipboardCodec.decode(copied!).map((r) => r.single).toSet(), {
      'Expense 0',
      'Expense 1',
    });
    await tester.tap(find.byKey(const ValueKey('grid-filter-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank').last);
    await tester.pumpAndSettle();
    expect(find.text('Expense 0'), findsNothing);
    expect(find.text('Expense 1'), findsOneWidget);
    expect(writes, 0);
  });
  testWidgets('single-cell undo saves through normal update callback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var current = fixture.row();
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionGrid(
            rows: [current],
            policy: fixture.policy(),
            readCurrent: (_) => current,
            onSave: (r) async {
              writes++;
              current = r.copyWith(
                version: r.version + 1,
                updatedAt: DateTime(2026, 9, 29, 0, 0, writes),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Expense 0'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('grid-editor')), 'Edited');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(current.title, 'Edited');
    expect(current.version, 2);
    await tester.tap(find.text('Undo last cell edit'));
    await tester.pumpAndSettle();
    expect(current.title, 'Expense 0');
    expect(current.version, 3);
    expect(writes, 2);
  });
  test(
    'clipboard preserves tab/newline/quotes and rejects malformed rectangles',
    () {
      final values = [
        ['Note\nsecond', 'a\tb', '"quoted"'],
        ['1', '2', '3'],
      ];
      expect(
        GridClipboardCodec.decode(GridClipboardCodec.encode(values)),
        values,
      );
      expect(GridClipboardCodec.decode('one\ttwo\r\nthree\tfour\r\n'), [
        ['one', 'two'],
        ['three', 'four'],
      ]);
      expect(
        () => GridClipboardCodec.decode('one\ttwo\nthree'),
        throwsFormatException,
      );
      expect(
        () => GridClipboardCodec.decode('"unclosed'),
        throwsFormatException,
      );
      expect(
        GridClipboardCodec.encode([
          ['=1+1'],
        ]),
        "'=1+1",
      );
    },
  );
  test(
    'whole rectangle validates before apply; invalid cell blocks every row',
    () async {
      final rows = [fixture.row(), fixture.row(1)];
      final plan = TransactionGridBatch.plan(
        rows: rows,
        fields: [TransactionGridField.amount],
        values: [
          ['150'],
          ['oops'],
        ],
        policy: fixture.policy(),
      );
      expect(plan.canApply, isFalse);
      expect(plan.errors.single, contains('Row 2'));
      var calls = 0;
      await expectLater(
        GridBatchCommit.apply(
          plan,
          current: (id) => rows.firstWhere((r) => r.id == id),
          save: (_) async {
            calls++;
          },
        ),
        throwsStateError,
      );
      expect(calls, 0);
    },
  );
  test('protected, unknown category and cross-currency edits block', () {
    for (final input in [
      (
        fixture.row().copyWith(type: TransactionType.transfer),
        TransactionGridField.note,
        'x',
      ),
      (fixture.row(), TransactionGridField.category, 'new'),
      (fixture.row(), TransactionGridField.account, 'USD'),
    ]) {
      expect(
        TransactionGridBatch.plan(
          rows: [input.$1],
          fields: [input.$2],
          values: [
            [input.$3],
          ],
          policy: fixture.policy(),
        ).canApply,
        isFalse,
      );
    }
  });
  test(
    'reviewed updates preserve identity and report partial failure explicitly',
    () async {
      final rows = List.generate(3, fixture.row);
      final plan = TransactionGridBatch.plan(
        rows: rows,
        fields: [TransactionGridField.note],
        values: [
          ['a'],
          ['b'],
          ['c'],
        ],
        policy: fixture.policy(),
      );
      final saved = <Transaction>[];
      final results = await GridBatchCommit.apply(
        plan,
        current: (id) => rows.firstWhere((r) => r.id == id),
        save: (r) async {
          if (r.id == 'r1') throw StateError('disk');
          saved.add(r);
        },
      );
      expect(saved.map((r) => r.id), ['r0']);
      expect(results.map((r) => r.saved), [true, false, false]);
      expect(results[1].message, contains('uncertain'));
      expect(results[2].message, contains('Not attempted'));
    },
  );
  test('changed record blocks reviewed save and subsequent rows', () async {
    final row = fixture.row();
    var writes = 0;
    final plan = TransactionGridBatch.plan(
      rows: [row],
      fields: [TransactionGridField.reference],
      values: [
        ['ref'],
      ],
      policy: fixture.policy(),
    );
    final result = await GridBatchCommit.apply(
      plan,
      current: (_) => row.copyWith(version: 2),
      save: (_) async {
        writes++;
      },
    );
    expect(writes, 0);
    expect(result.single.saved, isFalse);
  });
  test(
    'undo prepares a normal mutation only against its exact saved version',
    () {
      final saved = fixture.row().copyWith(title: 'new', version: 2);
      final undo = GridUndoChange(
        saved,
        TransactionGridField.description,
        'old',
      );
      final next = undo.prepare(saved, fixture.policy());
      expect(next.title, 'old');
      expect(next.id, saved.id);
      expect(next.version, 2);
      expect(
        () => undo.prepare(saved.copyWith(version: 3), fixture.policy()),
        throwsStateError,
      );
      expect(GridUndoChange.supports(TransactionGridField.account), isFalse);
    },
  );
  testWidgets(
    'paste requires review then saves; rejected rectangle saves nothing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final saved = <Transaction>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': 'Changed'};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionGrid(
              rows: [fixture.row()],
              policy: fixture.policy(),
              onSave: (r) async {
                saved.add(r);
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Expense 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste / review'));
      await tester.pumpAndSettle();
      expect(find.text('Review bulk changes'), findsOneWidget);
      expect(saved, isEmpty);
      await tester.tap(find.text('Apply 1 rows'));
      await tester.pumpAndSettle();
      expect(saved.single.title, 'Changed');
      expect(find.text('Bulk save outcomes'), findsOneWidget);
    },
  );
}
