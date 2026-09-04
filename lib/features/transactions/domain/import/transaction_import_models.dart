import '../entities/transaction.dart';

const int csvImportMaxBytes = 10 * 1024 * 1024;
const int csvImportMaxRows = 5000;
const int csvImportMaxColumns = 100;
const int csvImportMaxFieldLength = 10000;

enum CsvHeaderMode { firstRowHeaders, firstRowData }

enum CsvAmountStrategy { canonical, signedAmount, debitCredit }

enum CsvSignConvention { negativeExpense, positiveExpense }

enum CsvDateFormat {
  automatic,
  yyyyMmDd,
  ddMmYyyySlash,
  mmDdYyyySlash,
  ddMmYyyyDash,
  yyyyMmDdSlash,
  ddMmmYyyy,
  ddMmmmYyyy,
}

enum CsvSeparator { none, comma, period }

enum TransactionImportClassification {
  newRecord,
  alreadyImported,
  semanticDuplicate,
  possibleDuplicate,
  possiblePreviouslyDeleted,
  invalid,
}

class TransactionImportException implements Exception {
  const TransactionImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SelectedCsvFile {
  const SelectedCsvFile({required this.name, required this.bytes});
  final String name;
  final List<int> bytes;
}

class CsvSourceRow {
  const CsvSourceRow({
    required this.rowNumber,
    required this.values,
    this.identityKey,
    this.merchantHint,
  });
  final int rowNumber;
  final List<String> values;
  final String? identityKey;
  final String? merchantHint;
}

enum TransactionImportCategorySource { unresolved, source, rule, manual }

class CsvParsedSource {
  const CsvParsedSource({
    required this.fileName,
    required this.fileFingerprint,
    required this.delimiter,
    required this.headers,
    required this.rows,
    required this.headerMode,
  });

  final String fileName;
  final String fileFingerprint;
  final String delimiter;
  final List<String> headers;
  final List<CsvSourceRow> rows;
  final CsvHeaderMode headerMode;
}

class TransactionImportMapping {
  const TransactionImportMapping({
    required this.dateColumn,
    required this.descriptionColumn,
    this.amountColumn,
    this.debitColumn,
    this.creditColumn,
    this.typeColumn,
    this.categoryColumn,
    this.referenceColumn,
    this.noteColumn,
    this.amountStrategy = CsvAmountStrategy.canonical,
    this.signConvention = CsvSignConvention.negativeExpense,
    this.dateFormat = CsvDateFormat.automatic,
    this.decimalSeparator = CsvSeparator.none,
    this.thousandsSeparator = CsvSeparator.none,
    this.stripCurrencySymbols = false,
  });

  final int dateColumn;
  final int descriptionColumn;
  final int? amountColumn;
  final int? debitColumn;
  final int? creditColumn;
  final int? typeColumn;
  final int? categoryColumn;
  final int? referenceColumn;
  final int? noteColumn;
  final CsvAmountStrategy amountStrategy;
  final CsvSignConvention signConvention;
  final CsvDateFormat dateFormat;
  final CsvSeparator decimalSeparator;
  final CsvSeparator thousandsSeparator;
  final bool stripCurrencySymbols;

