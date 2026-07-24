import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/edit/transaction_form.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';

void main() {
  testWidgets('asset edit preserves or explicitly clears execution reference', (
    tester,
  ) async {
    Transaction? submitted;
    final quotedAt = DateTime.utc(2026, 7, 24, 8);
    final transaction = Transaction(
      title: 'USD acquisition',
      category: 'Asset conversion',
      account: 'Cash -> US Dollar Cash (USD)',
      date: quotedAt,
      amount: 16300000,
      type: TransactionType.assetConversion,
      quantity: 1000,
      unit: 'usd',
      unitPrice: 16300,
      assetDefinitionId: 'asset-usd',
      assetName: 'US Dollar Cash',
      assetSymbol: 'USD',
      assetAction: AssetAction.buy,
      marketReferenceUnitPrice: 16250,
      marketReferenceCurrencyCode: 'IDR',
      marketReferenceUnit: 'usd',
      marketReferenceSource: AssetMarketReferenceSource.manual,
      marketReferenceQuotedAt: quotedAt,
    );
    final options = TransactionFormOptions(
      accounts: const ['Cash'],
      expenseCategories: const ['General'],
      incomeCategories: const ['Salary'],
      projects: const [],
      assetDefinitions: [_usd],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionForm(
            transaction: transaction,
            options: options,
            onSubmit: (value) async => submitted = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(submitted!.marketReferenceUnitPrice, 16250);
    expect(submitted!.marketReferenceQuotedAt, quotedAt);

    submitted = null;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionForm(
            transaction: transaction,
            options: options,
            onSubmit: (value) async => submitted = value,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Clear'));
    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(submitted!.marketReferenceUnitPrice, isNull);
    expect(submitted!.marketReferenceSource, isNull);
  });

  testWidgets('Edit Transaction changes project through searchable selection', (
    tester,
  ) async {
    Transaction? submitted;
    final transaction = Transaction(
      projectId: 'life',
      title: 'Groceries',
      category: 'Konsumsi',
      account: 'Cash Enos',
      date: DateTime(2026, 7, 19, 9, 30),
      amount: 125000,
      type: TransactionType.expense,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionForm(
            transaction: transaction,
            options: const TransactionFormOptions(
              accounts: ['Cash Enos', 'BNI Enos'],
              expenseCategories: ['Konsumsi', 'Transportasi'],
              incomeCategories: ['Gaji Enos'],
              projects: ['Life', 'Tebu Nai'],
            ),
            onSubmit: (value) async => submitted = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Life'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'tebu');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Tebu Nai'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.id, transaction.id);
    expect(submitted!.projectId, 'tebu-nai');
  });
  testWidgets('Edit Transaction remains open and displays persistence error', (
    tester,
  ) async {
    final transaction = Transaction(
      projectId: 'life',
      title: 'Groceries',
      category: 'Konsumsi',
      account: 'Cash Enos',
      date: DateTime(2026, 7, 19, 9, 30),
      amount: 125000,
      type: TransactionType.expense,
    );

    var submitCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionForm(
            transaction: transaction,
            options: const TransactionFormOptions(
              accounts: ['Cash Enos', 'BNI Enos'],
              expenseCategories: ['Konsumsi', 'Transportasi'],
              incomeCategories: ['Gaji Enos'],
              projects: ['Life', 'Tebu Nai'],
            ),
            onSubmit: (value) async {
              submitCount++;

              throw StateError('database unavailable');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(submitCount, 1);

    expect(find.text('Edit transaction'), findsOneWidget);

    expect(find.textContaining('database unavailable'), findsOneWidget);

    expect(find.text('Save changes'), findsOneWidget);
  });
}

final _usd = AssetDefinition(
  id: 'asset-usd',
  displayName: 'US Dollar Cash',
  kind: AssetKind.foreignCurrency,
  symbol: 'USD',
  providerCode: 'alpha_vantage',
  providerSymbol: 'USD/IDR',
  exchangeCode: null,
  currencyCode: 'IDR',
  unit: 'usd',
  lotSize: 1,
  onlinePricingEnabled: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'test',
  syncStatus: 'local_only',
);
