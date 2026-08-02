import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/shared/widgets/page_layout.dart';

class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.name,
    required this.income,
    required this.expenses,
    required this.net,
  });

  final String name;
  final String income;
  final String expenses;
  final String net;

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
              'Recorded activity',
              style: TextStyle(color: muted, fontSize: 9),
            ),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(child: MetricSmall('Income', income)),
                Expanded(child: MetricSmall('Expenses', expenses)),
                Expanded(child: MetricSmall('Net', net)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
