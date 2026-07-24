import 'package:flutter/foundation.dart';

import '../../../assets/domain/services/asset_transaction_sequence_validator.dart';
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
  AssetSequenceValidationResult? assetValidation;

  Future<void> load({List<Transaction> seed = const []}) async {
    isLoading = true;
    error = null;
    assetValidation = null;
    notifyListeners();
    try {
      var loaded = await get();
      if (loaded.isEmpty && seed.isNotEmpty) {
        for (final transaction in seed) {
          await create(transaction);
        }
        loaded = await get();
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
      await create(transaction);
      await _refreshTransactions();
    });
  }

  Future<void> updateTransaction(Transaction transaction) async {
    await _run(() async {
      await update(transaction);
      await _refreshTransactions();
    });
  }

  Future<void> deleteTransaction(Transaction transaction) async {
    await _run(() async {
      await delete(transaction);
      await _refreshTransactions();
    });
  }

  Future<Transaction?> duplicateTransaction(
    Transaction transaction, {
    bool withoutAmount = false,
  }) async {
    Transaction? copy;
    await _run(() async {
      copy = await duplicate(transaction, withoutAmount: withoutAmount);

      await _refreshTransactions();
    });
    return copy;
  }

  void _sortTransactions() {
    transactions.sort(_compareTransactions);
  }

  Future<void> _refreshTransactions() async {
    transactions
      ..clear()
      ..addAll(await get());
    _sortTransactions();
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
    assetValidation = null;
    notifyListeners();

    try {
      await operation();
    } on TransactionValidationException catch (exception) {
      error = exception.toString();
      assetValidation = exception.assetValidation;
      rethrow;
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      notifyListeners();
    }
  }
}
