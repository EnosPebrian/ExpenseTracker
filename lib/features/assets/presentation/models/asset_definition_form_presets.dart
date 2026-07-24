import '../../domain/entities/asset_kind.dart';

enum AssetDefinitionPresetField {
  exchange,
  currency,
  unit,
  lotSize,
  providerCode,
  providerSymbol,
}

class AssetDefinitionFormValues {
  const AssetDefinitionFormValues({
    this.exchange = '',
    this.currency = '',
    this.unit = '',
    this.lotSize = '',
    this.providerCode = '',
    this.providerSymbol = '',
    this.onlinePricingEnabled = false,
  });

  final String exchange;
  final String currency;
  final String unit;
  final String lotSize;
  final String providerCode;
  final String providerSymbol;
  final bool onlinePricingEnabled;

  AssetDefinitionFormValues copyWith({
    String? exchange,
    String? currency,
    String? unit,
    String? lotSize,
    String? providerCode,
    String? providerSymbol,
    bool? onlinePricingEnabled,
  }) {
    return AssetDefinitionFormValues(
      exchange: exchange ?? this.exchange,
      currency: currency ?? this.currency,
      unit: unit ?? this.unit,
      lotSize: lotSize ?? this.lotSize,
      providerCode: providerCode ?? this.providerCode,
      providerSymbol: providerSymbol ?? this.providerSymbol,
      onlinePricingEnabled: onlinePricingEnabled ?? this.onlinePricingEnabled,
    );
  }
}

class AssetDefinitionFormPresets {
  const AssetDefinitionFormPresets();

  AssetDefinitionFormValues applyKindDefaults({
    required AssetKind kind,
    required AssetDefinitionFormValues current,
    required Set<AssetDefinitionPresetField> dirtyFields,
    required bool isCreating,
  }) {
    if (!isCreating) {
      return current;
    }

    return switch (kind) {
      AssetKind.gold => _apply(
        current,
        dirtyFields,
        currency: 'IDR',
        unit: 'gram',
        lotSize: '1',
        providerSymbol: '',
      ),
      AssetKind.stock => _apply(
        current,
        dirtyFields,
        currency: 'IDR',
        unit: 'share',
        lotSize: '1',
      ),
      AssetKind.crypto => _apply(
        current,
        dirtyFields,
        unit: '',
        lotSize: '1',
        providerSymbol: '',
      ),
      AssetKind.foreignCurrency => _apply(
        current,
        dirtyFields,
        currency: 'IDR',
        unit: '',
        lotSize: '1',
        exchange: '',
        providerSymbol: '',
      ),
      AssetKind.inventory => _apply(
        current,
        dirtyFields,
        currency: 'IDR',
        unit: '',
        lotSize: '1',
        exchange: '',
        providerSymbol: '',
      ),
      AssetKind.other => _apply(
        current,
        dirtyFields,
        unit: '',
        lotSize: '1',
        exchange: '',
        providerSymbol: '',
      ),
    };
  }

  AssetDefinitionFormValues applyIdxDefaults({
    required AssetDefinitionFormValues current,
    required Set<AssetDefinitionPresetField> dirtyFields,
    required bool isCreating,
  }) {
    if (!isCreating) {
      return current;
    }
    return _apply(
      current,
      dirtyFields,
      exchange: 'IDX',
      currency: 'IDR',
      unit: 'share',
      lotSize: '100',
    );
  }

  AssetDefinitionFormValues applySymbolAsUnit({
    required AssetDefinitionFormValues current,
    required Set<AssetDefinitionPresetField> dirtyFields,
    required bool isCreating,
    required String symbol,
  }) {
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (!isCreating || !RegExp(r'^[A-Z]{3}$').hasMatch(normalizedSymbol)) {
      return current;
    }
    return _apply(current, dirtyFields, unit: normalizedSymbol);
  }

  AssetDefinitionFormValues applyProviderPair({
    required AssetDefinitionFormValues current,
    required Set<AssetDefinitionPresetField> dirtyFields,
    required bool isCreating,
    required String symbol,
  }) {
    final normalizedSymbol = symbol.trim().toUpperCase();
    final normalizedCurrency = current.currency.trim().toUpperCase();
    if (!isCreating ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(normalizedSymbol) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(normalizedCurrency)) {
      return current;
    }
    return _apply(
      current,
      dirtyFields,
      providerSymbol: '$normalizedSymbol/$normalizedCurrency',
    );
  }

  AssetDefinitionFormValues _apply(
    AssetDefinitionFormValues current,
    Set<AssetDefinitionPresetField> dirtyFields, {
    String? exchange,
    String? currency,
    String? unit,
    String? lotSize,
    String? providerCode,
    String? providerSymbol,
  }) {
    return current.copyWith(
      exchange: _suggest(
        current.exchange,
        exchange,
        AssetDefinitionPresetField.exchange,
        dirtyFields,
      ),
      currency: _suggest(
        current.currency,
        currency,
        AssetDefinitionPresetField.currency,
        dirtyFields,
      ),
      unit: _suggest(
        current.unit,
        unit,
        AssetDefinitionPresetField.unit,
        dirtyFields,
      ),
      lotSize: _suggest(
        current.lotSize,
        lotSize,
        AssetDefinitionPresetField.lotSize,
        dirtyFields,
      ),
      providerCode: _suggest(
        current.providerCode,
        providerCode,
        AssetDefinitionPresetField.providerCode,
        dirtyFields,
      ),
      providerSymbol: _suggest(
        current.providerSymbol,
        providerSymbol,
        AssetDefinitionPresetField.providerSymbol,
        dirtyFields,
      ),
    );
  }

  String _suggest(
    String current,
    String? suggestion,
    AssetDefinitionPresetField field,
    Set<AssetDefinitionPresetField> dirtyFields,
  ) {
    if (suggestion == null || dirtyFields.contains(field)) {
      return current;
    }
    return suggestion;
  }
}
