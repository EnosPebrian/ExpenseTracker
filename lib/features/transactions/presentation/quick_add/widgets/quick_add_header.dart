import 'package:flutter/material.dart';

class QuickAddHeader extends StatelessWidget {
  const QuickAddHeader({super.key, required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Text(
                'NEW ENTRY',
                style: TextStyle(
                  color: Color(0xFFA4A3B1),
                  fontSize: 9,
                  letterSpacing: 1.7,
                  fontWeight: FontWeight.w600,
                ),
              ),

              SizedBox(height: 8),

              Text(
                'Add transaction',
                style: TextStyle(
                  color: Color(0xFF24242F),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),

        IconButton(onPressed: onClose, icon: const Icon(Icons.close, size: 20)),
      ],
    );
  }
}
