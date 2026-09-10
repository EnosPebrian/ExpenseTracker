import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../assets/domain/entities/asset_definition.dart';
import '../../../assets/domain/entities/asset_kind.dart';
import '../../../assets/domain/services/asset_portfolio_calculator.dart';
import '../../../assets/domain/services/asset_trade_validator.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/internal_transfer_link.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../../../transactions/domain/import/csv_value_parsers.dart';
import '../../../transactions/domain/import/transaction_import_models.dart';
import '../../../transactions/domain/services/transaction_duplicate_detector.dart';
import 'brokerage_import_identity.dart';
import 'brokerage_import_models.dart';
import 'brokerage_import_posting.dart';

class BrokerageImportPlanner {
  const BrokerageImportPlanner({
    this.dateParser = const CsvTransactionDateParser(),
    this.moneyParser = const CsvMoneyParser(),
    this.duplicateDetector = const TransactionDuplicateDetector(),
    this.tradeValidator = const AssetTradeValidator(),
  });

  final CsvTransactionDateParser dateParser;
  final CsvMoneyParser moneyParser;
  final TransactionDuplicateDetector duplicateDetector;
  final AssetTradeValidator tradeValidator;

  Future<BrokerageImportPreview> build({
    required CsvParsedSource source,
    required BrokerageStatementMapping mapping,
    required Account brokerageAccount,
    required String activeBookId,
    required Iterable<AssetDefinition> instruments,
    required Iterable<Transaction> existingTransactions,
    required Iterable<InternalTransferLink> existingTransferLinks,
    Account? counterpartyAccount,
    bool remoteFreshnessVerified = true,
  }) async {
    mapping.validate();
    _validateAccounts(activeBookId, brokerageAccount, counterpartyAccount);
    final activeInstruments = instruments
        .where(
          (instrument) =>
              !instrument.isDeleted && instrument.bookId == activeBookId,
        )
        .toList(growable: false);
    final transactions = existingTransactions.toList(growable: false);
    final links = existingTransferLinks.toList(growable: false);
    final existingIndex = _BrokerageExistingTransactionIndex(transactions);
    final existingLinkIds = links.map((link) => link.id).toSet();
    final drafts = <BrokerageImportDraft>[];
    for (final row in source.rows) {
      drafts.add(
        await _buildRow(
          source: source,
          row: row,
          mapping: mapping,
          brokerageAccount: brokerageAccount,
          activeBookId: activeBookId,
          instruments: activeInstruments,
          existingTransactions: transactions,
          existingIndex: existingIndex,
          existingTransferLinkIds: existingLinkIds,
          counterpartyAccount: counterpartyAccount,
        ),
      );
    }
    final ordered = List<int>.generate(drafts.length, (index) => index)
      ..sort((left, right) {
        final byDate = drafts[left].date.compareTo(drafts[right].date);
        return byDate != 0
            ? byDate
            : drafts[left].sourceRowNumber.compareTo(
                drafts[right].sourceRowNumber,
              );
      });
    final analysisTransactions = transactions.toList(growable: true);
    final analysisIndex = _BrokerageExistingTransactionIndex(transactions);
    for (final index in ordered) {
      final finalized = _finish(
        drafts[index],
        activeBookId: activeBookId,
        brokerageAccount: brokerageAccount,
        counterpartyAccount: counterpartyAccount,
        instruments: activeInstruments,
        existingTransactions: analysisTransactions,
        existingIndex: analysisIndex,
        existingTransferLinkIds: existingLinkIds,
      );
      drafts[index] = finalized;
      if (!finalized.canCommit) continue;
      final instrument = finalized.instrumentId == null
          ? null
          : activeInstruments.cast<AssetDefinition?>().firstWhere(
              (candidate) => candidate?.id == finalized.instrumentId,
              orElse: () => finalized.plannedInstrument,
            );
      final plannedTransactions = BrokerageImportPosting.materialize(
        draft: finalized,
        bookId: activeBookId,
        memberId: null,
        brokerageAccount: brokerageAccount,
        counterpartyAccount: counterpartyAccount,
        instrument: instrument,
      ).transactions;
      analysisTransactions.addAll(plannedTransactions);
      analysisIndex.addAll(plannedTransactions);
    }
    return BrokerageImportPreview(
      source: source,
      drafts: List.unmodifiable(drafts),
      remoteFreshnessVerified: remoteFreshnessVerified,
    );
  }

