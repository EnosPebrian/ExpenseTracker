import 'package:flutter/material.dart';

import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../controllers/asset_conversion_controller.dart';
import '../formatters/asset_quantity_formatter.dart';

class ConversionSummaryCard extends StatelessWidget {
  const ConversionSummaryCard({super.key, required this.controller});

  final AssetConversionController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2D2D3A),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CONVERSION SUMMARY',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 25),
            Text(
              'Rp ${money(controller.sellAsset ? controller.netProceeds : controller.totalCashPaid)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${controller.source} → ${controller.destination}',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            const SizedBox(height: 28),
            MetricSmall(
              controller.sellAsset ? 'Gross proceeds' : 'Asset value',
              'Rp ${money(controller.grossTradeAmount)}',
              labelColor: Colors.white54,
              valueColor: Colors.white,
            ),
            const SizedBox(height: 15),
            MetricSmall(
              controller.recordsFeeAsExpense && controller.sellAsset
                  ? 'Separate fee expense'
                  : controller.recordsFeeAsExpense
                  ? 'Fee expense'
                  : 'Fee',
              'Rp ${money(controller.feeAmount)}',
              labelColor: Colors.white54,
              valueColor: Colors.white,
            ),
            const SizedBox(height: 15),
            MetricSmall(
              controller.recordsFeeAsExpense
                  ? controller.sellAsset
                        ? 'Net cash effect'
                        : 'Total cash outflow'
                  : controller.sellAsset
                  ? 'Net received'
                  : 'Total paid',
              'Rp ${money(controller.sellAsset ? controller.netProceeds : controller.totalCashPaid)}',
              labelColor: Colors.white54,
              valueColor: Colors.white,
            ),
            if (controller.recordsFeeAsExpense && !controller.sellAsset) ...[
              const SizedBox(height: 15),
              MetricSmall(
                'Cost basis added',
                'Rp ${money(controller.costBasisAdded)}',
                labelColor: Colors.white54,
                valueColor: Colors.white,
              ),
            ],
            const SizedBox(height: 15),
            MetricSmall(
              controller.quantityLabel,
              AssetQuantityFormatter.withUnit(
                quantity: controller.quantity,
                kind: controller.selectedAssetDefinition.kind,
                unit: controller.unit,
                symbol: controller.selectedAssetDefinition.normalizedSymbol,
              ),
              labelColor: Colors.white54,
              valueColor: Colors.white,
            ),
            const SizedBox(height: 15),
            MetricSmall(
              controller.calculatedRateLabel,
              'Rp ${money(controller.unitPrice)}',
              labelColor: Colors.white54,
              valueColor: Colors.white,
            ),
            const SizedBox(height: 15),
            const MetricSmall(
              'Accounting impact',
              'Transfer between assets',
              labelColor: Colors.white54,
              valueColor: Colors.white,
            ),
            if (controller.feeAmount > 0) ...[
              const SizedBox(height: 15),
              MetricSmall(
                'Fee handling',
                controller.feeTreatmentLabel(controller.feeTreatment),
                labelColor: Colors.white54,
                valueColor: Colors.white,
              ),
            ],
            const SizedBox(height: 24),
            Text(
              controller.recordsFeeAsExpense
                  ? 'The linked fee expense affects ordinary expenses once. '
                        'The asset trade remains excluded from tithe.'
                  : 'This will not affect ordinary income, expenses, or tithe '
                        'obligations.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
