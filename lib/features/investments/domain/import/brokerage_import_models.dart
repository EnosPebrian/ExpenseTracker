import '../../../assets/domain/entities/asset_definition.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../../../transactions/domain/import/transaction_import_models.dart';

enum BrokerageInstrumentResolution { notRequired, unresolved, mapped, create }

enum BrokerageImportClassification {
  newRecord,
  alreadyImported,
  semanticDuplicate,
  possibleDuplicate,
  invalid,
}

class BrokerageStatementMapping {
  const BrokerageStatementMapping({
    required this.dateColumn,
    required this.activityColumn,
    required this.instrumentColumn,
    required this.grossAmountColumn,
    this.quantityColumn,
    this.executionPriceColumn,
    this.feeColumn,
    this.taxColumn,
    this.currencyColumn,
    this.referenceColumn,
    this.noteColumn,
    this.realizedPnlColumn,
    this.splitNumeratorColumn,
    this.splitDenominatorColumn,
    this.dateFormat = CsvDateFormat.automatic,
    this.decimalSeparator = CsvSeparator.none,
    this.thousandsSeparator = CsvSeparator.none,
    this.stripCurrencySymbols = false,
  });

  final int dateColumn;
  final int activityColumn;
  final int instrumentColumn;
  final int grossAmountColumn;
  final int? quantityColumn;
  final int? executionPriceColumn;
  final int? feeColumn;
  final int? taxColumn;
  final int? currencyColumn;
  final int? referenceColumn;
  final int? noteColumn;
  final int? realizedPnlColumn;
  final int? splitNumeratorColumn;
  final int? splitDenominatorColumn;
  final CsvDateFormat dateFormat;
  final CsvSeparator decimalSeparator;
  final CsvSeparator thousandsSeparator;
  final bool stripCurrencySymbols;

  void validate() {
    final requiredColumns = {
      dateColumn,
      activityColumn,
      instrumentColumn,
      grossAmountColumn,
    };
    if (requiredColumns.length != 4) {
      throw const TransactionImportException(
        'Required brokerage columns cannot be assigned more than once.',
      );
    }
    if (decimalSeparator != CsvSeparator.none &&
        decimalSeparator == thousandsSeparator) {
      throw const TransactionImportException(
        'Decimal and thousands separators must be different.',
      );
    }
  }
}

class BrokerageImportIssue {
  const BrokerageImportIssue(this.message, {this.blocking = false});

  final String message;
  final bool blocking;
}

class BrokerageImportDraft {
  const BrokerageImportDraft({
    required this.sourceRowNumber,
    required this.sourceRowIdentity,
    required this.sourceRowFingerprint,
    required this.eventId,
    required this.date,
    required this.rawActivity,
    required this.activityType,
    required this.sourceInstrument,
    required this.currencyCode,
    required this.quantity,
    required this.executionPrice,
    required this.grossAmount,
    required this.feeAmount,
    required this.taxAmount,
    required this.splitNumerator,
    required this.splitDenominator,
    required this.reference,
    required this.note,
    required this.brokerRealizedPnl,
    required this.instrumentResolution,
    required this.instrumentId,
    required this.plannedInstrument,
    required this.classification,
    required this.included,
    required this.issues,
    this.matchedTransactionId,
  });

  final int sourceRowNumber;
  final String sourceRowIdentity;
  final String sourceRowFingerprint;
  final String eventId;
  final DateTime date;
  final String rawActivity;
  final BrokerageActivityType? activityType;
  final String sourceInstrument;
  final String currencyCode;
  final double? quantity;
  final int? executionPrice;
  final int grossAmount;
  final int feeAmount;
  final int taxAmount;
  final int? splitNumerator;
  final int? splitDenominator;
  final String reference;
  final String note;
  final int? brokerRealizedPnl;
  final BrokerageInstrumentResolution instrumentResolution;
  final String? instrumentId;
  final AssetDefinition? plannedInstrument;
  final BrokerageImportClassification classification;
  final bool included;
  final List<BrokerageImportIssue> issues;
  final String? matchedTransactionId;

