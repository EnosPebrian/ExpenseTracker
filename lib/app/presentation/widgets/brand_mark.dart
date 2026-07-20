import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: violet,
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 17),
    );
  }
}