  void validate() {
    final requiredColumns = <int>[dateColumn, descriptionColumn];
    switch (amountStrategy) {
      case CsvAmountStrategy.canonical:
        if (amountColumn == null || typeColumn == null) {
          throw const TransactionImportException(
            'Map amount and type for canonical CSV.',
          );
        }
        requiredColumns.addAll([amountColumn!, typeColumn!]);
      case CsvAmountStrategy.signedAmount:
        if (amountColumn == null) {
          throw const TransactionImportException(
            'Map the signed amount column.',
          );
        }
        requiredColumns.add(amountColumn!);
      case CsvAmountStrategy.debitCredit:
        if (debitColumn == null || creditColumn == null) {
          throw const TransactionImportException(
            'Map both debit and credit columns.',
          );
        }
        requiredColumns.addAll([debitColumn!, creditColumn!]);
    }
    if (requiredColumns.toSet().length != requiredColumns.length) {
      throw const TransactionImportException(
        'A required CSV column cannot be assigned more than once.',
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

class TransactionImportIssue {
  const TransactionImportIssue(this.message, {this.blocking = false});
  final String message;
  final bool blocking;
}

class TransactionImportDraft {
  const TransactionImportDraft({
    required this.sourceRowNumber,
    this.sourceRowIdentity,
    required this.sourceRowFingerprint,
    required this.transactionId,
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    required this.category,
    required this.reference,
    required this.note,
    required this.classification,
    required this.included,
    required this.issues,
    this.matchedTransactionId,
    this.categorySource = TransactionImportCategorySource.unresolved,
    this.matchedRuleIds = const [],
    this.winningRuleId,
    this.ruleAmbiguous = false,
    this.merchantHint = '',
  });

  final int sourceRowNumber;
  final String? sourceRowIdentity;
  final String sourceRowFingerprint;
  final String transactionId;
  final DateTime date;
  final String description;
  final int amount;
  final TransactionType type;
  final String category;
  final String reference;
  final String note;
  final TransactionImportClassification classification;
  final bool included;
  final List<TransactionImportIssue> issues;
  final String? matchedTransactionId;
  final TransactionImportCategorySource categorySource;
  final List<String> matchedRuleIds;
  final String? winningRuleId;
  final bool ruleAmbiguous;
  final String merchantHint;

  bool get canImport =>
      included &&
      !issues.any((issue) => issue.blocking) &&
      (classification == TransactionImportClassification.newRecord ||
          classification == TransactionImportClassification.semanticDuplicate ||
          classification == TransactionImportClassification.possibleDuplicate);

  bool get canChangeInclusion =>
      classification == TransactionImportClassification.newRecord ||
      classification == TransactionImportClassification.semanticDuplicate ||
      classification == TransactionImportClassification.possibleDuplicate;

  TransactionImportDraft copyWith({
    DateTime? date,
    String? description,
    int? amount,
    TransactionType? type,
    String? category,
    String? reference,
    String? note,
    TransactionImportClassification? classification,
    bool? included,
    List<TransactionImportIssue>? issues,
    String? matchedTransactionId,
    TransactionImportCategorySource? categorySource,
    List<String>? matchedRuleIds,
    String? winningRuleId,
    bool? ruleAmbiguous,
    String? merchantHint,
  }) => TransactionImportDraft(
    sourceRowNumber: sourceRowNumber,
    sourceRowIdentity: sourceRowIdentity,
    sourceRowFingerprint: sourceRowFingerprint,
    transactionId: transactionId,
    date: date ?? this.date,
    description: description ?? this.description,
    amount: amount ?? this.amount,
    type: type ?? this.type,
    category: category ?? this.category,
    reference: reference ?? this.reference,
    note: note ?? this.note,
    classification: classification ?? this.classification,
    included: included ?? this.included,
    issues: issues ?? this.issues,
    matchedTransactionId: matchedTransactionId ?? this.matchedTransactionId,
    categorySource: categorySource ?? this.categorySource,
    matchedRuleIds: matchedRuleIds ?? this.matchedRuleIds,
    winningRuleId: winningRuleId ?? this.winningRuleId,
    ruleAmbiguous: ruleAmbiguous ?? this.ruleAmbiguous,
    merchantHint: merchantHint ?? this.merchantHint,
  );
}

class TransactionImportPreview {
  const TransactionImportPreview({
    required this.source,
    required this.drafts,
    required this.remoteFreshnessVerified,
  });
  final CsvParsedSource source;
  final List<TransactionImportDraft> drafts;
  final bool remoteFreshnessVerified;

  int count(TransactionImportClassification value) =>
      drafts.where((draft) => draft.classification == value).length;
  int get readyCount => drafts.where((draft) => draft.canImport).length;
  int get excludedCount => drafts.where((draft) => !draft.included).length;
  int get incomeTotal => drafts
      .where((draft) => draft.canImport && draft.type == TransactionType.income)
      .fold(0, (sum, draft) => sum + draft.amount);
  int get expenseTotal => drafts
      .where(
        (draft) => draft.canImport && draft.type == TransactionType.expense,
      )
      .fold(0, (sum, draft) => sum + draft.amount);
}

class TransactionImportResult {
  const TransactionImportResult({
    required this.importedIds,
    this.viewTransactionIds = const [],
    this.convertedInternalTransfers = 0,
    required this.alreadyImported,
    required this.skippedDuplicates,
    required this.excluded,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.completedAt,
  });
  final List<String> importedIds;
  final List<String> viewTransactionIds;
  final int convertedInternalTransfers;
  final int alreadyImported;
  final int skippedDuplicates;
  final int excluded;
  final int incomeTotal;
  final int expenseTotal;
  final DateTime completedAt;
}
