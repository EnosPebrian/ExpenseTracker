import 'dart:convert';

const int receiptDocumentMaxBytes = 12 * 1024 * 1024;
const int bankStatementMaxBytes = 25 * 1024 * 1024;
const int bankStatementMaxPages = 50;

enum FinancialDocumentType { receiptInvoice, bankStatement }

enum DocumentImageSource { camera, gallery, files }

enum BankStatementReconciliationStatus {
  reconciled,
  insufficientInformation,
  mismatch,
}

class FinancialDocumentSource {
  const FinancialDocumentSource({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final List<int> bytes;

  Map<String, Object?> toRequestJson() => {
    'name': name,
    'mime_type': mimeType,
    'base64': base64Encode(bytes),
  };
}

class DocumentExtractionRequest {
  const DocumentExtractionRequest({
    required this.type,
    required this.documents,
  });

  final FinancialDocumentType type;
  final List<FinancialDocumentSource> documents;

  Map<String, Object?> toJson() => {
    'document_type': switch (type) {
      FinancialDocumentType.receiptInvoice => 'receipt_invoice',
      FinancialDocumentType.bankStatement => 'bank_statement',
    },
    'documents': documents.map((document) => document.toRequestJson()).toList(),
  };
}

class ExtractedReceiptLineItem {
  const ExtractedReceiptLineItem({
    required this.description,
    this.quantity,
    this.unitPrice,
    this.total,
  });

  final String description;
  final String? quantity;
  final String? unitPrice;
  final String? total;

  factory ExtractedReceiptLineItem.fromJson(Map<String, Object?> json) =>
      ExtractedReceiptLineItem(
        description: _requiredString(json, 'description'),
        quantity: _optionalString(json, 'quantity'),
        unitPrice: _optionalString(json, 'unit_price'),
        total: _optionalString(json, 'line_total'),
      );
}

class ReceiptExtraction {
  const ReceiptExtraction({
    required this.documentType,
    required this.merchant,
    required this.date,
    required this.time,
    required this.currency,
    required this.subtotal,
    required this.tax,
    required this.serviceCharge,
    required this.discount,
    required this.total,
    required this.reference,
    required this.paymentMethodHint,
    required this.lineItems,
    required this.confidence,
    required this.warnings,
  });

  final String documentType;
  final String? merchant;
  final String? date;
  final String? time;
  final String? currency;
  final String? subtotal;
  final String? tax;
  final String? serviceCharge;
  final String? discount;
  final String? total;
  final String? reference;
  final String? paymentMethodHint;
  final List<ExtractedReceiptLineItem> lineItems;
  final String confidence;
  final List<String> warnings;

  factory ReceiptExtraction.fromJson(Map<String, Object?> json) {
    final kind = _requiredString(json, 'document_type');
    if (!const {'receipt', 'invoice', 'unknown'}.contains(kind)) {
      throw const DocumentExtractionException(
        'The extraction service returned an unsupported document type.',
      );
    }
    return ReceiptExtraction(
      documentType: kind,
      merchant: _optionalString(json, 'merchant_name'),
      date: _optionalString(json, 'transaction_date'),
      time: _optionalString(json, 'transaction_time'),
      currency: _optionalString(json, 'currency'),
      subtotal: _optionalString(json, 'subtotal'),
      tax: _optionalString(json, 'tax'),
      serviceCharge: _optionalString(json, 'service_charge'),
      discount: _optionalString(json, 'discount'),
      total: _optionalString(json, 'total'),
      reference: _optionalString(json, 'receipt_number'),
      paymentMethodHint: _optionalString(json, 'payment_method_hint'),
      lineItems: _maps(
        json['line_items'],
      ).map(ExtractedReceiptLineItem.fromJson).toList(growable: false),
      confidence: _requiredString(json, 'confidence'),
      warnings: _strings(json['warnings']),
    );
  }
}

class ExtractedStatementTransaction {
  const ExtractedStatementTransaction({
    required this.sourceIndex,
    required this.pageNumber,
    required this.transactionDate,
    required this.postingDate,
    required this.description,
    required this.amount,
    required this.direction,
    required this.reference,
    required this.runningBalance,
    required this.confidence,
    required this.warnings,
  });

  final int sourceIndex;
  final int? pageNumber;
  final String? transactionDate;
  final String? postingDate;
  final String description;
  final String amount;
  final String direction;
  final String? reference;
  final String? runningBalance;
  final String confidence;
  final List<String> warnings;

  factory ExtractedStatementTransaction.fromJson(Map<String, Object?> json) {
    final direction = _requiredString(json, 'direction');
    if (!const {'debit', 'credit'}.contains(direction)) {
      throw const DocumentExtractionException(
        'The statement contains an invalid debit or credit direction.',
      );
    }
    return ExtractedStatementTransaction(
      sourceIndex: _requiredInt(json, 'source_index'),
      pageNumber: _optionalInt(json, 'page_number'),
      transactionDate: _optionalString(json, 'transaction_date'),
      postingDate: _optionalString(json, 'posting_date'),
      description: _requiredString(json, 'description'),
      amount: _requiredString(json, 'amount'),
      direction: direction,
      reference: _optionalString(json, 'reference'),
      runningBalance: _optionalString(json, 'running_balance'),
      confidence: _requiredString(json, 'confidence'),
      warnings: _strings(json['warnings']),
    );
  }
}

class BankStatementExtraction {
  const BankStatementExtraction({
    required this.institutionName,
    required this.accountHolder,
    required this.maskedAccountHint,
    required this.currency,
    required this.periodStart,
    required this.periodEnd,
    required this.openingBalance,
    required this.closingBalance,
    required this.transactions,
    required this.documentWarnings,
    required this.pagesDetected,
    required this.pagesProcessed,
  });

  final String? institutionName;
  final String? accountHolder;
  final String? maskedAccountHint;
  final String? currency;
  final String? periodStart;
  final String? periodEnd;
  final String? openingBalance;
  final String? closingBalance;
  final List<ExtractedStatementTransaction> transactions;
  final List<String> documentWarnings;
  final int pagesDetected;
  final int pagesProcessed;

  factory BankStatementExtraction.fromJson(Map<String, Object?> json) {
    final period = _map(json['statement_period']);
    final pagesDetected = _requiredInt(json, 'pages_detected');
    final pagesProcessed = _requiredInt(json, 'pages_processed');
    if (pagesDetected < 1 ||
        pagesProcessed < 1 ||
        pagesProcessed > pagesDetected ||
        pagesDetected > bankStatementMaxPages) {
      throw const DocumentExtractionException(
        'The statement page count is incomplete or exceeds the 50-page limit.',
      );
    }
    return BankStatementExtraction(
      institutionName: _optionalString(json, 'institution_name'),
      accountHolder: _optionalString(json, 'account_holder'),
      maskedAccountHint: _maskedHint(json['masked_account_hint']),
      currency: _optionalString(json, 'currency'),
      periodStart: _optionalString(period, 'start_date'),
      periodEnd: _optionalString(period, 'end_date'),
      openingBalance: _optionalString(json, 'opening_balance'),
      closingBalance: _optionalString(json, 'closing_balance'),
      transactions: _maps(
        json['transactions'],
      ).map(ExtractedStatementTransaction.fromJson).toList(growable: false),
      documentWarnings: _strings(json['document_warnings']),
      pagesDetected: pagesDetected,
      pagesProcessed: pagesProcessed,
    );
  }

  String? get institutionHint {
    final pieces = [
      institutionName,
      maskedAccountHint,
    ].whereType<String>().where((value) => value.isNotEmpty).toList();
    return pieces.isEmpty ? null : pieces.join(' ');
  }
}

class DocumentExtractionResult {
  const DocumentExtractionResult._({this.receipt, this.statement});

  final ReceiptExtraction? receipt;
  final BankStatementExtraction? statement;

  factory DocumentExtractionResult.fromJson(Map<String, Object?> json) {
    final type = _requiredString(json, 'document_type');
    return switch (type) {
      'receipt_invoice' => DocumentExtractionResult._(
        receipt: ReceiptExtraction.fromJson(_map(json['result'])),
      ),
      'bank_statement' => DocumentExtractionResult._(
        statement: BankStatementExtraction.fromJson(_map(json['result'])),
      ),
      _ => throw const DocumentExtractionException(
        'The extraction service returned an unsupported result.',
      ),
    };
  }
}

class DocumentExtractionException implements Exception {
  const DocumentExtractionException(this.message, {this.retryable = false});
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

String? _maskedHint(Object? value) {
  final hint = value is String ? value.trim() : '';
  if (hint.isEmpty) return null;
  final digits = hint.replaceAll(RegExp(r'\D'), '');
  if (digits.length > 4) {
    return digits.substring(digits.length - 4).padLeft(8, '*');
  }
  return digits.isEmpty ? null : digits.padLeft(8, '*');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw DocumentExtractionException('Extraction field "$key" is invalid.');
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value.trim().isEmpty ? null : value.trim();
  throw DocumentExtractionException('Extraction field "$key" is invalid.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num && value.toInt() == value && value >= 0) {
    return value.toInt();
  }
  throw DocumentExtractionException('Extraction field "$key" is invalid.');
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num && value.toInt() == value && value >= 0) {
    return value.toInt();
  }
  throw DocumentExtractionException('Extraction field "$key" is invalid.');
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  throw const DocumentExtractionException(
    'The extraction service returned malformed data.',
  );
}

List<Map<String, Object?>> _maps(Object? value) {
  if (value is! List) {
    throw const DocumentExtractionException(
      'The extraction service returned malformed rows.',
    );
  }
  return value.map(_map).toList(growable: false);
}

List<String> _strings(Object? value) {
  if (value is! List || value.any((item) => item is! String)) {
    throw const DocumentExtractionException(
      'The extraction service returned malformed warnings.',
    );
  }
  return value
      .cast<String>()
      .map((item) => item.trim())
      .toList(growable: false);
}
