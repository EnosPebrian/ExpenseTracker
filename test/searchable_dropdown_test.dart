import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/main.dart';

void main() {
  testWidgets('selects the top category with Enter', (tester) async {
    String selected = 'Select Category';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableSelect(
            label: 'Category',
            value: selected,
            options: const ['Transport', 'Perpuluhan', 'Persembahan'],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Select Category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'perp');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 'Perpuluhan');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('Escape preserves the existing selection', (tester) async {
    String selected = 'Transport';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableSelect(
            label: 'Category',
            value: selected,
            options: const ['Transport', 'Food & dining', 'Perpuluhan'],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'food');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(selected, 'Transport');
  });

  testWidgets('selects the top BNI account with Enter', (tester) async {
    String selected = 'Select Account';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableSelect(
            label: 'Account',
            value: selected,
            options: const ['CIMB Enos', 'BNI Enos', 'BNI Grace'],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select Account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'BNI');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'BNI Enos');
  });

  testWidgets('selects a partial project match with Enter', (tester) async {
    String selected = 'No project';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableSelect(
            label: 'Project',
            value: selected,
            options: const ['No project', 'Life', 'Tebu Nai', 'Motor Listrik'],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('No project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'motor');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'Motor Listrik');
  });
}
