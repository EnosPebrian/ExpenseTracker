import 'package:flutter/material.dart';

import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../controllers/asset_conversion_controller.dart';
import '../../domain/services/asset_execution_analysis.dart';
import '../../../transactions/domain/entities/asset_market_reference_source.dart';

class AssetExecutionReferenceFields extends StatelessWidget {
  const AssetExecutionReferenceFields({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final AssetConversionController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hasReference =
        controller.marketReferenceSource != null ||
        controller.referencePriceController.text.trim().isNotEmpty;
    final cached = controller.latestCompatibleMarketPrice;
    final analysis = controller.executionAnalysis;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Execution comparison (optional)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Compare the calculated execution price with a saved snapshot.',
            style: TextStyle(fontSize: 10, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          if (!hasReference)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'No reference price',
                key: Key('no_market_reference_state'),
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const Key('manual_market_reference_button'),
                onPressed: controller.useManualMarketReference,
                child: const Text('Enter manually'),
              ),
              OutlinedButton(
                key: const Key('cached_market_reference_button'),
                onPressed: cached == null
                    ? null
                    : controller.useLatestCachedMarketReference,
                child: const Text('Use latest saved price'),
              ),
              if (hasReference)
                TextButton(
                  key: const Key('clear_market_reference_button'),
                  onPressed: controller.clearMarketReference,
                  child: const Text('Clear'),
                ),
            ],
          ),
          if (hasReference) ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('market_reference_price_field'),
              controller: controller.referencePriceController,
              readOnly:
                  controller.marketReferenceSource ==
                  AssetMarketReferenceSource.cachedQuote,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsFormatter()],
              decoration: InputDecoration(
                labelText: 'Reference price per ${controller.unit}',
                prefixText: 'Rp ',
                errorText: controller.marketReferenceValidationMessage,
              ),
            ),
            if (controller.marketReferenceQuotedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                '${controller.marketReferenceSource == AssetMarketReferenceSource.manual ? 'Manual' : 'Saved price'} snapshot · '
                '${_formatTimestamp(controller.marketReferenceQuotedAt!)}',
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ],
          ],
          if (analysis != null) ...[
            const SizedBox(height: 12),
            _ExecutionComparison(analysis: analysis, controller: controller),
          ],
        ],
      ),
    );
  }

  static String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _ExecutionComparison extends StatelessWidget {
  const _ExecutionComparison({
    required this.analysis,
    required this.controller,
  });

  final AssetExecutionAnalysisResult analysis;
  final AssetConversionController controller;

  @override
  Widget build(BuildContext context) {
    final outcome = switch ((controller.sellAsset, analysis.outcome)) {
      (_, AssetExecutionOutcome.neutral) => 'Matched reference price',
      (false, AssetExecutionOutcome.favorable) => 'Paid below reference',
      (false, AssetExecutionOutcome.unfavorable) => 'Paid above reference',
      (true, AssetExecutionOutcome.favorable) => 'Sold above reference',
      (true, AssetExecutionOutcome.unfavorable) => 'Sold below reference',
    };
    final color = switch (analysis.outcome) {
      AssetExecutionOutcome.favorable => const Color(0xFF168A5B),
      AssetExecutionOutcome.neutral => Colors.black54,
      AssetExecutionOutcome.unfavorable => Theme.of(context).colorScheme.error,
    };

    final unit = controller.unit.toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(
          'Reference price',
          'Rp ${_money(analysis.referenceUnitPrice)} / $unit',
        ),
        _row(
          'Execution price',
          'Rp ${_money(analysis.executionUnitPrice)} / $unit',
        ),
        _row(
          'Difference',
          'Rp ${_money(analysis.signedDifferencePerUnit.abs())} / $unit',
        ),
        _row(
          'Estimated impact',
          'Rp ${_money(analysis.estimatedTotalDifference.abs())}',
        ),
        if (controller.feeAmount > 0)
          _row(
            controller.sellAsset ? 'Net cash rate' : 'All-in cash rate',
            'Rp ${_money(controller.cashEffectUnitPrice)} / $unit',
          ),
        const SizedBox(height: 4),
        Text(
          outcome,
          key: const Key('execution_comparison_outcome'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${analysis.differenceBasisPoints.abs().toStringAsFixed(1)} bps '
          'against the saved reference quote; not a historical bid/ask spread.',
          style: const TextStyle(fontSize: 10, color: Colors.black54),
        ),
      ],
    );
  }

  static Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 10))),
        Text(
          value,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  static String _money(int value) {
    final source = value.toString();
    final result = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      if (index > 0 && (source.length - index) % 3 == 0) result.write('.');
      result.write(source[index]);
    }
    return result.toString();
  }
}
