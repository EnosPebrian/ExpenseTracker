import 'package:flutter/foundation.dart';

import '../../../assets/domain/services/asset_transaction_sequence_validator.dart';
import '../../domain/entities/internal_transfer_link.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/usecases/internal_transfer_usecases.dart';
import '../../domain/usecases/transaction_usecases.dart';

class TransactionController extends ChangeNotifier {
  TransactionController({
    required this.create,
    required this.update,
    required this.delete,
    required this.get,
    required this.duplicate,
    this.internalTransfers,
    this.afterMutation,
  });
  final CreateTransaction create;
  final UpdateTransaction update;
  final DeleteTransaction delete;
  final GetTransactions get;
  final DuplicateTransaction duplicate;
  final InternalTransferService? internalTransfers;
  final Future<void> Function()? afterMutation;

  final List<Transaction> transactions = [];
  final List<InternalTransferLink> transferLinks = [];
  bool isLoading = false;
  String? error;
  AssetSequenceValidationResult? assetValidation;
  String? activeBookId;
  String? activeMemberId;

  void setActiveContext({required String? bookId, required String? memberId}) {
    activeBookId = bookId;
    activeMemberId = memberId;
  }

  Future<void> load() async {
    isLoading = true;
    error = null;
    assetValidation = null;
    notifyListeners();
    try {
      final loaded = await get();
      transactions
        ..clear()
        ..addAll(loaded);
      await _refreshTransferLinks();

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
      final prepared = _withActiveContext(transaction);
      if (prepared.type == TransactionType.transfer &&
          internalTransfers != null) {
        await internalTransfers!.createFromLegacyDraft(prepared);
      } else {
        await create(prepared);
      }
      await _refreshTransactions();
    });
  }

  Future<void> updateTransaction(Transaction transaction) async {
    await _run(() async {
      final link = transferLinkForTransaction(transaction.id);
      if (transaction.type == TransactionType.transfer &&
          link != null &&
          internalTransfers != null) {
        final incoming = transactions.firstWhere(
          (item) => item.id == link.incomingTransactionId,
        );
        final route = transaction.account
            .split('->')
            .map((item) => item.trim())
            .toList();
        final accounts = await internalTransfers!.repository.getAllAccounts();
        final source = accounts.firstWhere(
          (item) => item.name.toLowerCase() == route.first.toLowerCase(),
        );
        final destination = accounts.firstWhere(
          (item) => item.name.toLowerCase() == route.last.toLowerCase(),
        );
        await internalTransfers!.edit(
          linkId: link.id,
          expectedLinkVersion: link.version,
          expectedOutgoingVersion: transaction.version,
          expectedIncomingVersion: incoming.version,
          title: transaction.title,
          sourceAccountId: source.id,
          destinationAccountId: destination.id,
          date: transaction.date,
          amount: transaction.amount,
        );
      } else {
        await update(transaction);
      }
      await _refreshTransactions();
    });
  }

  Future<void> deleteTransaction(Transaction transaction) async {
    await _run(() async {
      final link = transferLinkForTransaction(transaction.id);
      if (link != null && internalTransfers != null) {
        final outgoing = transactions.firstWhere(
          (item) => item.id == link.outgoingTransactionId,
        );
        final incoming = transactions.firstWhere(
          (item) => item.id == link.incomingTransactionId,
        );
        await internalTransfers!.delete(
          linkId: link.id,
          expectedLinkVersion: link.version,
          expectedOutgoingVersion: outgoing.version,
          expectedIncomingVersion: incoming.version,
        );
      } else {
        await delete(transaction);
      }
      await _refreshTransactions();
    });
  }

  Future<void> unpairTransaction(Transaction transaction) async {
    final link = transferLinkForTransaction(transaction.id);
    if (link == null || internalTransfers == null) return;
    await _run(() async {
      await internalTransfers!.unpair(
        linkId: link.id,
        expectedVersion: link.version,
      );
      await _refreshTransactions();
    });
  }

  Future<Transaction?> duplicateTransaction(
    Transaction transaction, {
    bool withoutAmount = false,
  }) async {
    Transaction? copy;
    await _run(() async {
      final link = transferLinkForTransaction(transaction.id);
      if (link != null && internalTransfers != null) {
        final draft = Transaction(
          bookId: activeBookId ?? transaction.bookId,
          enteredByMemberId: activeMemberId,
          title: transaction.title,
          category: 'Transfer',
          account: transaction.account,
          date: DateTime.now(),
          amount: withoutAmount ? 0 : transaction.amount,
          type: TransactionType.transfer,
        );
        final created = await internalTransfers!.createFromLegacyDraft(draft);
        copy = _displayTransfer(
          created.link,
          created.outgoing,
          created.incoming,
        );
      } else {
        copy = await duplicate(
          transaction.copyWith(
            bookId: activeBookId ?? transaction.bookId,
            enteredByMemberId: activeMemberId,
          ),
          withoutAmount: withoutAmount,
        );
      }

      await _refreshTransactions();
    });
    return copy;
  }

  Transaction _withActiveContext(Transaction transaction) {
    return transaction.copyWith(
      bookId: transaction.bookId ?? activeBookId,
      enteredByMemberId: transaction.enteredByMemberId ?? activeMemberId,
    );
  }

  void _sortTransactions() {
    transactions.sort(_compareTransactions);
  }

  Future<void> _refreshTransactions() async {
    transactions
      ..clear()
      ..addAll(await get());
    await _refreshTransferLinks();
    _sortTransactions();
  }

  Future<void> _refreshTransferLinks() async {
    transferLinks
      ..clear()
      ..addAll(await internalTransfers?.getLinks() ?? const []);
  }

  InternalTransferLink? transferLinkForTransaction(String transactionId) {
    for (final link in transferLinks) {
      if (link.transactionIds.contains(transactionId)) return link;
    }
    return null;
  }

  Transaction? transactionById(String transactionId) {
    for (final transaction in transactions) {
      if (transaction.id == transactionId) return transaction;
    }
    return null;
  }

  Set<String> get pairedTransactionIds => {
    for (final link in transferLinks) ...link.transactionIds,
  };

  List<Transaction> get displayTransactions {
    if (transferLinks.isEmpty) return List.unmodifiable(transactions);
    final linksByOutgoing = {
      for (final link in transferLinks) link.outgoingTransactionId: link,
    };
    final incomingIds = {
      for (final link in transferLinks) link.incomingTransactionId,
    };
    final byId = {for (final item in transactions) item.id: item};
    final result = <Transaction>[];
    for (final transaction in transactions) {
      if (incomingIds.contains(transaction.id)) continue;
      final link = linksByOutgoing[transaction.id];
      if (link == null) {
        result.add(transaction);
        continue;
      }
      final incoming = byId[link.incomingTransactionId];
      if (incoming != null) {
        result.add(_displayTransfer(link, transaction, incoming));
      }
    }
    result.sort(_compareTransactions);
    return List.unmodifiable(result);
  }

  Transaction _displayTransfer(
    InternalTransferLink link,
    Transaction outgoing,
    Transaction incoming,
  ) => outgoing.copyWith(
    category: 'Transfer',
    account: '${outgoing.account} -> ${incoming.account}',
    amount: link.amount,
    type: TransactionType.transfer,
  );

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
      await afterMutation?.call();
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
