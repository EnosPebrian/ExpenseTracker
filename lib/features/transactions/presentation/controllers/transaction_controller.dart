import 'package:flutter/foundation.dart';

import '../../domain/entities/transaction.dart';
import '../../domain/usecases/transaction_usecases.dart';

class TransactionController extends ChangeNotifier {
  TransactionController({
    required this.create,
    required this.update,
    required this.delete,
    required this.get,
    required this.duplicate,
  });
  final CreateTransaction create;
  final UpdateTransaction update;
  final DeleteTransaction delete;
  final GetTransactions get;
  final DuplicateTransaction duplicate;

  final List<Transaction> transactions = [];
  bool isLoading = false;
  String? error;

  Future<void> load({List<Transaction> seed = const []}) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      var loaded = await get();
      if (loaded.isEmpty && seed.isNotEmpty) {
        loaded = [];
        for (final transaction in seed) {
          loaded.add(await create(transaction));
        }
      }
      transactions
        ..clear()
        ..addAll(loaded);

      _sortTransactions();
    } catch (exception) {
      error = exception.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createTransaction(Transaction transaction) async {
    await _run(() async {
      transactions.add(await create(transaction));

      _sortTransactions();
    });
  }

  Future<void> updateTransaction(Transaction transaction) async {
    await _run(() async {
      final updated = await update(transaction);

      final index = transactions.indexWhere((item) => item.id == updated.id);

      if (index >= 0) {
        transactions[index] = updated;
      } else {
        transactions.add(updated);
      }

      _sortTransactions();
    });
  }

  Future<void> deleteTransaction(Transaction transaction) async {
    await _run(() async {
      await delete(transaction);
      transactions.removeWhere((item) => item.id == transaction.id);
    });
  }

  Future<Transaction?> duplicateTransaction(
    Transaction transaction, {
    bool withoutAmount = false,
  }) async {
    Transaction? copy;
    await _run(() async {
      copy = await duplicate(transaction, withoutAmount: withoutAmount);

      transactions.add(copy!);
      _sortTransactions();
    });
    return copy;
  }

  void _sortTransactions() {
    transactions.sort(_compareTransactions);
  }

  static int _compareTransactions(Transaction left, Transaction right) {
    final dateComparison = right.date.compareTo(left.date);

    if (dateComparison != 0) {
      return dateComparison;
    }

    return right.createdAt.compareTo(left.createdAt);
  }

  Future<void> _run(Future<void> Function() operation) async {
    error = null;
    notifyListeners();

    try {
      await operation();
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      notifyListeners();
    }
  }
}