  BrokerageImportDraft resolveActivity({
    required BrokerageImportDraft draft,
    required BrokerageActivityType activityType,
    required String activeBookId,
    required Account brokerageAccount,
    required Iterable<Transaction> existingTransactions,
    required Iterable<InternalTransferLink> existingTransferLinks,
    required Iterable<AssetDefinition> instruments,
    Account? counterpartyAccount,
  }) {
    final transactions = existingTransactions.toList(growable: false);
    return _finish(
      draft.copyWith(activityType: activityType),
      activeBookId: activeBookId,
      brokerageAccount: brokerageAccount,
      counterpartyAccount: counterpartyAccount,
      instruments: instruments,
      existingTransactions: transactions,
      existingIndex: _BrokerageExistingTransactionIndex(transactions),
      existingTransferLinkIds: existingTransferLinks
          .map((link) => link.id)
          .toSet(),
    );
  }

  BrokerageImportDraft mapInstrument({
    required BrokerageImportDraft draft,
    required AssetDefinition instrument,
    required String activeBookId,
    required Account brokerageAccount,
    required Iterable<Transaction> existingTransactions,
    required Iterable<InternalTransferLink> existingTransferLinks,
    required Iterable<AssetDefinition> instruments,
    Account? counterpartyAccount,
  }) {
    final transactions = existingTransactions.toList(growable: false);
    return _finish(
      draft.copyWith(
        instrumentResolution: BrokerageInstrumentResolution.mapped,
        instrumentId: instrument.id,
        plannedInstrument: instrument,
      ),
      activeBookId: activeBookId,
      brokerageAccount: brokerageAccount,
      counterpartyAccount: counterpartyAccount,
      instruments: instruments,
      existingTransactions: transactions,
      existingIndex: _BrokerageExistingTransactionIndex(transactions),
      existingTransferLinkIds: existingTransferLinks
          .map((link) => link.id)
          .toSet(),
    );
  }

  BrokerageImportDraft createInstrument({
    required BrokerageImportDraft draft,
    required String activeBookId,
    required Account brokerageAccount,
    required Iterable<Transaction> existingTransactions,
    required Iterable<InternalTransferLink> existingTransferLinks,
    required Iterable<AssetDefinition> instruments,
    Account? counterpartyAccount,
  }) {
    final symbol = draft.sourceInstrument.trim().toUpperCase();
    if (symbol.isEmpty) {
      throw StateError('An instrument symbol is required.');
    }
    final now = DateTime.now();
    final instrument = AssetDefinition(
      id: BrokerageImportIdentity.instrument(
        bookId: activeBookId,
        symbol: symbol,
        currencyCode: draft.currencyCode,
      ),
      bookId: activeBookId,
      displayName: symbol,
      kind: AssetKind.stock,
      symbol: symbol,
      providerCode: null,
      providerSymbol: null,
      exchangeCode: null,
      currencyCode: draft.currencyCode,
      unit: 'share',
      lotSize: 1,
      onlinePricingEnabled: false,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: 'local-device',
      syncStatus: 'pending',
    );
    final transactions = existingTransactions.toList(growable: false);
    return _finish(
      draft.copyWith(
        instrumentResolution: BrokerageInstrumentResolution.create,
        instrumentId: instrument.id,
        plannedInstrument: instrument,
      ),
      activeBookId: activeBookId,
      brokerageAccount: brokerageAccount,
      counterpartyAccount: counterpartyAccount,
      instruments: [...instruments, instrument],
      existingTransactions: transactions,
      existingIndex: _BrokerageExistingTransactionIndex(transactions),
      existingTransferLinkIds: existingTransferLinks
          .map((link) => link.id)
          .toSet(),
    );
  }

