import 'package:uuid/uuid.dart';

import '../../../master_data/domain/entities/account.dart';
import '../entities/internal_transfer_link.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';
import '../services/internal_transfer_integrity_validator.dart';

class CanonicalInternalTransfer {
  const CanonicalInternalTransfer({
    required this.link,
    required this.outgoing,
    required this.incoming,
  });

  final InternalTransferLink link;
  final Transaction outgoing;
  final Transaction incoming;
}

class InternalTransferService {
  InternalTransferService(
    this.repository, {
    this.validator = const InternalTransferIntegrityValidator(),
  });

  final InternalTransferRepository repository;
  final InternalTransferIntegrityValidator validator;

  static const _matcherLinkNamespace = '0f488122-6356-55c6-8981-dbc6168824fa';

  Future<List<InternalTransferLink>> getLinks({bool includeDeleted = false}) =>
      repository.getTransferLinks(includeDeleted: includeDeleted);

  Future<CanonicalInternalTransfer> create({
    required String bookId,
    required String? enteredByMemberId,
    required String title,
    required String sourceAccountId,
    required String destinationAccountId,
    required DateTime date,
    required int amount,
    String? outgoingTransactionId,
    String? incomingTransactionId,
    String? linkId,
    String deviceId = 'local-device',
  }) async {
    final accounts = await repository.getAllAccounts();
    final source = _account(accounts, sourceAccountId);
    final destination = _account(accounts, destinationAccountId);
    final now = DateTime.now();
    final outgoing = Transaction(
      id: outgoingTransactionId,
      bookId: bookId,
      enteredByMemberId: enteredByMemberId,
      title: title,
      category: 'Transfer',
      account: source.name,
      date: date,
      amount: amount,
      type: TransactionType.expense,
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
      syncStatus: 'pending',
    );
    final incoming = Transaction(
      id: incomingTransactionId,
      bookId: bookId,
      enteredByMemberId: enteredByMemberId,
      title: title,
      category: 'Transfer',
      account: destination.name,
      date: date,
      amount: amount,
      type: TransactionType.income,
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
      syncStatus: 'pending',
    );
    final link = InternalTransferLink(
      id: linkId,
      bookId: bookId,
      outgoingTransactionId: outgoing.id,
      incomingTransactionId: incoming.id,
      sourceAccountId: source.id,
      destinationAccountId: destination.id,
      currencyCode: source.currencyCode,
      amount: amount,
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
      syncStatus: 'pending',
    );
    await _validateAndSave(
      link: link,
      outgoing: outgoing,
      incoming: incoming,
      source: source,
      destination: destination,
      transactions: [outgoing, incoming],
    );
    return CanonicalInternalTransfer(
      link: link,
      outgoing: outgoing,
      incoming: incoming,
    );
  }

  Future<CanonicalInternalTransfer> createFromLegacyDraft(
    Transaction draft,
  ) async {
    final bookId = draft.bookId;
    if (bookId == null || bookId.isEmpty) {
      throw const InternalTransferValidationException(
        'A household is required for an internal transfer.',
      );
    }
    final route = draft.account.split('->').map((item) => item.trim()).toList();
    if (route.length != 2 || route.any((item) => item.isEmpty)) {
      throw const InternalTransferValidationException(
        'Choose a source and destination account.',
      );
    }
    final accounts = await repository.getAllAccounts();
    final source = _accountByName(accounts, bookId, route.first);
    final destination = _accountByName(accounts, bookId, route.last);
    return create(
      bookId: bookId,
      enteredByMemberId: draft.enteredByMemberId,
      title: draft.title,
      sourceAccountId: source.id,
      destinationAccountId: destination.id,
      date: draft.date,
      amount: draft.amount,
      outgoingTransactionId: draft.id,
      deviceId: draft.deviceId,
    );
  }

