import '../../../master_data/domain/entities/account.dart';
import '../entities/internal_transfer_link.dart';
import '../entities/transaction.dart';

class InternalTransferValidationException implements Exception {
  const InternalTransferValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class InternalTransferIntegrityValidator {
  const InternalTransferIntegrityValidator();

  void validate({
    required InternalTransferLink link,
    required Transaction outgoing,
    required Transaction incoming,
    required Account sourceAccount,
    required Account destinationAccount,
    Iterable<InternalTransferLink> existingLinks = const [],
    String? replacedLinkId,
  }) {
    if (!link.isActive) return;
    if (link.outgoingTransactionId == link.incomingTransactionId ||
        outgoing.id == incoming.id) {
      throw const InternalTransferValidationException(
        'A transfer requires two different transaction legs.',
      );
    }
    if (outgoing.id != link.outgoingTransactionId ||
        incoming.id != link.incomingTransactionId) {
      throw const InternalTransferValidationException(
        'Transfer direction does not match its transaction legs.',
      );
    }
    if (outgoing.deletedAt != null || incoming.deletedAt != null) {
      throw const InternalTransferValidationException(
        'Deleted transactions cannot form an active transfer.',
      );
    }
    if (outgoing.bookId != link.bookId ||
        incoming.bookId != link.bookId ||
        sourceAccount.bookId != link.bookId ||
        destinationAccount.bookId != link.bookId) {
      throw const InternalTransferValidationException(
        'Transfer legs and accounts must belong to the same household.',
      );
    }
    if (sourceAccount.id == destinationAccount.id ||
        outgoing.account.trim().toLowerCase() ==
            incoming.account.trim().toLowerCase()) {
      throw const InternalTransferValidationException(
        'Choose two different accounts for an internal transfer.',
      );
    }
    if (link.sourceAccountId != sourceAccount.id ||
        link.destinationAccountId != destinationAccount.id ||
        outgoing.account.trim().toLowerCase() !=
            sourceAccount.name.trim().toLowerCase() ||
        incoming.account.trim().toLowerCase() !=
            destinationAccount.name.trim().toLowerCase()) {
      throw const InternalTransferValidationException(
        'Transfer account identity does not match its transaction legs.',
      );
    }
    if (sourceAccount.deletedAt != null ||
        destinationAccount.deletedAt != null) {
      throw const InternalTransferValidationException(
        'Archived accounts cannot form a new internal transfer.',
      );
    }
    if (sourceAccount.currencyCode != destinationAccount.currencyCode ||
        sourceAccount.currencyCode != link.currencyCode) {
      throw const InternalTransferValidationException(
        'Internal transfers require matching account currencies.',
      );
    }
    if (outgoing.type != TransactionType.expense ||
        incoming.type != TransactionType.income) {
      throw const InternalTransferValidationException(
        'A transfer requires one outgoing expense leg and one incoming income leg.',
      );
    }
    if (link.amount <= 0 ||
        outgoing.amount != link.amount ||
        incoming.amount != link.amount) {
      throw const InternalTransferValidationException(
        'Transfer legs must have the same positive amount.',
      );
    }
    for (final existing in existingLinks.where((item) => item.isActive)) {
      if (existing.id == replacedLinkId || existing.id == link.id) continue;
      if (existing.transactionIds
          .intersection(link.transactionIds)
          .isNotEmpty) {
        throw const InternalTransferValidationException(
          'A transaction already belongs to another active transfer.',
        );
      }
    }
  }
}