  Future<BrokerageImportDraft> _buildRow({
    required CsvParsedSource source,
    required CsvSourceRow row,
    required BrokerageStatementMapping mapping,
    required Account brokerageAccount,
    required String activeBookId,
    required List<AssetDefinition> instruments,
    required List<Transaction> existingTransactions,
    required _BrokerageExistingTransactionIndex existingIndex,
    required Set<String> existingTransferLinkIds,
    required Account? counterpartyAccount,
  }) async {
    String at(int index) => row.values[index];
    String optional(int? index) =>
        index == null || index >= row.values.length ? '' : row.values[index];
    final rawIdentity = jsonEncode({
      'row': row.identityKey ?? row.rowNumber,
      'date': at(mapping.dateColumn),
      'activity': at(mapping.activityColumn),
      'instrument': at(mapping.instrumentColumn),
      'quantity': optional(mapping.quantityColumn),
      'execution_price': optional(mapping.executionPriceColumn),
      'gross_amount': at(mapping.grossAmountColumn),
      'fee': optional(mapping.feeColumn),
      'tax': optional(mapping.taxColumn),
      'currency': optional(mapping.currencyColumn),
      'reference': optional(mapping.referenceColumn),
      'note': optional(mapping.noteColumn),
      'realized_pnl': optional(mapping.realizedPnlColumn),
      'split_numerator': optional(mapping.splitNumeratorColumn),
      'split_denominator': optional(mapping.splitDenominatorColumn),
    });
    final rowFingerprint = await _sha256(utf8.encode(rawIdentity));
    final sourceRowIdentity = (row.identityKey ?? row.rowNumber).toString();
    final eventId = BrokerageImportIdentity.event(
      bookId: activeBookId,
      brokerageAccountId: brokerageAccount.id,
      sourceFingerprint: source.fileFingerprint,
      sourceRowIdentity: sourceRowIdentity,
      sourceRowFingerprint: rowFingerprint,
    );
    final parseIssues = <BrokerageImportIssue>[];
    var date = DateTime(1970);
    final rawActivity = at(mapping.activityColumn).trim();
    final activity = _activity(rawActivity);
    final sourceInstrument = at(mapping.instrumentColumn).trim();
    final currency = optional(mapping.currencyColumn).trim().toUpperCase();
    final effectiveCurrency = currency.isEmpty
        ? brokerageAccount.currencyCode
        : currency;
    var quantity = _decimal(optional(mapping.quantityColumn), parseIssues);
    int? executionPrice = _optionalMoney(
      optional(mapping.executionPriceColumn),
      effectiveCurrency,
      mapping,
      parseIssues,
    );
    var gross = _money(
      at(mapping.grossAmountColumn),
      effectiveCurrency,
      mapping,
      parseIssues,
    );
    var fee = _money(
      optional(mapping.feeColumn),
      effectiveCurrency,
      mapping,
      parseIssues,
    );
    var tax = _money(
      optional(mapping.taxColumn),
      effectiveCurrency,
      mapping,
      parseIssues,
    );
    final brokerPnl = _optionalMoney(
      optional(mapping.realizedPnlColumn),
      effectiveCurrency,
      mapping,
      parseIssues,
      signed: true,
    );
    final numerator = _integer(
      optional(mapping.splitNumeratorColumn),
      parseIssues,
    );
    final denominator = _integer(
      optional(mapping.splitDenominatorColumn),
      parseIssues,
    );
    try {
      date = dateParser.parse(at(mapping.dateColumn), mapping.dateFormat);
    } on Object catch (error) {
      parseIssues.add(BrokerageImportIssue('CSV: $error', blocking: true));
    }
    if (activity == BrokerageActivityType.fee && gross == 0 && fee > 0) {
      gross = fee;
      fee = 0;
    }
    if (activity == BrokerageActivityType.tax && gross == 0 && tax > 0) {
      gross = tax;
      tax = 0;
    }
    if (activity == BrokerageActivityType.split) {
      gross = 0;
      fee = 0;
      tax = 0;
      quantity = null;
      executionPrice = null;
    }
    final exactMatches = instruments
        .where(
          (instrument) =>
              instrument.normalizedSymbol == sourceInstrument.toUpperCase() &&
              instrument.normalizedCurrencyCode == effectiveCurrency,
        )
        .toList(growable: false);
    final matchedInstrument = exactMatches.length == 1
        ? exactMatches.single
        : null;
    return _finish(
      BrokerageImportDraft(
        sourceRowNumber: row.rowNumber,
        sourceRowIdentity: sourceRowIdentity,
        sourceRowFingerprint: rowFingerprint,
        eventId: eventId,
        date: date,
        rawActivity: rawActivity,
        activityType: activity,
        sourceInstrument: sourceInstrument,
        currencyCode: effectiveCurrency,
        quantity: quantity,
        executionPrice: executionPrice,
        grossAmount: gross.abs(),
        feeAmount: fee.abs(),
        taxAmount: tax.abs(),
        splitNumerator: numerator,
        splitDenominator: denominator,
        reference: optional(mapping.referenceColumn).trim(),
        note: optional(mapping.noteColumn).trim(),
        brokerRealizedPnl: brokerPnl,
        instrumentResolution: matchedInstrument == null
            ? sourceInstrument.isEmpty
                  ? BrokerageInstrumentResolution.notRequired
                  : BrokerageInstrumentResolution.unresolved
            : BrokerageInstrumentResolution.mapped,
        instrumentId: matchedInstrument?.id,
        plannedInstrument: matchedInstrument,
        classification: BrokerageImportClassification.newRecord,
        included: true,
        issues: parseIssues,
      ),
      activeBookId: activeBookId,
      brokerageAccount: brokerageAccount,
      counterpartyAccount: counterpartyAccount,
      instruments: instruments,
      existingTransactions: existingTransactions,
      existingIndex: existingIndex,
      existingTransferLinkIds: existingTransferLinkIds,
    );
  }

