import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../master_data/domain/entities/account.dart';
import '../entities/transaction.dart';
import '../entities/transaction_import_rule.dart';
import '../services/transaction_import_rule_engine.dart';
import '../services/transaction_duplicate_detector.dart';
import 'csv_value_parsers.dart';
import 'transaction_import_models.dart';
import 'transaction_import_identity.dart';

class TransactionImportPlanner {
  const TransactionImportPlanner({
    this.dateParser = const CsvTransactionDateParser(),
    this.moneyParser = const CsvMoneyParser(),
    this.duplicateDetector = const TransactionDuplicateDetector(),
  });

  final CsvTransactionDateParser dateParser;
  final CsvMoneyParser moneyParser;
  final TransactionDuplicateDetector duplicateDetector;

  Future<TransactionImportPreview> build({
    required CsvParsedSource source,
    required TransactionImportMapping mapping,
    required Account account,
    required String activeBookId,
    required Iterable<Transaction> existingTransactions,
    required Iterable<String> expenseCategories,
    required Iterable<String> incomeCategories,
    Iterable<TransactionImportRule> importRules = const [],
    Map<String, ImportRuleCategory> ruleCategories = const {},
    Set<String> activeAccountIds = const {},
    bool remoteFreshnessVerified = true,
  }) async {
    mapping.validate();
    if (account.deletedAt != null || account.bookId != activeBookId) {
      throw const TransactionImportException(
        'Choose an active account in the current household.',
      );
    }
    final existingRecords = existingTransactions
        .map((item) => item.toRecord())
        .toList();
    final existingIndex = _ExistingTransactionIndex(existingRecords);
    final drafts = <TransactionImportDraft>[];
    for (final row in source.rows) {
      drafts.add(
        await _buildRow(
          source: source,
          row: row,
          mapping: mapping,
          account: account,
          activeBookId: activeBookId,
          existingIndex: existingIndex,
          expenseCategories: expenseCategories,
          incomeCategories: incomeCategories,
          importRules: importRules,
          ruleCategories: ruleCategories,
          activeAccountIds: activeAccountIds,
        ),
      );
    }
    return TransactionImportPreview(
      source: source,
      drafts: drafts,
      remoteFreshnessVerified: remoteFreshnessVerified,
    );
  }

