import 'package:flutter/foundation.dart';

import '../../../master_data/domain/entities/account.dart';
import '../../domain/entities/internal_transfer_link.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/services/internal_transfer_matcher.dart';
import '../../domain/usecases/internal_transfer_usecases.dart';

enum InternalTransferReviewFilter { all, strong, possible, ambiguous }

class InternalTransferReviewController extends ChangeNotifier {
  InternalTransferReviewController({
    required this.transactions,
    required this.accounts,
    required this.links,
    required this.service,
    this.matcher = const InternalTransferMatcher(),
    DateTime? now,
    this.afterMutation,
  }) : _now = now ?? DateTime.now() {
    useCurrentMonth();
  }

  final List<Transaction> transactions;
  final List<Account> accounts;
  final List<InternalTransferLink> links;
  final InternalTransferService service;
  final InternalTransferMatcher matcher;
  final Future<void> Function()? afterMutation;
  final DateTime _now;

  late DateTime from;
  late DateTime to;
  InternalTransferReviewFilter filter = InternalTransferReviewFilter.all;
  bool busy = false;
  String? error;
  final Set<String> _dismissed = {};
  Map<String, InternalTransferMatch> _matches = const {};

  List<InternalTransferMatch> get matches {
    final values = _matches.values.where((match) {
      if (_dismissed.contains(match.source.id)) return false;
      return switch (filter) {
        InternalTransferReviewFilter.all => true,
        InternalTransferReviewFilter.strong =>
          match.classification == InternalTransferMatchClassification.strong,
        InternalTransferReviewFilter.possible =>
          match.classification == InternalTransferMatchClassification.possible,
        InternalTransferReviewFilter.ambiguous =>
          match.classification == InternalTransferMatchClassification.ambiguous,
      };
    }).toList();
    values.sort((left, right) {
      final date = right.source.date.compareTo(left.source.date);
      return date != 0 ? date : left.source.id.compareTo(right.source.id);
    });
    return List.unmodifiable(values);
  }

  int count(InternalTransferMatchClassification classification) => _matches
      .values
      .where((match) => match.classification == classification)
      .length;

  void useCurrentMonth() {
    from = DateTime(_now.year, _now.month);
    to = DateTime(_now.year, _now.month + 1).subtract(const Duration(days: 1));
  }

  void usePreviousMonth() {
    from = DateTime(_now.year, _now.month - 1);
    to = DateTime(_now.year, _now.month).subtract(const Duration(days: 1));
    scan();
  }

  void useCustomRange(DateTime start, DateTime end) {
    from = DateTime(start.year, start.month, start.day);
    to = DateTime(end.year, end.month, end.day);
    scan();
  }

  void setFilter(InternalTransferReviewFilter value) {
    filter = value;
    notifyListeners();
  }

  Future<void> scan() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final paired = {
        for (final link in links.where((item) => item.isActive))
          ...link.transactionIds,
      };
      final accountByName = {
        for (final account in accounts.where((item) => item.deletedAt == null))
          account.name.trim().toLowerCase(): account,
      };
      InternalTransferCandidate? candidate(Transaction transaction) {
        final account = accountByName[transaction.account.trim().toLowerCase()];
        if (account == null) return null;
        return InternalTransferCandidate(
          id: transaction.id,
          bookId: transaction.bookId ?? '',
          accountId: account.id,
          accountName: account.name,
          currencyCode: account.currencyCode,
          date: transaction.date,
          type: transaction.type,
          amount: transaction.amount,
          description: transaction.title,
          source: InternalTransferCandidateSource.existing,
          version: transaction.version,
          deleted: transaction.deletedAt != null,
          alreadyPaired: paired.contains(transaction.id),
        );
      }

      final inRange = transactions.where((item) {
        final date = DateTime(item.date.year, item.date.month, item.date.day);
        return !date.isBefore(from) &&
            !date.isAfter(to) &&
            item.type == TransactionType.expense;
      });
      final sources = inRange
          .map(candidate)
          .whereType<InternalTransferCandidate>();
      final counterparts = transactions
          .map(candidate)
          .whereType<InternalTransferCandidate>();
      final raw = matcher.matchAll(
        sources: sources,
        counterparts: counterparts,
      );
      final usable = <String, InternalTransferMatch>{
        for (final entry in raw.entries)
          if (entry.value.classification !=
                  InternalTransferMatchClassification.notEligible &&
              entry.value.classification !=
                  InternalTransferMatchClassification.alreadyTransfer)
            entry.key: entry.value,
      };
      final selectedCounterparts = <String, int>{};
      for (final match in usable.values) {
        final id = match.counterpart?.id;
        if (id != null) {
          selectedCounterparts[id] = (selectedCounterparts[id] ?? 0) + 1;
        }
      }
      _matches = {
        for (final entry in usable.entries)
          entry.key:
              selectedCounterparts[entry.value.counterpart?.id] != null &&
                  selectedCounterparts[entry.value.counterpart?.id]! > 1
              ? InternalTransferMatch(
                  source: entry.value.source,
                  classification: InternalTransferMatchClassification.ambiguous,
                  options: entry.value.options,
                )
              : entry.value,
      };
    } catch (exception) {
      error = exception.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void dismiss(String sourceId) {
    _dismissed.add(sourceId);
    notifyListeners();
  }

  void chooseCounterpart(String sourceId, String counterpartId) {
    final current = _matches[sourceId];
    if (current == null) return;
    final option = current.options
        .where((item) => item.counterpart.id == counterpartId)
        .firstOrNull;
    if (option == null) return;
    _matches = {
      ..._matches,
      sourceId: InternalTransferMatch(
        source: current.source,
        counterpart: option.counterpart,
        classification: option.rank.sameDate
            ? InternalTransferMatchClassification.strong
            : InternalTransferMatchClassification.possible,
        options: [option, ...current.options.where((item) => item != option)],
      ),
    };
    notifyListeners();
  }

  Future<bool> confirm(InternalTransferMatch match) async {
    final counterpart = match.counterpart;
    if (counterpart == null) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final outgoing = match.source.type == TransactionType.expense
          ? match.source
          : counterpart;
      final incoming = match.source.type == TransactionType.income
          ? match.source
          : counterpart;
      await service.convertExisting(
        outgoingTransactionId: outgoing.id,
        incomingTransactionId: incoming.id,
        sourceAccountId: outgoing.accountId,
        destinationAccountId: incoming.accountId,
        expectedOutgoingVersion: outgoing.version,
        expectedIncomingVersion: incoming.version,
      );
      _dismissed.add(match.source.id);
      await afterMutation?.call();
      return true;
    } catch (_) {
      error = 'This transfer candidate changed. Review again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<Map<String, bool>> confirmAllUnambiguous() async {
    final results = <String, bool>{};
    final used = <String>{};
    for (final match in matches.where((item) => item.canConfirm)) {
      final counterpart = match.counterpart;
      if (counterpart == null ||
          !used.add(match.source.id) ||
          !used.add(counterpart.id)) {
        results[match.source.id] = false;
        continue;
      }
      results[match.source.id] = await confirm(match);
    }
    return results;
  }
}
