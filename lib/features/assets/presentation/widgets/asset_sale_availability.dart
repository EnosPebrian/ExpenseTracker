import 'package:flutter/material.dart';

import '../../controllers/asset_conversion_controller.dart';
import '../../domain/entities/asset_kind.dart';
import '../formatters/asset_quantity_formatter.dart';

class AssetSaleAvailability extends StatelessWidget {
  const AssetSaleAvailability({super.key, required this.controller});

  final AssetConversionController controller;

  @override
  Widget build(BuildContext context) {
    final validation = controller.saleValidation;

    if (!controller.sellAsset || validation == null) {
      return const SizedBox.shrink();
    }

    final available = _availabilityLabel(
      controller: controller,
      quantity: validation.availableQuantity,
    );
    final lotValidation = controller.lotValidation;

    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available: $available',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (lotValidation?.hasOddLotHolding == true) ...[
            const SizedBox(height: 4),
            Text(
              'This position contains '
              '${AssetQuantityFormatter.number(lotValidation!.oddLotShares, AssetKind.stock)} '
              'odd-lot shares.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          if (lotValidation?.isOddLotCleanup == true) ...[
            const SizedBox(height: 4),
            Text(
              'Odd-lot cleanup: '
              '${AssetQuantityFormatter.number(lotValidation!.oddLotShares, AssetKind.stock)} shares',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Remaining: '
              '${AssetQuantityFormatter.stockWithLots(shares: lotValidation.remainingShares, lotSize: lotValidation.lotSize)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          if (!validation.isValid) ...[
            const SizedBox(height: 4),
            Text(
              validation.message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _availabilityLabel({
    required AssetConversionController controller,
    required double quantity,
  }) {
    final definition = controller.selectedAssetDefinition;
    final formattedQuantity = AssetQuantityFormatter.number(
      quantity,
      definition.kind,
    );

    if (definition.kind == AssetKind.stock) {
      return AssetQuantityFormatter.stockWithLots(
        shares: quantity,
        lotSize: definition.lotSize,
      );
    }

    if (definition.kind == AssetKind.foreignCurrency) {
      return '${controller.currencySymbol} $formattedQuantity';
    }

    final unit = definition.normalizedUnit == 'gram'
        ? 'g'
        : definition.normalizedUnit;
    return '$formattedQuantity $unit';
  }
}
