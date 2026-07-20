import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/widgets/page_layout.dart';

class ProjectCard extends StatelessWidget {
  const ProjectCard(
    this.name,
    this.income,
    this.expense,
    this.progress, {
    super.key,
  });

  final String name;
  final String income;
  final String expense;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const Text(
              'Active project',
              style: TextStyle(color: muted, fontSize: 9),
            ),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(child: MetricSmall('Income', income)),
                Expanded(child: MetricSmall('Expenses', expense)),
              ],
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(5),
              color: violet,
              backgroundColor: border,
            ),
          ],
        ),
      ),
    );
  }
}
