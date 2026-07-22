import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/local_store.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_market_price.dart';

void main() {
  test('asset market price survives SQLite round trip', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pilgrim-asset-price-test-',
    );

    final store = LocalStore(
      databasePath: p.join(directory.path, 'asset-prices.db'),
    );

    addTearDown(() async {
      await store.close();

      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    await store.initialize();

    final price = AssetMarketPrice.manual(
      assetKey: 'BBCA',
      symbol: 'BBCA',
      price: 9250,
      unit: 'share',
      quotedAt: DateTime.utc(2026, 7, 21),
    );

    await store.upsertAssetMarketPrice(price.toRecord());

    final records = await store.getAssetMarketPrices();

    expect(records, hasLength(1));

    final loaded = AssetMarketPrice.fromRecord(records.single);

    expect(loaded.assetKey, 'BBCA');
    expect(loaded.symbol, 'BBCA');
    expect(loaded.roundedPrice, 9250);
    expect(loaded.currencyCode, 'IDR');
    expect(loaded.unit, 'share');
    expect(loaded.isManual, isTrue);
  });
}
