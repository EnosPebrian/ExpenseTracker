import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/presentation/models/asset_definition_form_presets.dart';

void main() {
  const presets = AssetDefinitionFormPresets();

  test('applies safe gold defaults without enabling online pricing', () {
    final result = presets.applyKindDefaults(
      kind: AssetKind.gold,
      current: const AssetDefinitionFormValues(),
      dirtyFields: const {},
      isCreating: true,
    );
    expect(result.currency, 'IDR');
    expect(result.unit, 'gram');
    expect(result.lotSize, '1');
    expect(result.providerSymbol, isEmpty);
    expect(result.onlinePricingEnabled, isFalse);
  });

  test('applies generic stock defaults without assuming an IDX lot', () {
    final result = presets.applyKindDefaults(
      kind: AssetKind.stock,
      current: const AssetDefinitionFormValues(),
      dirtyFields: const {},
      isCreating: true,
    );
    expect(result.currency, 'IDR');
    expect(result.unit, 'share');
    expect(result.lotSize, '1');
    expect(result.exchange, isEmpty);
  });

  test('offers explicit IDX defaults', () {
    final result = presets.applyIdxDefaults(
      current: const AssetDefinitionFormValues(unit: 'share', lotSize: '1'),
      dirtyFields: const {},
      isCreating: true,
    );
    expect(result.exchange, 'IDX');
    expect(result.currency, 'IDR');
    expect(result.unit, 'share');
    expect(result.lotSize, '100');
  });

  test('offers foreign-currency unit and provider pair independently', () {
    final defaults = presets.applyKindDefaults(
      kind: AssetKind.foreignCurrency,
      current: const AssetDefinitionFormValues(unit: 'share'),
      dirtyFields: const {},
      isCreating: true,
    );
    final unit = presets.applySymbolAsUnit(
      current: defaults,
      dirtyFields: const {},
      isCreating: true,
      symbol: 'usd',
    );
    final pair = presets.applyProviderPair(
      current: unit,
      dirtyFields: const {},
      isCreating: true,
      symbol: 'usd',
    );
    expect(defaults.currency, 'IDR');
    expect(defaults.unit, isEmpty);
    expect(unit.unit, 'USD');
    expect(unit.providerSymbol, isEmpty);
    expect(pair.providerSymbol, 'USD/IDR');
    expect(pair.onlinePricingEnabled, isFalse);
  });

  test('inventory defaults leave the measurement unit open', () {
    final result = presets.applyKindDefaults(
      kind: AssetKind.inventory,
      current: const AssetDefinitionFormValues(unit: 'share'),
      dirtyFields: const {},
      isCreating: true,
    );
    expect(result.currency, 'IDR');
    expect(result.unit, isEmpty);
    expect(result.lotSize, '1');
  });

  test('presets never overwrite dirty fields', () {
    final result = presets.applyIdxDefaults(
      current: const AssetDefinitionFormValues(
        exchange: 'NASDAQ',
        currency: 'USD',
        unit: 'custom',
        lotSize: '25',
      ),
      dirtyFields: const {
        AssetDefinitionPresetField.exchange,
        AssetDefinitionPresetField.currency,
        AssetDefinitionPresetField.unit,
        AssetDefinitionPresetField.lotSize,
      },
      isCreating: true,
    );
    expect(result.exchange, 'NASDAQ');
    expect(result.currency, 'USD');
    expect(result.unit, 'custom');
    expect(result.lotSize, '25');
  });

  test('presets never overwrite edit or protected values', () {
    const existing = AssetDefinitionFormValues(
      exchange: 'IDX',
      currency: 'IDR',
      unit: 'share',
      lotSize: '100',
      providerSymbol: 'BBCA.JK',
      onlinePricingEnabled: true,
    );
    final result = presets.applyKindDefaults(
      kind: AssetKind.gold,
      current: existing,
      dirtyFields: const {},
      isCreating: false,
    );
    expect(result.exchange, existing.exchange);
    expect(result.unit, existing.unit);
    expect(result.lotSize, existing.lotSize);
    expect(result.providerSymbol, existing.providerSymbol);
    expect(result.onlinePricingEnabled, isTrue);
  });
}
