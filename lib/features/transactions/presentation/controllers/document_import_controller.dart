import 'package:flutter/foundation.dart';

import '../../data/document_import_file_service.dart';
import '../../domain/extraction/document_extraction_models.dart';
import '../../domain/extraction/document_extraction_provider.dart';
import '../../domain/extraction/document_transaction_normalizer.dart';
import '../../domain/import/transaction_import_models.dart';
import '../../domain/entities/import_review_session.dart';
import 'transaction_import_controller.dart';

enum DocumentImportStage {
  idle,
  preparing,
  uploading,
  reading,
  checking,
  ready,
  cancelled,
}

class DocumentImportController extends ChangeNotifier {
  DocumentImportController({
    required this.type,
    required this.provider,
    required this.fileService,
    required this.transactions,
    this.normalizer = const DocumentTransactionNormalizer(),
  });

  final FinancialDocumentType type;
  final DocumentExtractionProvider provider;
  final DocumentImportFileService fileService;
  final TransactionImportController transactions;
  final DocumentTransactionNormalizer normalizer;

  DocumentImportStage stage = DocumentImportStage.idle;
  List<FinancialDocumentSource> sources = const [];
  DocumentExtractionResult? extraction;
  BankStatementReconciliation? reconciliation;
  String? error;
  bool _cancelled = false;

  bool get busy => const {
    DocumentImportStage.preparing,
    DocumentImportStage.uploading,
    DocumentImportStage.reading,
    DocumentImportStage.checking,
  }.contains(stage);

  Future<void> chooseReceipt(DocumentImageSource source) async =>
      _guard(() async {
        final picked = await fileService.pickReceipt(source);
        if (picked != null) sources = picked;
      });

  Future<void> chooseStatement({required bool images}) async =>
      _guard(() async {
        final picked = await fileService.pickStatement(images: images);
        if (picked != null) sources = picked;
      });

  Future<bool> extract() async {
    if (sources.isEmpty) {
      error = 'Choose a document first.';
      notifyListeners();
      return false;
    }
    _cancelled = false;
    error = null;
    try {
      stage = DocumentImportStage.preparing;
      notifyListeners();
      final fingerprint = await DocumentSourceFingerprint.calculate(
        type,
        sources,
      );
      if (_cancelled) return false;
      stage = DocumentImportStage.uploading;
      notifyListeners();
      final extracted = await provider.extract(
        DocumentExtractionRequest(type: type, documents: sources),
      );
      if (_cancelled) return false;
      stage = DocumentImportStage.reading;
      notifyListeners();
      extraction = extracted;
      if (type == FinancialDocumentType.receiptInvoice) {
        final receipt = extracted.receipt!;
        transactions.reviewSourceType = receipt.documentType == 'invoice'
            ? ImportReviewSourceType.invoice
            : ImportReviewSourceType.receipt;
        transactions.reviewTitle = [
          receipt.merchant,
          receipt.date,
        ].whereType<String>().where((value) => value.isNotEmpty).join(' — ');
        if (transactions.reviewTitle!.isEmpty) {
          transactions.reviewTitle = receipt.documentType == 'invoice'
              ? 'Invoice review'
              : 'Receipt review';
        }
        transactions.reviewSummary = {
          'merchant': receipt.merchant,
          'date': receipt.date,
          'currency': receipt.currency,
          'line_count': receipt.lineItems.length,
        };
      } else {
        final statement = extracted.statement!;
        transactions.reviewSourceType = ImportReviewSourceType.bankStatement;
        transactions.reviewTitle =
            [
                  statement.institutionName,
                  [
                    statement.periodStart,
                    statement.periodEnd,
                  ].whereType<String>().join(' – '),
                ]
                .where((value) => value != null && value.toString().isNotEmpty)
                .join(' — ');
        if (transactions.reviewTitle!.isEmpty) {
          transactions.reviewTitle = 'Bank statement review';
        }
        transactions.reviewSummary = {
          'institution': statement.institutionName,
          'period_start': statement.periodStart,
          'period_end': statement.periodEnd,
          'currency': statement.currency,
          'row_count': statement.transactions.length,
          'pages_processed': statement.pagesProcessed,
        };
      }
      final prepared = switch (type) {
        FinancialDocumentType.receiptInvoice => normalizer.receipt(
          extraction: extracted.receipt!,
          sourceFingerprint: fingerprint,
        ),
        FinancialDocumentType.bankStatement => normalizer.statement(
          extraction: extracted.statement!,
          sourceFingerprint: fingerprint,
        ),
      };
      stage = DocumentImportStage.checking;
      notifyListeners();
      transactions.loadPreparedSource(prepared);
      transactions.setMapping(
        const TransactionImportMapping(
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
      );
      final account = transactions.destinationAccount;
      if (type == FinancialDocumentType.bankStatement && account != null) {
        reconciliation = BankStatementReconciliation.calculate(
          extracted.statement!,
          currencyCode: account.currencyCode,
        );
      }
      await transactions.analyze();
      if (_cancelled) return false;
      if (transactions.error != null) {
        error = transactions.error;
        stage = DocumentImportStage.idle;
        notifyListeners();
        return false;
      }
      stage = DocumentImportStage.ready;
      notifyListeners();
      return true;
    } on DocumentExtractionException catch (exception) {
      error = exception.message;
      stage = DocumentImportStage.idle;
      notifyListeners();
      return false;
    } catch (_) {
      error = 'The document could not be prepared for review.';
      stage = DocumentImportStage.idle;
      notifyListeners();
      return false;
    }
  }

  void cancel() {
    _cancelled = true;
    stage = DocumentImportStage.cancelled;
    notifyListeners();
  }

  Future<void> _guard(Future<void> Function() action) async {
    error = null;
    try {
      await action();
    } on DocumentExtractionException catch (exception) {
      error = exception.message;
    } catch (_) {
      error = 'The selected document could not be read.';
    }
    notifyListeners();
  }
}