  Future<TransactionImportDraft> _buildRow({
    required CsvParsedSource source,
    required CsvSourceRow row,
    required TransactionImportMapping mapping,
    required Account account,
    required String activeBookId,
    required _ExistingTransactionIndex existingIndex,
    required Iterable<String> expenseCategories,
    required Iterable<String> incomeCategories,
    required Iterable<TransactionImportRule> importRules,
    required Map<String, ImportRuleCategory> ruleCategories,
    required Set<String> activeAccountIds,
  }) async {
    final rawIdentity = jsonEncode({
      'row': row.identityKey ?? row.rowNumber,
      'date': _at(row, mapping.dateColumn),
      'description': _at(row, mapping.descriptionColumn),
      'amount': _atNullable(row, mapping.amountColumn),
      'debit': _atNullable(row, mapping.debitColumn),
      'credit': _atNullable(row, mapping.creditColumn),
      'reference': _atNullable(row, mapping.referenceColumn),
    });
    final rowFingerprint = await _sha256(utf8.encode(rawIdentity));
    final sourceRowIdentity = row.identityKey ?? row.rowNumber;
    final id = TransactionImportIdentity.derive(
      bookId: activeBookId,
      accountId: account.id,
      sourceFingerprint: source.fileFingerprint,
      sourceRowIdentity: sourceRowIdentity,
      sourceRowFingerprint: rowFingerprint,
    );
    final issues = <TransactionImportIssue>[];
    DateTime date = DateTime(1970);
    var description = _at(row, mapping.descriptionColumn).trim();
    var amount = 0;
    var type = TransactionType.expense;
    try {
      if (description.isEmpty) {
        throw const TransactionImportException('Description is required.');
      }
      date = dateParser.parse(_at(row, mapping.dateColumn), mapping.dateFormat);
      (amount, type) = _parseAmountAndType(row, mapping, account.currencyCode);
    } on TransactionImportException catch (error) {
      issues.add(TransactionImportIssue(error.message, blocking: true));
    } on FormatException {
      issues.add(
        const TransactionImportIssue(
          'A mapped value is invalid.',
          blocking: true,
        ),
      );
    } on RangeError {
      issues.add(
        const TransactionImportIssue(
          'A mapped column is missing.',
          blocking: true,
        ),
      );
    }
    final rawCategory = _atNullable(row, mapping.categoryColumn).trim();
    var category = _resolveCategory(
      rawCategory,
      type == TransactionType.income ? incomeCategories : expenseCategories,
    );
    var categorySource = category.isEmpty
        ? TransactionImportCategorySource.unresolved
        : TransactionImportCategorySource.source;
    var matchedRuleIds = const <String>[];
    String? winningRuleId;
    var ruleAmbiguous = false;
    if (category.isEmpty && !issues.any((item) => item.blocking)) {
      final ruleMatch = const TransactionImportRuleEngine().evaluate(
        input: TransactionImportRuleInput(
          bookId: activeBookId,
          type: type,
          accountId: account.id,
          description: description,
          reference: _atNullable(row, mapping.referenceColumn).trim(),
          merchantHint: row.merchantHint ?? '',
        ),
        rules: importRules,
        categories: ruleCategories,
        activeAccountIds: activeAccountIds,
      );
      matchedRuleIds = ruleMatch.matchedRuleIds;
      winningRuleId = ruleMatch.winningRuleId;
      ruleAmbiguous = ruleMatch.ambiguous;
      issues.addAll(ruleMatch.warnings.map(TransactionImportIssue.new));
      if (ruleMatch.hasSuggestion) {
        category = ruleMatch.categoryName!;
        categorySource = TransactionImportCategorySource.rule;
      }
    }
    if (rawCategory.isNotEmpty && category.isEmpty) {
      issues.add(
        const TransactionImportIssue(
          'Category was not matched; assign it during review.',
        ),
      );
    }
    if (!mapping.stripCurrencySymbols &&
        description.startsWith(RegExp(r'[=+\-@]'))) {
      issues.add(
        const TransactionImportIssue(
          'Description begins with a spreadsheet formula character.',
        ),
      );
    }
    var classification = issues.any((item) => item.blocking)
        ? TransactionImportClassification.invalid
        : TransactionImportClassification.newRecord;
    String? matchedId;
    if (classification != TransactionImportClassification.invalid) {
      final candidate = Transaction(
        id: id,
        bookId: activeBookId,
        title: description,
        category: category,
        account: account.name,
        date: date,
        amount: amount,
        type: type,
      ).toRecord();
      final relevantExisting = existingIndex.candidatesFor(candidate);
      final tombstone = relevantExisting
          .where((item) => item['deleted_at'] != null)
          .cast<Map<String, Object?>>();
      if (_matchesDeleted(candidate, tombstone)) {
        classification =
            TransactionImportClassification.possiblePreviouslyDeleted;
        issues.add(
          const TransactionImportIssue(
            'Possible previously deleted transaction.',
          ),
        );
      } else {
        final match = duplicateDetector.classify(candidate, relevantExisting);
        matchedId = match.existingId;
        classification = switch (match.classification) {
          TransactionCandidateClassification.exactIdentity =>
            TransactionImportClassification.alreadyImported,
          TransactionCandidateClassification.semanticDuplicate =>
            TransactionImportClassification.semanticDuplicate,
          TransactionCandidateClassification.possibleDuplicate =>
            TransactionImportClassification.possibleDuplicate,
          TransactionCandidateClassification.newRecord =>
            TransactionImportClassification.newRecord,
        };
      }
    }
    return TransactionImportDraft(
      sourceRowNumber: row.rowNumber,
      sourceRowIdentity: sourceRowIdentity.toString(),
      sourceRowFingerprint: rowFingerprint,
      transactionId: id,
      date: date,
      description: description,
      amount: amount,
      type: type,
      category: category,
      reference: _atNullable(row, mapping.referenceColumn).trim(),
      note: _atNullable(row, mapping.noteColumn).trim(),
      classification: classification,
      included: classification == TransactionImportClassification.newRecord,
      issues: issues,
      matchedTransactionId: matchedId,
      categorySource: categorySource,
      matchedRuleIds: matchedRuleIds,
      winningRuleId: winningRuleId,
      ruleAmbiguous: ruleAmbiguous,
      merchantHint: row.merchantHint ?? '',
    );
  }

