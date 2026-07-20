// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:pilgrim_tracker/main.dart';

void main() {
  testWidgets('starts local database initialization', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const PilgrimApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
