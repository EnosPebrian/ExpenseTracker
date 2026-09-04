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

  ReceiptExtraction receipt({
    String? total = '1234.50',
    String? date = '2026-08-19',
  }) => ReceiptExtraction(
    documentType: 'receipt',
    merchant: 'Grocery Store',
    date: date,
    time: '10:00',
    currency: 'USD',
    subtotal: '1200.00',
    tax: '34.50',
    serviceCharge: null,
    discount: null,
    total: total,
    reference: 'R-42',
    paymentMethodHint: 'card ending 1234',
    lineItems: const [
      ExtractedReceiptLineItem(description: 'Food', total: '1234.50'),
    ],
    confidence: 'high',
    warnings: const [],
  );

  Future<TransactionImportDraft> plan(
    ReceiptExtraction extraction, {
    List<Transaction> existing = const [],
  }) async {
    final source = normalizer.receipt(
      extraction: extraction,
      sourceFingerprint: 'image-sha',
    );
    final preview = await const TransactionImportPlanner().build(
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
      expenseCategories: const ['Groceries'],
      incomeCategories: const ['Salary'],
    );
    return preview.drafts.single;
  }

  test(
    'receipt becomes one editable expense draft with exact minor units',
    () async {
      final draft = await plan(receipt());
      expect(draft.description, 'Grocery Store');
      expect(draft.amount, 123450);
      expect(draft.type, TransactionType.expense);
      expect(draft.reference, 'R-42');
    },
  );

  test(
    'missing date or unreadable total remains invalid for manual review',
    () async {
      expect(
        (await plan(receipt(date: null))).classification,
        TransactionImportClassification.invalid,
      );
      expect(
        (await plan(receipt(total: null))).classification,
        TransactionImportClassification.invalid,
      );
    },
  );

  test(
    'same source and account is deterministic and repeated import is excluded',
    () async {
      final first = await plan(receipt());
      final existing = Transaction(
        id: first.transactionId,
        bookId: 'book',
        title: first.description,
        category: first.category,
        account: 'Bank',
        date: first.date,
        amount: first.amount,
        type: first.type,
      );
      final second = await plan(receipt(), existing: [existing]);
      expect(second.transactionId, first.transactionId);
      expect(
        second.classification,
        TransactionImportClassification.alreadyImported,
      );
      expect(second.included, isFalse);
    },
  );

  test('single source fingerprint is SHA-256 of original bytes', () async {
    final value = await DocumentSourceFingerprint.calculate(
      FinancialDocumentType.receiptInvoice,
      [
        const FinancialDocumentSource(
          name: 'x.jpg',
          mimeType: 'image/jpeg',
          bytes: [1, 2, 3],
        ),
      ],
    );
    expect(
      value,
      '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
    );
  });
}
