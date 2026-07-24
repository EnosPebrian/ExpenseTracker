import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../domain/services/asset_definition_retirement_policy.dart';

class LegacyAssetDefinitionWarning extends StatelessWidget {
  const LegacyAssetDefinitionWarning({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('legacy-asset-definition-warning'),
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.history_rounded,
            size: 19,
            color: colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Legacy stock definition',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 3),
                Text(
                  AssetDefinitionRetirementPolicy.legacyPositionMessage,
                  style: TextStyle(color: muted, fontSize: 10, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