  Future<InternalTransferLink> convertExisting({
    required String outgoingTransactionId,
    required String incomingTransactionId,
    required String sourceAccountId,
    required String destinationAccountId,
    int? expectedOutgoingVersion,
    int? expectedIncomingVersion,
    String? linkId,
  }) async {
    final transactions = await repository.getAllTransactions();
    final accounts = await repository.getAllAccounts();
    final outgoing = _transaction(transactions, outgoingTransactionId);
    final incoming = _transaction(transactions, incomingTransactionId);
    if ((expectedOutgoingVersion != null &&
            outgoing.version != expectedOutgoingVersion) ||
        (expectedIncomingVersion != null &&
            incoming.version != expectedIncomingVersion)) {
      throw const InternalTransferValidationException(
        'A transaction changed before it could be paired. Reload and try again.',
      );
    }
    final source = _account(accounts, sourceAccountId);
    final destination = _account(accounts, destinationAccountId);
    final bookId = outgoing.bookId;
    if (bookId == null || bookId.isEmpty) {
      throw const InternalTransferValidationException(
        'Transfer legs must belong to a household.',
      );
    }
    final now = DateTime.now();
    final link = InternalTransferLink(
      id: linkId,
      bookId: bookId,
      outgoingTransactionId: outgoing.id,
      incomingTransactionId: incoming.id,
      sourceAccountId: source.id,
      destinationAccountId: destination.id,
      currencyCode: source.currencyCode,
      amount: outgoing.amount,
      createdAt: now,
      updatedAt: now,
      deviceId: outgoing.deviceId,
      syncStatus: 'pending',
    );
    await _validateAndSave(
      link: link,
      outgoing: outgoing,
      incoming: incoming,
      source: source,
      destination: destination,
      transactions: const [],
      expectedTransactionVersions: {
        outgoing.id: outgoing.version,
        incoming.id: incoming.version,
      },
    );
    return link;
  }

  Future<CanonicalInternalTransfer> convertDraftExisting({
    required Transaction draft,
    required String existingTransactionId,
    required int expectedExistingVersion,
    required String draftAccountId,
    required String existingAccountId,
  }) async {
    final transactions = await repository.getAllTransactions();
    final accounts = await repository.getAllAccounts();
    final existing = _transaction(transactions, existingTransactionId);
    if (existing.version != expectedExistingVersion) {
      throw const InternalTransferValidationException(
        'This transfer candidate changed. Review again.',
      );
    }
    final draftAccount = _account(accounts, draftAccountId);
    final existingAccount = _account(accounts, existingAccountId);
    final preparedDraft = draft.copyWith(
      categoryId: null,
      version: 1,
      updatedAt: draft.createdAt,
      syncStatus: 'pending',
    );
    final outgoing = preparedDraft.type == TransactionType.expense
        ? preparedDraft
        : existing;
    final incoming = preparedDraft.type == TransactionType.income
        ? preparedDraft
        : existing;
    final source = preparedDraft.type == TransactionType.expense
        ? draftAccount
        : existingAccount;
    final destination = preparedDraft.type == TransactionType.income
        ? draftAccount
        : existingAccount;
    final link = _matchedLink(
      outgoing: outgoing,
      incoming: incoming,
      source: source,
      destination: destination,
    );
    await _validateAndSave(
      link: link,
      outgoing: outgoing,
      incoming: incoming,
      source: source,
      destination: destination,
      transactions: [preparedDraft],
      expectedTransactionVersions: {existing.id: expectedExistingVersion},
      requireNewTransactionIds: {preparedDraft.id},
    );
    return CanonicalInternalTransfer(
      link: link,
      outgoing: outgoing,
      incoming: incoming,
    );
  }