  (int, TransactionType) _parseAmountAndType(
    CsvSourceRow row,
    TransactionImportMapping mapping,
    String currency,
  ) {
    int parse(String value, {bool allowZero = false}) => moneyParser.parse(
      value,
      currencyCode: currency,
      decimalSeparator: mapping.decimalSeparator,
      thousandsSeparator: mapping.thousandsSeparator,
      stripCurrencySymbols: mapping.stripCurrencySymbols,
      allowZero: allowZero,
    );
    switch (mapping.amountStrategy) {
      case CsvAmountStrategy.canonical:
        final amount = parse(_at(row, mapping.amountColumn!));
        final rawType = _at(row, mapping.typeColumn!).trim().toLowerCase();
        final type = switch (rawType) {
          'expense' => TransactionType.expense,
          'income' => TransactionType.income,
          _ => throw const TransactionImportException(
            'Type must be expense or income.',
          ),
        };
        return (amount.abs(), type);
      case CsvAmountStrategy.signedAmount:
        final signed = parse(_at(row, mapping.amountColumn!));
        final positiveIsExpense =
            mapping.signConvention == CsvSignConvention.positiveExpense;
        final expense = signed > 0 ? positiveIsExpense : !positiveIsExpense;
        return (
          signed.abs(),
          expense ? TransactionType.expense : TransactionType.income,
        );
      case CsvAmountStrategy.debitCredit:
        final debitRaw = _at(row, mapping.debitColumn!).trim();
        final creditRaw = _at(row, mapping.creditColumn!).trim();
        final debit = debitRaw.isEmpty
            ? 0
            : parse(debitRaw, allowZero: true).abs();
        final credit = creditRaw.isEmpty
            ? 0
            : parse(creditRaw, allowZero: true).abs();
        if ((debit > 0) == (credit > 0)) {
          throw const TransactionImportException(
            'Exactly one of debit or credit must be greater than zero.',
          );
        }
        return debit > 0
            ? (debit, TransactionType.expense)
            : (credit, TransactionType.income);
    }
  }

  static String _resolveCategory(String source, Iterable<String> categories) {
    if (source.trim().isEmpty) return '';
    final normalized = _normalize(source);
    final matches = categories
        .where((item) => _normalize(item) == normalized)
        .toList();
    return matches.length == 1 ? matches.single : '';
  }

  static bool _matchesDeleted(
    Map<String, Object?> candidate,
    Iterable<Map<String, Object?>> deleted,
  ) => deleted.any(
    (row) =>
        row['transaction_type'] == candidate['transaction_type'] &&
        row['amount'] == candidate['amount'] &&
        _normalize(row['account']?.toString() ?? '') ==
            _normalize(candidate['account']?.toString() ?? '') &&
        _normalize(row['title']?.toString() ?? '') ==
            _normalize(candidate['title']?.toString() ?? '') &&
        _localDay(row['transaction_date']) ==
            _localDay(candidate['transaction_date']),
  );

  static int _localDay(Object? value) {
    final date = DateTime.fromMillisecondsSinceEpoch((value as num).toInt());
    return DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
  }

  static String _at(CsvSourceRow row, int index) => row.values[index];
  static String _atNullable(CsvSourceRow row, int? index) =>
      index == null || index >= row.values.length ? '' : row.values[index];
  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static Future<String> _sha256(List<int> bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class _ExistingTransactionIndex {
  _ExistingTransactionIndex(Iterable<Map<String, Object?>> rows) {
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id != null) byId[id] = row;
      bySemanticKey.putIfAbsent(_key(row), () => []).add(row);
    }
  }

  final Map<String, Map<String, Object?>> byId = {};
  final Map<String, List<Map<String, Object?>>> bySemanticKey = {};

  Iterable<Map<String, Object?>> candidatesFor(Map<String, Object?> candidate) {
    final result = <Map<String, Object?>>[...?bySemanticKey[_key(candidate)]];
    final exact = byId[candidate['id']];
    if (exact != null && !result.any((row) => row['id'] == exact['id'])) {
      result.add(exact);
    }
    return result;
  }

  static String _key(Map<String, Object?> row) =>
      '${row['transaction_type']}|${row['amount']}|'
      '${(row['account']?.toString() ?? '').trim().toLowerCase()}';
}

TransactionImportMapping? canonicalMappingFor(List<String> headers) {
  final normalized = headers.map((item) => item.trim().toLowerCase()).toList();
  int? index(String name) {
    final result = normalized.indexOf(name);
    return result < 0 ? null : result;
  }

  final date = index('date');
  final description = index('description');
  final amount = index('amount');
  final type = index('type');
  if (date == null || description == null || amount == null || type == null) {
    return null;
  }
  return TransactionImportMapping(
    dateColumn: date,
    descriptionColumn: description,
    amountColumn: amount,
    typeColumn: type,
    categoryColumn: index('category'),
    referenceColumn: index('reference'),
    noteColumn: index('note'),
  );
}
