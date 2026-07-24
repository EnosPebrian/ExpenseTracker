import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/asset_market_reference_source.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/screens/transaction_detail_screen.dart';

class _FailingDeleteRepository implements TransactionRepository {
  @override
  Future<List<Transaction>> getAll({bool includeDeleted = false}) async {
    return const [];
  }

  @override
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async => null;

  @override
  Future<void> save(Transaction transaction) async {}

  @override
  Future<void> softDelete(Transaction transaction) async {
    throw StateError('database unavailable');
  }

  @override
  Future<void> saveAssetFeeChange({
    required Transaction parent,
    Transaction? linkedExpense,
    Transaction? obsoleteLinkedExpense,
  }) async => throw StateError('database unavailable');
}

TransactionController _createController(TransactionRepository repository) {
  return TransactionController(
    create: CreateTransaction(repository),
    update: UpdateTransaction(repository),
    delete: DeleteTransaction(repository),
    get: GetTransactions(repository),
    duplicate: DuplicateTransaction(repository),
  );
}

void main() {
  testWidgets(
    'linked fee detail identifies managed status and blocks actions',
    (tester) async {
      final repository = _FailingDeleteRepository();
      final controller = _createController(repository);
      addTearDown(controller.dispose);
      final child = Transaction(
        title: 'Fee - Buy USD',
        category: 'Asset Fees',
        account: 'Cash Enos',
        date: DateTime(2026, 7, 24),
        amount: 100000,
        type: TransactionType.expense,
        relatedTransactionId: 'parent-usd',
        relationType: TransactionRelationType.assetFeeExpense,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => TransactionDetailScreen.show(
                context,
                transaction: child,
                controller: controller,
                onEdit: (_) {},
              ),
              child: const Text('Open managed detail'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open managed detail'));
      await tester.pumpAndSettle();

      expect(find.text(managedAssetFeeExpenseMessage), findsOneWidget);
      expect(find.text('Execution price'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Delete'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Edit transaction'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('parent asset detail shows saved execution comparison', (
    tester,
  ) async {
    final controller = _createController(_FailingDeleteRepository());
    addTearDown(controller.dispose);
    final transaction = Transaction(
      title: 'USD acquisition',
      category: 'Asset conversion',
      account: 'Cash -> USD',
      date: DateTime.utc(2026, 7, 24),
      amount: 16300000,
      type: TransactionType.assetConversion,
      quantity: 1000,
      unit: 'usd',
      unitPrice: 16300,
      assetAction: AssetAction.buy,
      marketReferenceUnitPrice: 16250,
      marketReferenceCurrencyCode: 'IDR',
      marketReferenceUnit: 'usd',
      marketReferenceSource: AssetMarketReferenceSource.cachedQuote,
      marketReferenceQuotedAt: DateTime.utc(2026, 7, 24, 8),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => TransactionDetailScreen.show(
              context,
              transaction: transaction,
              controller: controller,
            ),
            child: const Text('Open comparison'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open comparison'));
    await tester.pumpAndSettle();

    expect(find.text('Execution price'), findsOneWidget);
    expect(find.text('Reference price'), findsOneWidget);
    expect(find.textContaining('Paid above reference'), findsOneWidget);
    expect(find.textContaining('Saved price snapshot'), findsOneWidget);
  });

  testWidgets('delete failure keeps detail dialog open and displays error', (
    tester,
  ) async {
    final repository = _FailingDeleteRepository();
    final controller = _createController(repository);

    addTearDown(controller.dispose);

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
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    TransactionDetailScreen.show(
                      context,
                      transaction: transaction,
                      controller: controller,
                    );
                  },
                  child: const Text('Open detail'),
                ),
              ),
            );
          },
        ),
      ),
    );

    // Buka transaction detail terlebih dahulu.
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Baru klik tombol Delete pada detail.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Transaction detail tetap terbuka di belakang confirmation dialog.
    expect(find.byType(AlertDialog), findsNWidgets(2));

    expect(find.text('Delete transaction'), findsOneWidget);

    // Persistence baru dijalankan setelah konfirmasi kedua.
    await tester.tap(find.text('Delete transaction'));

    await tester.pumpAndSettle();

    expect(find.textContaining('database unavailable'), findsOneWidget);

    // Confirmation dialog sudah tertutup,
    // tetapi transaction detail tetap terbuka.
    expect(find.byType(AlertDialog), findsOneWidget);

    expect(find.text(transaction.title), findsOneWidget);

    expect(find.text('Delete'), findsOneWidget);

    expect(controller.error, contains('database unavailable'));
  });
}
