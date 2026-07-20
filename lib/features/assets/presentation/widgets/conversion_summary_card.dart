import 'package:flutter/material.dart';

import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../controllers/asset_conversion_controller.dart';

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
              'Rp ${money(controller.cash)}',
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
              controller.quantityLabel,
              '${controller.quantity.toStringAsFixed(2)} '
              '${controller.unit}',
              labelColor: Colors.white54,
              valueColor: Colors.white,
            ),
            const SizedBox(height: 15),
            MetricSmall(
              'Average unit value',
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
            const SizedBox(height: 15),
            MetricSmall(
              'Fee treatment',
              controller.feeTreatment,
              labelColor: Colors.white54,
              valueColor: Colors.white,
            ),
            const SizedBox(height: 24),
            const Text(
              'This will not affect ordinary income, expenses, or tithe '
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
