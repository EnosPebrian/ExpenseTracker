import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';

class AccountCard extends StatelessWidget {
  const AccountCard(this.type, this.name, this.value, this.dark, {super.key});

  final String type;
  final String name;
  final String value;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: dark ? const Color(0xFF2D2D3A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              type,
              style: TextStyle(
                color: dark ? Colors.white54 : muted,
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: dark ? Colors.white : ink,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                color: dark ? Colors.white54 : muted,
                fontSize: 10,
              ),
            ),
            const Spacer(),
            const Text(
              'Updated just now',
              style: TextStyle(color: muted, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}