  BrokerageImportDraft _finish(
    BrokerageImportDraft draft, {
    required String activeBookId,
    required Account brokerageAccount,
    required Account? counterpartyAccount,
    required Iterable<AssetDefinition> instruments,
    required Iterable<Transaction> existingTransactions,
    required _BrokerageExistingTransactionIndex existingIndex,
    required Set<String> existingTransferLinkIds,
  }) {
    final issues = draft.issues
        .where((issue) => issue.message.startsWith('CSV:'))
        .toList();
    final activity = draft.activityType;
    if (activity == null) {
      issues.add(
        BrokerageImportIssue(
          'Unknown activity “${draft.rawActivity}”. Choose an activity.',
          blocking: true,
        ),
      );
    }
    if (draft.currencyCode != brokerageAccount.currencyCode) {
      issues.add(
        const BrokerageImportIssue(
          'Statement currency must match the brokerage account currency.',
          blocking: true,
        ),
      );
    }
    if (activity != BrokerageActivityType.split && draft.grossAmount <= 0) {
      issues.add(
        const BrokerageImportIssue(
          'A positive gross amount is required.',
          blocking: true,
        ),
      );
    }
    if (activity == BrokerageActivityType.buy ||
        activity == BrokerageActivityType.sell) {
      if ((draft.quantity ?? 0) <= 0 || (draft.executionPrice ?? 0) <= 0) {
        issues.add(
          const BrokerageImportIssue(
            'Trades require positive quantity and execution price.',
            blocking: true,
          ),
        );
      }
    }
    if (activity == BrokerageActivityType.split &&
        ((draft.splitNumerator ?? 0) <= 0 ||
            (draft.splitDenominator ?? 0) <= 0)) {
      issues.add(
        const BrokerageImportIssue(
          'A split requires positive numerator and denominator columns.',
          blocking: true,
        ),
      );
    }
    if (draft.needsInstrumentResolution) {
      issues.add(
        BrokerageImportIssue(
          draft.sourceInstrument.isEmpty
              ? 'Choose an instrument before importing this activity.'
              : 'Unknown instrument “${draft.sourceInstrument}”. Map it or create it explicitly.',
          blocking: true,
        ),
      );
    }
    final instrument = draft.instrumentId == null
        ? null
        : instruments.cast<AssetDefinition?>().firstWhere(
            (candidate) => candidate?.id == draft.instrumentId,
            orElse: () => draft.plannedInstrument,
          );
    if (instrument != null &&
        (instrument.bookId != activeBookId ||
            instrument.isDeleted ||
            instrument.normalizedCurrencyCode !=
                brokerageAccount.currencyCode)) {
      issues.add(
        const BrokerageImportIssue(
          'The selected instrument is not compatible with this brokerage account.',
          blocking: true,
        ),
      );
    }
    if ((activity == BrokerageActivityType.deposit ||
            activity == BrokerageActivityType.withdrawal) &&
        (counterpartyAccount == null ||
            counterpartyAccount.id == brokerageAccount.id ||
            counterpartyAccount.bookId != activeBookId ||
            counterpartyAccount.deletedAt != null ||
            counterpartyAccount.currencyCode !=
                brokerageAccount.currencyCode)) {
      issues.add(
        const BrokerageImportIssue(
          'Choose another active same-currency account for funding.',
          blocking: true,
        ),
      );
    }

    var candidate = draft.copyWith(issues: issues);
    var classification = issues.any((issue) => issue.blocking)
        ? BrokerageImportClassification.invalid
        : BrokerageImportClassification.newRecord;
    String? matchedId;
    if (classification != BrokerageImportClassification.invalid) {
      final posting = BrokerageImportPosting.materialize(
        draft: candidate,
        bookId: activeBookId,
        memberId: null,
        brokerageAccount: brokerageAccount,
        counterpartyAccount: counterpartyAccount,
        instrument: instrument,
      );
      final matchingTransactions = posting.transactionIds
          .where(existingIndex.containsId)
          .length;
      final expectedLinkId = posting.transferLink?.id;
      final linkExists =
          expectedLinkId != null &&
          existingTransferLinkIds.contains(expectedLinkId);
      final allTransactionsExist =
          matchingTransactions == posting.transactionIds.length;
      if (allTransactionsExist && (expectedLinkId == null || linkExists)) {
        classification = BrokerageImportClassification.alreadyImported;
        candidate = candidate.copyWith(included: false);
      } else if (matchingTransactions > 0 || linkExists) {
        classification = BrokerageImportClassification.invalid;
        issues.add(
          const BrokerageImportIssue(
            'Only part of this statement event already exists. Review local data before importing.',
            blocking: true,
          ),
        );
      } else {
        final primary = posting.transactions.firstWhere(
          (transaction) => transaction.brokerageAccountId != null,
          orElse: () => posting.transactions.first,
        );
        final duplicate = duplicateDetector.classify(
          primary.toRecord(),
          existingIndex.candidatesFor(primary),
        );
        matchedId = duplicate.existingId;
        classification = switch (duplicate.classification) {
          TransactionCandidateClassification.exactIdentity =>
            BrokerageImportClassification.alreadyImported,
          TransactionCandidateClassification.semanticDuplicate =>
            BrokerageImportClassification.semanticDuplicate,
          TransactionCandidateClassification.possibleDuplicate =>
            BrokerageImportClassification.possibleDuplicate,
          TransactionCandidateClassification.newRecord =>
            BrokerageImportClassification.newRecord,
        };
        if (classification != BrokerageImportClassification.newRecord) {
          candidate = candidate.copyWith(included: false);
        }
        if (activity == BrokerageActivityType.buy ||
            activity == BrokerageActivityType.sell ||
            activity == BrokerageActivityType.split) {
          final validation = tradeValidator.validateCandidate(
            existingTransactions: existingTransactions.toList(),
            candidate: primary,
            definition: instrument,
            replacedTransactionId: null,
          );
          if (!validation.isValid) {
            classification = BrokerageImportClassification.invalid;
            issues.add(
              BrokerageImportIssue(
                validation.message ?? 'The asset sequence is invalid.',
                blocking: true,
              ),
            );
          }
        }
        if (activity == BrokerageActivityType.sell &&
            draft.brokerRealizedPnl != null &&
            instrument != null) {
          final before = AssetPortfolioCalculator.calculate(
            transactions: existingTransactions,
            assetDefinitions: instruments,
            brokerageAccountId: brokerageAccount.id,
          ).totalRealizedGain;
          final after = AssetPortfolioCalculator.calculate(
            transactions: [...existingTransactions, primary],
            assetDefinitions: instruments,
            brokerageAccountId: brokerageAccount.id,
          ).totalRealizedGain;
          final pilgrimPnl = after - before - draft.taxAmount;
          if (pilgrimPnl != draft.brokerRealizedPnl) {
            issues.add(
              BrokerageImportIssue(
                'Broker P&L ${draft.brokerRealizedPnl} differs from Pilgrim weighted-average P&L $pilgrimPnl.',
              ),
            );
          }
        }
      }
    }
    return candidate.copyWith(
      classification: classification,
      issues: List.unmodifiable(issues),
      matchedTransactionId: matchedId,
      clearMatchedTransactionId: matchedId == null,
    );
  }

