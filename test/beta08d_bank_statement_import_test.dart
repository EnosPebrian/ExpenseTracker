import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/extraction/document_extraction_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/extraction/document_transaction_normalizer.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_planner.dart';

void main() {
  const normalizer = DocumentTransactionNormalizer();
  final account = Account(id: 'account', bookId: 'book', name: 'Bank');

  ExtractedStatementTransaction row({
    required int index,
    required String description,
    required String amount,
    required String direction,
    String date = '2026-08-19',
    String? balance,
    int page = 1,
  }) => ExtractedStatementTransaction(
    sourceIndex: index,
    pageNumber: page,
    transactionDate: date,
    postingDate: null,
    description: description,
    amount: amount,
    direction: direction,
    reference: null,
    runningBalance: balance,
    confidence: 'high',
    warnings: const [],
  );

  BankStatementExtraction statement({
    String? opening = '1000.00',
    String? closing = '850.00',
    List<ExtractedStatementTransaction>? rows,
  }) => BankStatementExtraction(
    institutionName: 'Synthetic Bank',
    accountHolder: 'Test Person',
    maskedAccountHint: '1234',
    currency: 'USD',
    periodStart: '2026-08-01',
    periodEnd: '2026-08-31',
    openingBalance: opening,
    closingBalance: closing,
    transactions:
        rows ??
        [
          row(
            index: 1,
            description: 'BANK FEE',
            amount: '150.00',
            direction: 'debit',
            balance: '850.00',
          ),
        ],
    documentWarnings: const [],
    pagesDetected: 1,
    pagesProcessed: 1,
  );

  Future<TransactionImportPreview> plan(
    BankStatementExtraction extraction,
    String fingerprint, {
    List<Transaction> existing = const [],
  }) async {
    final source = normalizer.statement(
      extraction: extraction,
      sourceFingerprint: fingerprint,
    );
    return const TransactionImportPlanner().build(
      source: source,
      mapping: const TransactionImportMapping(
        dateColumn: 0,
        descriptionColumn: 1,
        amountColumn: 2,
        typeColumn: 3,
        categoryColumn: 4,
        referenceColumn: 5,
        noteColumn: 6,
        decimalSeparator: CsvSeparator.period,
        stripCurrencySymbols: true,
      ),
      account: account.copyWith(currencyCode: 'USD'),
      activeBookId: 'book',
      existingTransactions: existing,
      expenseCategories: const ['Fees'],
      incomeCategories: const ['Refunds'],
    );
  }

  test(
    'debits and credits normalize to expense and income without summary rows',
    () async {
      final preview = await plan(
        statement(
          rows: [
            row(
              index: 1,
              description: 'FEE',
              amount: '12.34',
              direction: 'debit',
            ),
            row(
              index: 2,
              description: 'REFUND',
              amount: '5.00',
              direction: 'credit',
            ),
          ],
        ),
        'statement-sha',
      );
      expect(preview.drafts.map((draft) => draft.type), [
        TransactionType.expense,
        TransactionType.income,
      ]);
      expect(preview.drafts.map((draft) => draft.amount), [1234, 500]);
    },
  );

  test('balance reconciliation uses exact integer minor units', () {
    final result = BankStatementReconciliation.calculate(
      statement(),
      currencyCode: 'USD',
    );
    expect(result.status, BankStatementReconciliationStatus.reconciled);
    expect(result.debitTotal, 15000);
    expect(result.expectedClosingBalance, 85000);
  });

  test('mismatch and insufficient balance information are classified', () {
    expect(
      BankStatementReconciliation.calculate(
        statement(closing: '999.00'),
        currencyCode: 'USD',
      ).status,
      BankStatementReconciliationStatus.mismatch,
    );
    expect(
      BankStatementReconciliation.calculate(
        statement(opening: null),
        currencyCode: 'USD',
      ).status,
      BankStatementReconciliationStatus.insufficientInformation,
    );
  });

  test('image order changes deterministic source fingerprint', () async {
    const a = FinancialDocumentSource(
      name: 'a.png',
      mimeType: 'image/png',
      bytes: [1],
    );
    const b = FinancialDocumentSource(
      name: 'b.png',
      mimeType: 'image/png',
      bytes: [2],
    );
    final first = await DocumentSourceFingerprint.calculate(
      FinancialDocumentType.bankStatement,
      [a, b],
    );
    final second = await DocumentSourceFingerprint.calculate(
      FinancialDocumentType.bankStatement,
      [b, a],
    );
    expect(first, isNot(second));
  });

  test('same statement twice has stable IDs and zero new rows', () async {
    final first = await plan(statement(), 'same-sha');
    final draft = first.drafts.single;
    final existing = Transaction(
      id: draft.transactionId,
      bookId: 'book',
      title: draft.description,
      category: '',
      account: 'Bank',
      date: draft.date,
      amount: draft.amount,
      type: draft.type,
    );
    final repeated = await plan(statement(), 'same-sha', existing: [existing]);
    expect(repeated.readyCount, 0);
    expect(
      repeated.drafts.single.classification,
      TransactionImportClassification.alreadyImported,
    );
  });

  test(
    'overlapping statement from different bytes is a semantic duplicate',
    () async {
      final first = (await plan(statement(), 'july-august')).drafts.single;
      final existing = Transaction(
        id: first.transactionId,
        bookId: 'book',
        title: first.description,
        category: '',
        account: 'Bank',
        date: first.date,
        amount: first.amount,
        type: first.type,
      );
      final overlap = await plan(
        statement(),
        'august-september',
        existing: [existing],
      );
      expect(overlap.readyCount, 0);
      expect(
        overlap.drafts.single.classification,
        TransactionImportClassification.semanticDuplicate,
      );
    },
  );
}
