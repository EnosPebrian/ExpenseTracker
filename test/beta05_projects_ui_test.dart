import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/presentation/screens/projects_page.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

void main() {
  testWidgets('project summaries contain only real transaction totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsPage(
          projects: const ['BETA TEST Home'],
          projectIdsByName: const {
            'BETA TEST Home': '11111111-1111-4111-8111-111111111111',
          },
          currencyCode: 'IDR',
          transactions: [
            Transaction(
              title: 'Project income',
              category: 'Salary',
              account: 'Bank',
              date: DateTime(2026, 7, 28),
              amount: 2500000,
              type: TransactionType.income,
              projectId: '11111111-1111-4111-8111-111111111111',
            ),
            Transaction(
              title: 'Project expense',
              category: 'Fuel',
              account: 'Bank',
              date: DateTime(2026, 7, 28),
              amount: 400000,
              type: TransactionType.expense,
              projectId: '11111111-1111-4111-8111-111111111111',
            ),
          ],
          onSave:
              ({
                String? categoryType,
                required String entity,
                required String name,
                String? previousName,
              }) async {},
        ),
      ),
    );

    expect(find.text('Client Website'), findsNothing);
    expect(find.text('Product Launch'), findsNothing);
    expect(find.text('IDR 2.500.000'), findsOneWidget);
    expect(find.text('IDR 400.000'), findsOneWidget);
    expect(find.text('IDR 2.100.000'), findsOneWidget);
  });

  testWidgets('new project shows zero totals without fabricated analytics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsPage(
          projects: const ['BETA TEST Home'],
          transactions: const [],
          currencyCode: 'IDR',
          onSave:
              ({
                String? categoryType,
                required String entity,
                required String name,
                String? previousName,
              }) async {},
        ),
      ),
    );

    expect(find.text('IDR 0'), findsNWidgets(3));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
