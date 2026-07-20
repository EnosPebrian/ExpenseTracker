import 'package:flutter/material.dart';

import '../../design/app_colors.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    this.dark = false,
  });

  final String label;
  final String value;
  final String note;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: dark ? const Color(0xFF2D2D3A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: dark ? const Color(0xFFA7A6B4) : muted,
                fontSize: 10,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: dark ? Colors.white : ink,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              note,
              style: TextStyle(
                color: dark ? const Color(0xFFA7A6B4) : muted,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
