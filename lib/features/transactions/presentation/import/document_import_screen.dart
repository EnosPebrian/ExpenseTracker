import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../master_data/domain/entities/account.dart';
import '../../domain/extraction/document_extraction_models.dart';
import '../controllers/document_import_controller.dart';
import 'transaction_import_screen.dart';

class DocumentImportScreen extends StatelessWidget {
  const DocumentImportScreen({
    super.key,
    required this.controller,
    required this.onViewImported,
  });

  final DocumentImportController controller;
  final ValueChanged<List<String>> onViewImported;

  static Future<void> show(
    BuildContext context, {
    required DocumentImportController controller,
    required ValueChanged<List<String>> onViewImported,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DocumentImportScreen(
        controller: controller,
        onViewImported: onViewImported,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final receipt = controller.type == FinancialDocumentType.receiptInvoice;
    return Scaffold(
      appBar: AppBar(
        title: Text(receipt ? 'Receipt / invoice' : 'Bank statement'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([controller, controller.transactions]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              receipt ? 'Import a receipt or invoice' : 'Import bank statement',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              receipt
                  ? 'Secure extraction creates one editable expense draft. Nothing is saved until you confirm.'
                  : 'Choose one PDF or ordered page images. Review every extracted row before atomic import.',
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<Account>(
              initialValue: controller.transactions.destinationAccount,
              decoration: const InputDecoration(
                labelText: 'Destination account (required)',
              ),
              items: controller.transactions.accounts
                  .where(
                    (account) =>
                        account.deletedAt == null &&
                        account.bookId == controller.transactions.activeBookId,
                  )
                  .map(
                    (account) => DropdownMenuItem(
                      value: account,
                      child: Text('${account.name} · ${account.currencyCode}'),
                    ),
                  )
                  .toList(),
              onChanged: controller.busy
                  ? null
                  : controller.transactions.selectAccount,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: receipt
                  ? _receiptButtons()
                  : [
                      OutlinedButton.icon(
                        onPressed: controller.busy
                            ? null
                            : () => controller.chooseStatement(images: false),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Choose PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.busy
                            ? null
                            : () => controller.chooseStatement(images: true),
                        icon: const Icon(Icons.collections),
                        label: const Text('Choose page images'),
                      ),
                    ],
            ),
            if (controller.sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${controller.sources.length} source file(s): '
                '${controller.sources.map((source) => source.name).join(', ')}',
              ),
            ],
            if (controller.error case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (controller.busy) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_stageLabel(controller.stage)),
              TextButton(
                onPressed: controller.cancel,
                child: const Text('Cancel'),
              ),
            ] else ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed:
                    controller.sources.isEmpty ||
                        controller.transactions.destinationAccount == null
                    ? null
                    : () => _extractAndReview(context),
                icon: const Icon(Icons.document_scanner),
                label: Text(
                  controller.error == null
                      ? 'Extract securely'
                      : 'Retry extraction',
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'The document is sent directly to an authenticated server function, is not made public, and is not retained by Pilgrim Tracker after extraction.',
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _receiptButtons() => [
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      OutlinedButton.icon(
        onPressed: controller.busy
            ? null
            : () => controller.chooseReceipt(DocumentImageSource.camera),
        icon: const Icon(Icons.camera_alt),
        label: const Text('Take photo'),
      ),
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      OutlinedButton.icon(
        onPressed: controller.busy
            ? null
            : () => controller.chooseReceipt(DocumentImageSource.gallery),
        icon: const Icon(Icons.photo_library),
        label: const Text('Choose from gallery'),
      ),
    OutlinedButton.icon(
      onPressed: controller.busy
          ? null
          : () => controller.chooseReceipt(DocumentImageSource.files),
      icon: const Icon(Icons.file_open),
      label: const Text('Choose image file'),
    ),
  ];

  Future<void> _extractAndReview(BuildContext context) async {
    if (!await controller.extract() || !context.mounted) return;
    await TransactionImportScreen.showPrepared(
      context,
      controller: controller.transactions,
      title: controller.type == FinancialDocumentType.receiptInvoice
          ? 'Review receipt draft'
          : 'Review statement transactions',
      sourceSummary: _summary(context),
      onViewImported: onViewImported,
    );
  }

  Widget _summary(BuildContext context) {
    final receipt = controller.extraction?.receipt;
    if (receipt != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Extracted receipt',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('Merchant: ${receipt.merchant ?? 'Needs review'}'),
              Text('Total: ${receipt.total ?? 'Total needs review'}'),
              Text('Tax: ${receipt.tax ?? 'Not detected'}'),
              Text('Reference: ${receipt.reference ?? 'Not detected'}'),
              Text('Line items: ${receipt.lineItems.length}'),
              if (receipt.documentType == 'invoice')
                const Text(
                  'This appears to be an invoice. Confirm that payment actually occurred before saving it as a transaction.',
                ),
              for (final warning in receipt.warnings) Text('Warning: $warning'),
            ],
          ),
        ),
      );
    }
    final statement = controller.extraction!.statement!;
    final reconciliation = controller.reconciliation!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Statement details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('Institution: ${statement.institutionHint ?? 'Not detected'}'),
            Text(
              'Period: ${statement.periodStart ?? '?'} – ${statement.periodEnd ?? '?'}',
            ),
            Text('Currency: ${statement.currency ?? 'Needs review'}'),
            Text('Transactions detected: ${statement.transactions.length}'),
            Text(
              'Pages processed: ${statement.pagesProcessed}/${statement.pagesDetected}',
            ),
            Text('Debit total: ${reconciliation.debitTotal}'),
            Text('Credit total: ${reconciliation.creditTotal}'),
            Text('Balance reconciliation: ${reconciliation.status.name}'),
            if (reconciliation.status ==
                BankStatementReconciliationStatus.mismatch)
              const Text(
                'Statement totals could not be reconciled. Review extracted rows before importing.',
              ),
            for (final warning in [
              ...statement.documentWarnings,
              ...reconciliation.runningBalanceWarnings,
            ])
              Text('Warning: $warning'),
          ],
        ),
      ),
    );
  }

  static String _stageLabel(DocumentImportStage stage) => switch (stage) {
    DocumentImportStage.preparing => 'Preparing document',
    DocumentImportStage.uploading => 'Uploading securely',
    DocumentImportStage.reading => 'Reading document',
    DocumentImportStage.checking => 'Checking transactions',
    _ => 'Ready for review',
  };
}