  Future<CanonicalInternalTransfer> convertDraftPair({
    required Transaction first,
    required Transaction second,
    required String firstAccountId,
    required String secondAccountId,
  }) async {
    final accounts = await repository.getAllAccounts();
    final firstAccount = _account(accounts, firstAccountId);
    final secondAccount = _account(accounts, secondAccountId);
    final firstPrepared = first.copyWith(
      categoryId: null,
      version: 1,
      updatedAt: first.createdAt,
      syncStatus: 'pending',
    );
    final secondPrepared = second.copyWith(
      categoryId: null,
      version: 1,
      updatedAt: second.createdAt,
      syncStatus: 'pending',
    );
    final outgoing = firstPrepared.type == TransactionType.expense
        ? firstPrepared
        : secondPrepared;
    final incoming = firstPrepared.type == TransactionType.income
        ? firstPrepared
        : secondPrepared;
    final source = firstPrepared.type == TransactionType.expense
        ? firstAccount
        : secondAccount;
    final destination = firstPrepared.type == TransactionType.income
        ? firstAccount
        : secondAccount;
    final link = _matchedLink(
      outgoing: outgoing,
      incoming: incoming,
      source: source,
      destination: destination,
    );
    await _validateAndSave(
      link: link,
      outgoing: outgoing,
      incoming: incoming,
      source: source,
      destination: destination,
      transactions: [firstPrepared, secondPrepared],
      requireNewTransactionIds: {firstPrepared.id, secondPrepared.id},
    );
    return CanonicalInternalTransfer(
      link: link,
      outgoing: outgoing,
      incoming: incoming,
    );
  }

  InternalTransferLink _matchedLink({
    required Transaction outgoing,
    required Transaction incoming,
    required Account source,
    required Account destination,
  }) {
    final bookId = outgoing.bookId;
    if (bookId == null || bookId.isEmpty || incoming.bookId != bookId) {
      throw const InternalTransferValidationException(
        'Transfer legs must belong to the same household.',
      );
    }
    final now = DateTime.now();
    return InternalTransferLink(
      id: const Uuid().v5(
        _matcherLinkNamespace,
        '$bookId|${outgoing.id}|${incoming.id}',
      ),
      bookId: bookId,
      outgoingTransactionId: outgoing.id,
      incomingTransactionId: incoming.id,
      sourceAccountId: source.id,
      destinationAccountId: destination.id,
      currencyCode: source.currencyCode,
      amount: outgoing.amount,
      createdAt: now,
      updatedAt: now,
      deviceId: outgoing.deviceId,
      syncStatus: 'pending',
    );
  }

  Future<CanonicalInternalTransfer> edit({
    required String linkId,
    required int expectedLinkVersion,
    required int expectedOutgoingVersion,
    required int expectedIncomingVersion,
    required String title,
    required String sourceAccountId,
    required String destinationAccountId,
    required DateTime date,
    required int amount,
  }) async {
    final state = await _state(linkId, includeDeleted: false);
    if (state.link.version != expectedLinkVersion ||
        state.outgoing.version != expectedOutgoingVersion ||
        state.incoming.version != expectedIncomingVersion) {
      throw const InternalTransferValidationException(
        'The transfer changed on another device. Reload before editing.',
      );
    }
    final accounts = await repository.getAllAccounts();
    final source = _account(accounts, sourceAccountId);
    final destination = _account(accounts, destinationAccountId);
    final now = DateTime.now();
    final outgoing = state.outgoing.copyWith(
      title: title,
      category: 'Transfer',
      categoryId: null,
      account: source.name,
      date: date,
      amount: amount,
      type: TransactionType.expense,
      updatedAt: now,
      version: state.outgoing.version + 1,
      syncStatus: 'pending',
    );
    final incoming = state.incoming.copyWith(
      title: title,
      category: 'Transfer',
      categoryId: null,
      account: destination.name,
      date: date,
      amount: amount,
      type: TransactionType.income,
      updatedAt: now,
      version: state.incoming.version + 1,
      syncStatus: 'pending',
    );
    final link = state.link.copyWith(
      sourceAccountId: source.id,
      destinationAccountId: destination.id,
      currencyCode: source.currencyCode,
      amount: amount,
      updatedAt: now,
      version: state.link.version + 1,
      syncStatus: 'pending',
    );
    await _validateAndSave(
      link: link,
      outgoing: outgoing,
      incoming: incoming,
      source: source,
      destination: destination,
      transactions: [outgoing, incoming],
      replacedLinkId: link.id,
    );
    return CanonicalInternalTransfer(
      link: link,
      outgoing: outgoing,
      incoming: incoming,
    );
  }

