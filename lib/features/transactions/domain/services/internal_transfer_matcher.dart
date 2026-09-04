import '../entities/transaction.dart';

enum InternalTransferCandidateSource { draft, existing }

enum InternalTransferMatchClassification {
  strong,
  possible,
  ambiguous,
  notEligible,
  alreadyTransfer,
}

/// Source-neutral, immutable input used by [InternalTransferMatcher].
class InternalTransferCandidate {
  const InternalTransferCandidate({
    required this.id,
    required this.bookId,
    required this.accountId,
    required this.accountName,
    required this.currencyCode,
    required this.date,
    required this.type,
    required this.amount,
    required this.description,
    this.reference = '',
    required this.source,
    this.version = 1,
    this.deleted = false,
    this.alreadyPaired = false,
  });

  final String id;
  final String bookId;
  final String accountId;
  final String accountName;
  final String currencyCode;
  final DateTime date;
  final TransactionType type;
  final int amount;
  final String description;
  final String reference;
  final InternalTransferCandidateSource source;
  final int version;
  final bool deleted;
  final bool alreadyPaired;

  bool get isOrdinary =>
      type == TransactionType.expense || type == TransactionType.income;
}

class InternalTransferRank {
  const InternalTransferRank({
    required this.sameDate,
    required this.referenceMatch,
    required this.accountHint,
    required this.keywordEvidence,
    required this.dayDifference,
  });

  final bool sameDate;
  final bool referenceMatch;
  final bool accountHint;
  final bool keywordEvidence;
  final int dayDifference;

  int compareQuality(InternalTransferRank other) {
    final left = [
      sameDate ? 1 : 0,
      referenceMatch ? 1 : 0,
      accountHint ? 1 : 0,
      keywordEvidence ? 1 : 0,
      -dayDifference,
    ];
    final right = [
      other.sameDate ? 1 : 0,
      other.referenceMatch ? 1 : 0,
      other.accountHint ? 1 : 0,
      other.keywordEvidence ? 1 : 0,
      -other.dayDifference,
    ];
    for (var index = 0; index < left.length; index++) {
      final result = left[index].compareTo(right[index]);
      if (result != 0) return result;
    }
    return 0;
  }
}

class InternalTransferMatchOption {
  const InternalTransferMatchOption({
    required this.counterpart,
    required this.rank,
    required this.reasons,
  });

  final InternalTransferCandidate counterpart;
  final InternalTransferRank rank;
  final List<String> reasons;
}

class InternalTransferMatch {
  const InternalTransferMatch({
    required this.source,
    required this.classification,
    this.counterpart,
    this.options = const [],
  });

  final InternalTransferCandidate source;
  final InternalTransferMatchClassification classification;
  final InternalTransferCandidate? counterpart;
  final List<InternalTransferMatchOption> options;

  List<String> get reasons =>
      options.isEmpty ? const [] : options.first.reasons;
  bool get canConfirm =>
      classification == InternalTransferMatchClassification.strong ||
      classification == InternalTransferMatchClassification.possible;
}

/// Pure deterministic matcher. Hard financial constraints are applied before
/// any supplementary text signals are ranked.
class InternalTransferMatcher {
  const InternalTransferMatcher({this.maximumDayDifference = 2});

  static const transferKeywords = <String>{
    'transfer',
    'trf',
    'xfer',
    'transfer to',
    'transfer from',
    'transfer ke',
    'transfer dari',
    'pemindahan',
  };

  final int maximumDayDifference;

  Map<String, InternalTransferMatch> matchAll({
    required Iterable<InternalTransferCandidate> sources,
    required Iterable<InternalTransferCandidate> counterparts,
  }) {
    final pool = _CandidatePool(counterparts);
    return {
      for (final source in sources) source.id: _match(source, pool: pool),
    };
  }

  InternalTransferMatch matchOne({
    required InternalTransferCandidate source,
    required Iterable<InternalTransferCandidate> counterparts,
  }) => _match(source, pool: _CandidatePool(counterparts));

  InternalTransferMatch _match(
    InternalTransferCandidate source, {
    required _CandidatePool pool,
  }) {
    if (source.alreadyPaired) {
      return InternalTransferMatch(
        source: source,
        classification: InternalTransferMatchClassification.alreadyTransfer,
      );
    }
    if (!_sourceEligible(source)) {
      return InternalTransferMatch(
        source: source,
        classification: InternalTransferMatchClassification.notEligible,
      );
    }
    final options = <InternalTransferMatchOption>[];
    for (final candidate in pool.candidatesFor(
      source,
      maximumDayDifference: maximumDayDifference,
    )) {
      if (!_pairEligible(source, candidate)) continue;
      options.add(_option(source, candidate));
    }
    options.sort((left, right) {
      final quality = right.rank.compareQuality(left.rank);
      if (quality != 0) return quality;
      return left.counterpart.id.compareTo(right.counterpart.id);
    });
    if (options.isEmpty) {
      return InternalTransferMatch(
        source: source,
        classification: InternalTransferMatchClassification.notEligible,
      );
    }
    final ambiguous =
        options.length > 1 &&
        options[0].rank.compareQuality(options[1].rank) == 0;
    if (ambiguous) {
      return InternalTransferMatch(
        source: source,
        classification: InternalTransferMatchClassification.ambiguous,
        options: List.unmodifiable(options),
      );
    }
    return InternalTransferMatch(
      source: source,
      counterpart: options.first.counterpart,
      classification: options.first.rank.sameDate
          ? InternalTransferMatchClassification.strong
          : InternalTransferMatchClassification.possible,
      options: List.unmodifiable(options),
    );
  }

