import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, required this.onAdd});

  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;

        return Container(
          height: compact ? 64 : 74,
          padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              if (!compact)
                const Text(
                  'Personal  /  ',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 15 : 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Search',
                onPressed: () {},
                icon: const Icon(Icons.search),
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: onAdd,
                  style: FilledButton.styleFrom(
                    backgroundColor: violet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text(
                    'Quick add',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