  Future<void> unpair({
    required String linkId,
    required int expectedVersion,
  }) async {
    final state = await _state(linkId, includeDeleted: false);
    if (state.link.version != expectedVersion) {
      throw const InternalTransferValidationException(
        'The transfer changed on another device. Reload before unpairing.',
      );
    }
    final now = DateTime.now();
    await repository.saveInternalTransferAtomic(
      transactions: const [],
      link: state.link.copyWith(
        deletedAt: now,
        updatedAt: now,
        version: state.link.version + 1,
        syncStatus: 'pending',
      ),
    );
  }

  Future<void> delete({
    required String linkId,
    required int expectedLinkVersion,
    required int expectedOutgoingVersion,
    required int expectedIncomingVersion,
  }) async {
    final state = await _state(linkId, includeDeleted: false);
    if (state.link.version != expectedLinkVersion ||
        state.outgoing.version != expectedOutgoingVersion ||
        state.incoming.version != expectedIncomingVersion) {
      throw const InternalTransferValidationException(
        'The transfer changed on another device. Reload before deleting.',
      );
    }
    final now = DateTime.now();
    final outgoing = state.outgoing.copyWith(
      deletedAt: now,
      updatedAt: now,
      version: state.outgoing.version + 1,
      syncStatus: 'pending',
    );
    final incoming = state.incoming.copyWith(
      deletedAt: now,
      updatedAt: now,
      version: state.incoming.version + 1,
      syncStatus: 'pending',
    );
    final link = state.link.copyWith(
      deletedAt: now,
      updatedAt: now,
      version: state.link.version + 1,
      syncStatus: 'pending',
    );
    await repository.saveInternalTransferAtomic(
      transactions: [outgoing, incoming],
      link: link,
    );
  }

  Future<void> _validateAndSave({
    required InternalTransferLink link,
    required Transaction outgoing,
    required Transaction incoming,
    required Account source,
    required Account destination,
    required List<Transaction> transactions,
    String? replacedLinkId,
    Map<String, int> expectedTransactionVersions = const {},
    Set<String> requireNewTransactionIds = const {},
  }) async {
    validator.validate(
      link: link,
      outgoing: outgoing,
      incoming: incoming,
      sourceAccount: source,
      destinationAccount: destination,
      existingLinks: await repository.getTransferLinks(),
      replacedLinkId: replacedLinkId,
    );
    await repository.saveInternalTransferAtomic(
      transactions: transactions,
      link: link,
      expectedTransactionVersions: expectedTransactionVersions,
      requireNewTransactionIds: requireNewTransactionIds,
    );
  }

  Future<CanonicalInternalTransfer> _state(
    String linkId, {
    required bool includeDeleted,
  }) async {
    final links = await repository.getTransferLinks(
      includeDeleted: includeDeleted,
    );
    final link = links.where((item) => item.id == linkId).firstOrNull;
    if (link == null) {
      throw const InternalTransferValidationException(
        'The internal transfer no longer exists.',
      );
    }
    final transactions = await repository.getAllTransactions(
      includeDeleted: includeDeleted,
    );
    return CanonicalInternalTransfer(
      link: link,
      outgoing: _transaction(transactions, link.outgoingTransactionId),
      incoming: _transaction(transactions, link.incomingTransactionId),
    );
  }

  Account _account(List<Account> accounts, String id) {
    final account = accounts.where((item) => item.id == id).firstOrNull;
    if (account == null) {
      throw const InternalTransferValidationException(
        'A transfer account is missing or archived.',
      );
    }
    return account;
  }

  Account _accountByName(List<Account> accounts, String bookId, String name) {
    final normalized = name.trim().toLowerCase();
    final account = accounts
        .where(
          (item) =>
              item.bookId == bookId && item.name.toLowerCase() == normalized,
        )
        .firstOrNull;
    if (account == null) {
      throw const InternalTransferValidationException(
        'Choose an existing source and destination account.',
      );
    }
    return account;
  }

  Transaction _transaction(List<Transaction> transactions, String id) {
    final transaction = transactions.where((item) => item.id == id).firstOrNull;
    if (transaction == null) {
      throw const InternalTransferValidationException(
        'A transfer transaction leg is missing.',
      );
    }
    return transaction;
  }
}
