import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/presentation/widgets/master_data_list.dart';

Widget _testApp({
  required List<String> items,
  required MasterDataSaveCallback onSave,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MasterDataList(
        title: 'Accounts',
        subtitle: 'Available accounts',
        items: items,
        itemLabel: 'account',
        entity: 'accounts',
        onSave: onSave,
      ),
    ),
  );
}

void main() {
  testWidgets('adds master data after persistence succeeds', (tester) async {
    final items = <String>[];

    String? savedEntity;
    String? savedName;

    await tester.pumpWidget(
      _testApp(
        items: items,
        onSave:
            ({
              required String entity,
              required String name,
              String? previousName,
              String? categoryType,
            }) async {
              savedEntity = entity;
              savedName = name;

              items.add(name);
            },
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Savings Account');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(savedEntity, 'accounts');
    expect(savedName, 'Savings Account');
    expect(items, ['Savings Account']);
    expect(find.text('Savings Account'), findsOneWidget);
  });

  testWidgets('does not update list when persistence fails', (tester) async {
    final items = <String>[];

    await tester.pumpWidget(
      _testApp(
        items: items,
        onSave:
            ({
              required String entity,
              required String name,
              String? previousName,
              String? categoryType,
            }) async {
              throw StateError('database unavailable');
            },
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Broken Account');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(items, isEmpty);
    expect(find.textContaining('Could not save account'), findsOneWidget);
    expect(find.textContaining('database unavailable'), findsOneWidget);
  });

  testWidgets('editing passes previous name and updates after save', (
    tester,
  ) async {
    final items = <String>['Cash'];

    String? receivedPreviousName;
    String? savedName;

    await tester.pumpWidget(
      _testApp(
        items: items,
        onSave:
            ({
              required String entity,
              required String name,
              String? previousName,
              String? categoryType,
            }) async {
              receivedPreviousName = previousName;
              savedName = name;

              final itemIndex = items.indexOf(previousName!);
              items[itemIndex] = name;
            },
      ),
    );

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Wallet');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(receivedPreviousName, 'Cash');
    expect(savedName, 'Wallet');
    expect(items, ['Wallet']);
    expect(find.text('Cash'), findsNothing);
    expect(find.text('Wallet'), findsOneWidget);
  });

  testWidgets('rejects duplicate names without calling persistence', (
    tester,
  ) async {
    final items = <String>['Cash'];

    var saveCount = 0;

    await tester.pumpWidget(
      _testApp(
        items: items,
        onSave:
            ({
              required String entity,
              required String name,
              String? previousName,
              String? categoryType,
            }) async {
              saveCount++;
            },
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '  CASH  ');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(saveCount, 0);
    expect(items, ['Cash']);
    expect(find.textContaining('already exists'), findsOneWidget);
  });

  testWidgets('unchanged edit closes without calling persistence', (
    tester,
  ) async {
    final items = <String>['Cash'];

    var saveCount = 0;

    await tester.pumpWidget(
      _testApp(
        items: items,
        onSave:
            ({
              required String entity,
              required String name,
              String? previousName,
              String? categoryType,
            }) async {
              saveCount++;
            },
      ),
    );

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(saveCount, 0);
    expect(items, ['Cash']);
    expect(find.text('Cash'), findsOneWidget);
  });
}
