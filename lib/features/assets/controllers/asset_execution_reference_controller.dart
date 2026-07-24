import 'package:flutter/material.dart';

import '../../transactions/domain/entities/asset_market_reference_source.dart';
import '../domain/entities/asset_definition.dart';
import '../domain/entities/asset_market_price.dart';
import '../domain/services/asset_market_reference_policy.dart';

class AssetExecutionReferenceController {
  AssetExecutionReferenceController({
    required this.definitionProvider,
    required this.marketPrices,
    required this.onChanged,
    this.policy = const AssetMarketReferencePolicy(),
  }) {
    priceController.addListener(onChanged);
  }

  final AssetDefinition Function() definitionProvider;
  final List<AssetMarketPrice> marketPrices;
  final VoidCallback onChanged;
  final AssetMarketReferencePolicy policy;

  final TextEditingController priceController = TextEditingController();
  AssetMarketReferenceSource? source;
  DateTime? quotedAt;
  String? _assetDefinitionId;

  int? get unitPrice {
    final value = int.tryParse(
      priceController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    return value == null || value <= 0 ? null : value;
  }

  AssetMarketPrice? get latestCompatible => policy.latestCompatible(
    definition: definitionProvider(),
    prices: marketPrices,
  );

  String? get validationMessage {
    if (source == null && priceController.text.trim().isEmpty) return null;
    if (source == null) {
      return 'Choose a reference-price source or clear the reference.';
    }
    if (unitPrice == null) return 'Reference price must be greater than zero.';
    if (_assetDefinitionId != definitionProvider().id) {
      return 'The reference price does not match the selected asset.';
    }
    return null;
  }

  void useManual() {
    source = AssetMarketReferenceSource.manual;
    quotedAt = DateTime.now();
    _assetDefinitionId = definitionProvider().id;
    onChanged();
  }

  bool useLatestCached() {
    final price = latestCompatible;
    if (price == null) return false;
    source = AssetMarketReferenceSource.cachedQuote;
    quotedAt = price.quotedAt;
    _assetDefinitionId = definitionProvider().id;
    priceController.text = _formatInteger(price.roundedPrice);
    onChanged();
    return true;
  }

  void clear() {
    source = null;
    quotedAt = null;
    _assetDefinitionId = null;
    priceController.clear();
    onChanged();
  }

  void dispose() {
    priceController.removeListener(onChanged);
    priceController.dispose();
  }

  static String _formatInteger(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }
    return '${value < 0 ? '-' : ''}${groups.join('.')}';
  }
}
