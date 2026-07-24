import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_definition_retirement_policy.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_definition_usage_policy.dart';

void main() {
  const policy = AssetDefinitionRetirementPolicy();

  test('matches only the exact fixed retired seed ID', () {
    expect(policy.isRetiredSystemDefinition(_definition()), isTrue);
    expect(
      policy.isRetiredSystemDefinition(_definition(id: 'user-stock-portfolio')),
      isFalse,
    );
    expect(policy.isRetiredSystemId('asset-stock-portfolio-copy'), isFalse);
  });

  test('archives inactive legacy seed and permanently blocks restore/edit', () {
    final definition = _definition();
    expect(policy.shouldArchive(definition, _usage()), isTrue);
    expect(policy.canBuy(definition), isFalse);
    expect(policy.canRestore(definition), isFalse);
    expect(policy.canEdit(definition), isFalse);
  });

  test('open legacy position is sell-only until its quantity reaches zero', () {
    final definition = _definition();
    final open = _usage(openQuantity: 500);
    expect(policy.shouldArchive(definition, open), isFalse);
    expect(policy.canBuy(definition), isFalse);
    expect(policy.canSell(definition, open), isTrue);

    final closed = _usage(openQuantity: 0, linked: true);
    expect(policy.canSell(definition, closed), isFalse);
    expect(policy.shouldArchive(definition, closed), isTrue);
  });

  test('ordinary user definition with legacy display name is unaffected', () {
    final definition = _definition(id: 'user-created-stock');
    expect(policy.canBuy(definition), isTrue);
    expect(policy.canSell(definition, _usage()), isTrue);
    expect(policy.canRestore(definition), isTrue);
    expect(policy.canEdit(definition), isTrue);
  });
}

AssetDefinition _definition({
  String id = AssetDefinitionRetirementPolicy.retiredStockPortfolioId,
}) {
  return AssetDefinition(
    id: id,
    displayName: 'Stock Portfolio',
    kind: AssetKind.stock,
    symbol: 'STOCK',
    providerCode: null,
    providerSymbol: null,
    exchangeCode: null,
    currencyCode: 'IDR',
    unit: 'share',
    lotSize: 100,
    onlinePricingEnabled: false,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    deletedAt: null,
    version: 1,
    deviceId: 'test',
    syncStatus: 'local_only',
  );
}

AssetDefinitionUsageResult _usage({
  double openQuantity = 0,
  bool linked = false,
}) {
  final hasOpenPosition = openQuantity > 0;
  return AssetDefinitionUsageResult(
    hasLinkedTransactions: linked || hasOpenPosition,
    linkedTransactionCount: linked || hasOpenPosition ? 1 : 0,
    activeTransactionCount: linked || hasOpenPosition ? 1 : 0,
    openQuantity: openQuantity,
    hasOpenPosition: hasOpenPosition,
    canArchive: !hasOpenPosition,
    canEditIdentity: !linked && !hasOpenPosition,
    blockingReason: hasOpenPosition ? 'Open position.' : null,
  );
}