  bool _sourceEligible(InternalTransferCandidate candidate) =>
      !candidate.deleted &&
      !candidate.alreadyPaired &&
      candidate.isOrdinary &&
      candidate.bookId.isNotEmpty &&
      candidate.accountId.isNotEmpty &&
      candidate.currencyCode.isNotEmpty &&
      candidate.amount > 0;

  bool _pairEligible(
    InternalTransferCandidate source,
    InternalTransferCandidate counterpart,
  ) =>
      _sourceEligible(counterpart) &&
      source.id != counterpart.id &&
      source.bookId == counterpart.bookId &&
      source.accountId != counterpart.accountId &&
      source.currencyCode.toUpperCase() ==
          counterpart.currencyCode.toUpperCase() &&
      source.amount == counterpart.amount &&
      source.type != counterpart.type &&
      _dayDifference(source.date, counterpart.date) <= maximumDayDifference;

  InternalTransferMatchOption _option(
    InternalTransferCandidate source,
    InternalTransferCandidate counterpart,
  ) {
    final difference = _dayDifference(source.date, counterpart.date);
    final sourceText = _normalized('${source.description} ${source.reference}');
    final counterpartText = _normalized(
      '${counterpart.description} ${counterpart.reference}',
    );
    final sourceReference = _normalized(source.reference);
    final counterpartReference = _normalized(counterpart.reference);
    final referenceMatch =
        sourceReference.isNotEmpty &&
        counterpartReference.isNotEmpty &&
        sourceReference == counterpartReference;
    final accountHint =
        _mentionsAccount(sourceText, counterpart.accountName) ||
        _mentionsAccount(counterpartText, source.accountName);
    final keyword = transferKeywords.any(
      (value) => sourceText.contains(value) || counterpartText.contains(value),
    );
    final reasons = <String>[
      'Same amount',
      'Same currency',
      'Opposite directions',
      'Different accounts',
      if (difference == 0)
        'Same date'
      else
        'Posting dates differ by $difference day${difference == 1 ? '' : 's'}',
      if (referenceMatch) 'Matching reference',
      if (accountHint) 'Description or reference mentions the other account',
      if (keyword) 'Transfer wording detected',
    ];
    return InternalTransferMatchOption(
      counterpart: counterpart,
      rank: InternalTransferRank(
        sameDate: difference == 0,
        referenceMatch: referenceMatch,
        accountHint: accountHint,
        keywordEvidence: keyword,
        dayDifference: difference,
      ),
      reasons: List.unmodifiable(reasons),
    );
  }

  static int _dayDifference(DateTime left, DateTime right) {
    final leftDate = DateTime(left.year, left.month, left.day);
    final rightDate = DateTime(right.year, right.month, right.day);
    return leftDate.difference(rightDate).inDays.abs();
  }

  static String _normalized(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_./,:;()]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _mentionsAccount(String text, String accountName) {
    final normalizedName = _normalized(accountName);
    if (normalizedName.length < 3) return false;
    if (text.contains(normalizedName)) return true;
    final meaningful = normalizedName
        .split(' ')
        .where((part) => part.length >= 3 && !RegExp(r'^\d+$').hasMatch(part))
        .toList();
    return meaningful.length >= 2 && meaningful.every(text.contains);
  }
}

class _CandidatePool {
  _CandidatePool(Iterable<InternalTransferCandidate> candidates) {
    for (final candidate in candidates) {
      final key = _key(
        candidate.currencyCode,
        candidate.amount,
        candidate.type,
        candidate.date,
      );
      (_index[key] ??= []).add(candidate);
    }
  }

  final Map<String, List<InternalTransferCandidate>> _index = {};

  Iterable<InternalTransferCandidate> candidatesFor(
    InternalTransferCandidate source, {
    required int maximumDayDifference,
  }) sync* {
    final opposite = source.type == TransactionType.expense
        ? TransactionType.income
        : TransactionType.expense;
    final localDate = DateTime(
      source.date.year,
      source.date.month,
      source.date.day,
    );
    for (
      var offset = -maximumDayDifference;
      offset <= maximumDayDifference;
      offset++
    ) {
      final date = localDate.add(Duration(days: offset));
      yield* _index[_key(source.currencyCode, source.amount, opposite, date)] ??
          const [];
    }
  }

  static String _key(
    String currency,
    int amount,
    TransactionType type,
    DateTime date,
  ) =>
      '${currency.toUpperCase()}|$amount|${type.name}|'
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
