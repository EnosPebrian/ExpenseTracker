import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/screens/transaction_detail_screen.dart';

class _FailingDeleteRepository implements TransactionRepository {
  @override
  Future<List<Transaction>> getAll() async {
    return const [];
  }

  @override
  Future<void> save(Transaction transaction) async {}

  @override
  Future<void> softDelete(Transaction transaction) async {
    throw StateError('database unavailable');
  }
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
