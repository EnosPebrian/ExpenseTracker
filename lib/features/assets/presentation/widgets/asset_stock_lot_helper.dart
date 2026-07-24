import 'package:flutter/material.dart';

import '../../controllers/asset_conversion_controller.dart';
import '../../domain/entities/asset_kind.dart';
import '../formatters/asset_quantity_formatter.dart';

class AssetStockLotHelper extends StatelessWidget {
  const AssetStockLotHelper({super.key, required this.controller});

  final AssetConversionController controller;

  @override
  Widget build(BuildContext context) {
    final definition = controller.selectedAssetDefinition;
    if (definition.kind != AssetKind.stock || definition.lotSize <= 1) {
      return const SizedBox.shrink();
    }

    final quantity = controller.quantity;
    if (quantity <= 0 || !quantity.isFinite) {
      return const SizedBox.shrink();
    }

    final style = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('1 lot = ${definition.lotSize} shares', style: style),
          const SizedBox(height: 2),
          Text(
            AssetQuantityFormatter.stockWithLots(
              shares: quantity,
              lotSize: definition.lotSize,
            ),
            style: style,
          ),
        ],
      ),
    );
  }
}