  static BrokerageActivityType? _activity(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final activity in BrokerageActivityType.values) {
      if (activity.name == normalized) return activity;
    }
    return null;
  }

  double? _decimal(String raw, List<BrokerageImportIssue> issues) {
    if (raw.trim().isEmpty) return null;
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite) {
      issues.add(
        const BrokerageImportIssue('CSV: Quantity is invalid.', blocking: true),
      );
      return null;
    }
    return value.abs();
  }

  int? _integer(String raw, List<BrokerageImportIssue> issues) {
    if (raw.trim().isEmpty) return null;
    final value = int.tryParse(raw.trim());
    if (value == null) {
      issues.add(
        const BrokerageImportIssue(
          'CSV: Split ratio is invalid.',
          blocking: true,
        ),
      );
    }
    return value;
  }

  int _money(
    String raw,
    String currency,
    BrokerageStatementMapping mapping,
    List<BrokerageImportIssue> issues, {
    bool signed = false,
  }) {
    if (raw.trim().isEmpty) return 0;
    try {
      final value = moneyParser.parse(
        raw,
        currencyCode: currency,
        decimalSeparator: mapping.decimalSeparator,
        thousandsSeparator: mapping.thousandsSeparator,
        stripCurrencySymbols: mapping.stripCurrencySymbols,
        allowZero: true,
      );
      return signed ? value : value.abs();
    } on Object catch (error) {
      issues.add(BrokerageImportIssue('CSV: $error', blocking: true));
      return 0;
    }
  }

  int? _optionalMoney(
    String raw,
    String currency,
    BrokerageStatementMapping mapping,
    List<BrokerageImportIssue> issues, {
    bool signed = false,
  }) => raw.trim().isEmpty
      ? null
      : _money(raw, currency, mapping, issues, signed: signed);

  static void _validateAccounts(
    String activeBookId,
    Account brokerage,
    Account? counterparty,
  ) {
    if (brokerage.bookId != activeBookId ||
        brokerage.deletedAt != null ||
        brokerage.accountType != AccountType.brokerage) {
      throw const TransactionImportException(
        'Choose an active brokerage account in this household.',
      );
    }
    if (counterparty != null &&
        (counterparty.bookId != activeBookId ||
            counterparty.deletedAt != null ||
            counterparty.id == brokerage.id)) {
      throw const TransactionImportException(
        'Choose another active funding account in this household.',
      );
    }
  }

  static Future<String> _sha256(List<int> bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class _BrokerageExistingTransactionIndex {
  _BrokerageExistingTransactionIndex(Iterable<Transaction> transactions) {
    addAll(transactions);
  }

  final Map<String, Transaction> _byId = {};
  final Map<String, List<Transaction>> _bySemanticKey = {};

  bool containsId(String id) => _byId.containsKey(id);

  Iterable<Map<String, Object?>> candidatesFor(Transaction candidate) sync* {
    final seen = <String>{};
    final exact = _byId[candidate.id];
    if (exact != null && seen.add(exact.id)) yield exact.toRecord();
    for (final transaction in _bySemanticKey[_key(candidate)] ?? const []) {
      if (seen.add(transaction.id)) yield transaction.toRecord();
    }
  }

  void addAll(Iterable<Transaction> transactions) {
    for (final transaction in transactions) {
      _byId[transaction.id] = transaction;
      _bySemanticKey.putIfAbsent(_key(transaction), () => []).add(transaction);
    }
  }

  static String _key(Transaction transaction) =>
      '${transaction.type.name}|${transaction.amount}|'
      '${transaction.account.trim().toLowerCase()}';
}

BrokerageStatementMapping? canonicalBrokerageMappingFor(List<String> headers) {
  final normalized = headers
      .map((header) => header.trim().toLowerCase())
      .toList();
  int? index(String name) {
    final found = normalized.indexOf(name);
    return found < 0 ? null : found;
  }

  final date = index('date');
  final activity = index('activity');
  final instrument = index('symbol') ?? index('instrument');
  final gross = index('gross_amount') ?? index('amount');
  if (date == null || activity == null || instrument == null || gross == null) {
    return null;
  }
  return BrokerageStatementMapping(
    dateColumn: date,
    activityColumn: activity,
    instrumentColumn: instrument,
    grossAmountColumn: gross,
    quantityColumn: index('quantity'),
    executionPriceColumn: index('execution_price') ?? index('price'),
    feeColumn: index('fee'),
    taxColumn: index('tax'),
    currencyColumn: index('currency'),
    referenceColumn: index('reference'),
    noteColumn: index('note'),
    realizedPnlColumn: index('realized_pnl'),
    splitNumeratorColumn: index('split_numerator'),
    splitDenominatorColumn: index('split_denominator'),
  );
}
