import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/app/presentation/widgets/app_bootstrap_error_view.dart';

void main() {
  testWidgets('bootstrap error view displays failure and triggers retry', (
    tester,
  ) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AppBootstrapErrorView(
          message: 'Database unavailable',
          onRetry: () {
            retryCount++;
          },
        ),
      ),
    );

    expect(find.text('Could not open your local data'), findsOneWidget);
    expect(find.text('Database unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(retryCount, 1);
  });
}