  bool get requiresInstrument =>
      activityType == BrokerageActivityType.buy ||
      activityType == BrokerageActivityType.sell ||
      activityType == BrokerageActivityType.split;

  bool get needsInstrumentResolution =>
      (requiresInstrument || sourceInstrument.trim().isNotEmpty) &&
      instrumentId == null;

  bool get hasBlockingIssue => issues.any((issue) => issue.blocking);

  bool get canCommit =>
      included &&
      !hasBlockingIssue &&
      activityType != null &&
      !needsInstrumentResolution &&
      classification != BrokerageImportClassification.alreadyImported &&
      classification != BrokerageImportClassification.invalid;

  bool get canChangeInclusion =>
      classification == BrokerageImportClassification.newRecord ||
      classification == BrokerageImportClassification.semanticDuplicate ||
      classification == BrokerageImportClassification.possibleDuplicate;

  BrokerageImportDraft copyWith({
    BrokerageActivityType? activityType,
    bool clearActivityType = false,
    BrokerageInstrumentResolution? instrumentResolution,
    String? instrumentId,
    bool clearInstrumentId = false,
    AssetDefinition? plannedInstrument,
    bool clearPlannedInstrument = false,
    BrokerageImportClassification? classification,
    bool? included,
    List<BrokerageImportIssue>? issues,
    String? matchedTransactionId,
    bool clearMatchedTransactionId = false,
  }) => BrokerageImportDraft(
    sourceRowNumber: sourceRowNumber,
    sourceRowIdentity: sourceRowIdentity,
    sourceRowFingerprint: sourceRowFingerprint,
    eventId: eventId,
    date: date,
    rawActivity: rawActivity,
    activityType: clearActivityType ? null : activityType ?? this.activityType,
    sourceInstrument: sourceInstrument,
    currencyCode: currencyCode,
    quantity: quantity,
    executionPrice: executionPrice,
    grossAmount: grossAmount,
    feeAmount: feeAmount,
    taxAmount: taxAmount,
    splitNumerator: splitNumerator,
    splitDenominator: splitDenominator,
    reference: reference,
    note: note,
    brokerRealizedPnl: brokerRealizedPnl,
    instrumentResolution: instrumentResolution ?? this.instrumentResolution,
    instrumentId: clearInstrumentId ? null : instrumentId ?? this.instrumentId,
    plannedInstrument: clearPlannedInstrument
        ? null
        : plannedInstrument ?? this.plannedInstrument,
    classification: classification ?? this.classification,
    included: included ?? this.included,
    issues: issues ?? this.issues,
    matchedTransactionId: clearMatchedTransactionId
        ? null
        : matchedTransactionId ?? this.matchedTransactionId,
  );
}

class BrokerageImportPreview {
  const BrokerageImportPreview({
    required this.source,
    required this.drafts,
    required this.remoteFreshnessVerified,
  });

  final CsvParsedSource source;
  final List<BrokerageImportDraft> drafts;
  final bool remoteFreshnessVerified;

  int count(BrokerageImportClassification value) =>
      drafts.where((draft) => draft.classification == value).length;

  int get readyCount => drafts.where((draft) => draft.canCommit).length;
  int get unresolvedCount => drafts
      .where(
        (draft) =>
            draft.activityType == null || draft.needsInstrumentResolution,
      )
      .length;
  bool get canCommit =>
      readyCount > 0 &&
      drafts
          .where((draft) => draft.included)
          .every((draft) => !draft.hasBlockingIssue);
}

class BrokerageImportResult {
  const BrokerageImportResult({
    required this.importedEventIds,
    required this.transactionsCreated,
    required this.instrumentsCreated,
    required this.alreadyImported,
    required this.excluded,
    required this.completedAt,
  });

  final List<String> importedEventIds;
  final int transactionsCreated;
  final int instrumentsCreated;
  final int alreadyImported;
  final int excluded;
  final DateTime completedAt;
}
