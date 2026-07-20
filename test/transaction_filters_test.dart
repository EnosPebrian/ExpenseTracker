import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/widgets/transaction_filters.dart';

void main() {
  testWidgets('Reset month button invokes reset callback', (tester) async {
    var resetCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionFilters(
            onSearch: (_) {},
            from: DateTime(2026, 7, 1),
            to: DateTime(2026, 7, 31),
            onFromChanged: (_) {},
            onToChanged: (_) {},
            onReset: () {
              resetCount++;
            },
          ),
        ),
      ),
    );

    expect(find.text('From  1/7/2026'), findsOneWidget);

    expect(find.text('To  31/7/2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('transaction-filter-reset')));

    await tester.pump();

    expect(resetCount, 1);
  });
}
