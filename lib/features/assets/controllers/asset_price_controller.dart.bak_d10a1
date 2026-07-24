import 'package:flutter/foundation.dart';

import '../../../core/database/local_store.dart';
import '../domain/entities/asset_market_price.dart';
import '../domain/entities/asset_portfolio.dart';
import '../domain/entities/market_quote.dart';
import '../domain/repositories/asset_price_repository.dart';

class AssetPriceController extends ChangeNotifier {
  AssetPriceController({
    required LocalStore store,
    AssetPriceRepository? repository,
  }) : this._(store, repository);

  AssetPriceController._(this._store, this._repository);

  final LocalStore _store;
  final AssetPriceRepository? _repository;

  final Map<String, AssetMarketPrice> _pricesByKey = {};
  final Set<String> _refreshingKeys = {};

  bool isLoading = false;
  bool isRefreshingAll = false;
  String? error;

  bool get hasOnlineProvider => _repository != null;

  List<AssetMarketPrice> get prices {
    final values = _pricesByKey.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

    return List<AssetMarketPrice>.unmodifiable(values);
  }

  bool isRefreshing(String assetKey) {
    return _refreshingKeys.contains(_normalizeKey(assetKey));
  }

  bool canRefreshHolding(AssetHolding holding) {
    if (!holding.onlinePricingEnabled ||
        !_hasSupportedProviderConfiguration(holding)) {
      return false;
    }

    return switch (holding.kind) {
      AssetKind.gold => true,
      AssetKind.stock => holding.quoteSymbol != null,
      AssetKind.crypto || AssetKind.inventory || AssetKind.other => false,
    };
  }

  Future<void> load() async {
    if (isLoading) {
      return;
    }

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final records = await _store.getAssetMarketPrices();

      _pricesByKey.clear();

      for (final record in records) {
        final price = AssetMarketPrice.fromRecord(record);

        _pricesByKey[_normalizeKey(price.assetKey)] = price;
      }
    } catch (exception) {
      error = 'Could not load cached asset prices. $exception';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshHolding(AssetHolding holding) async {
    final repository = _repository;

    if (repository == null) {
      error =
          'Online pricing is unavailable because no Alpha Vantage API key '
          'was provided.';
      notifyListeners();
      return;
    }

    if (!canRefreshHolding(holding)) {
      if (!holding.onlinePricingEnabled) {
        error = 'Online pricing is disabled for ${holding.name}.';
      } else if (!_hasSupportedProviderConfiguration(holding)) {
        final providerCode = holding.normalizedProviderCode;

        error = providerCode == null
            ? 'No online pricing provider is configured for ${holding.name}.'
            : 'Online pricing provider $providerCode is not supported.';
      } else if (holding.kind == AssetKind.stock &&
          holding.quoteSymbol == null) {
        error = 'This stock holding does not have a provider or ticker symbol.';
      } else {
        error = 'Online pricing is not supported for ${holding.name}.';
      }

      notifyListeners();
      return;
    }

    final normalizedKey = _normalizeKey(holding.assetKey);

    if (_refreshingKeys.contains(normalizedKey)) {
      return;
    }

    _refreshingKeys.add(normalizedKey);
    error = null;
    notifyListeners();

    try {
      await _fetchAndSave(repository: repository, holding: holding);
    } catch (exception) {
      error = 'Could not refresh ${holding.name}. $exception';
    } finally {
      _refreshingKeys.remove(normalizedKey);
      notifyListeners();
    }
  }

  Future<void> refreshAll(Iterable<AssetHolding> holdings) async {
    final repository = _repository;

    if (repository == null) {
      error =
          'Online pricing is unavailable because no Alpha Vantage API key '
          'was provided.';
      notifyListeners();
      return;
    }

    if (isRefreshingAll) {
      return;
    }

    final refreshable = holdings
        .where(canRefreshHolding)
        .toList(growable: false);

    if (refreshable.isEmpty) {
      error =
          'No holdings with enabled and supported online pricing are available.';
      notifyListeners();
      return;
    }

    isRefreshingAll = true;
    error = null;
    notifyListeners();

    final failures = <String>[];

    try {
      for (final holding in refreshable) {
        final normalizedKey = _normalizeKey(holding.assetKey);

        _refreshingKeys.add(normalizedKey);
        notifyListeners();

        try {
          await _fetchAndSave(repository: repository, holding: holding);
        } catch (exception) {
          failures.add('${holding.name}: $exception');
        } finally {
          _refreshingKeys.remove(normalizedKey);
          notifyListeners();
        }
      }

      if (failures.isNotEmpty) {
        error = 'Some prices could not be refreshed. ${failures.join(' | ')}';
      }
    } finally {
      isRefreshingAll = false;
      notifyListeners();
    }
  }

  Future<void> setManualPrice({
    required AssetHolding holding,
    required int price,
  }) async {
    if (price <= 0) {
      throw ArgumentError.value(
        price,
        'price',
        'The market price must be greater than zero.',
      );
    }

    final marketPrice = AssetMarketPrice.manual(
      assetKey: holding.assetKey,
      symbol: holding.normalizedSymbol,
      price: price,
      currencyCode: holding.normalizedCurrencyCode,
      unit: holding.normalizedUnit,
    );

    await _save(marketPrice);

    error = null;
    notifyListeners();
  }

  Future<void> clearError() async {
    if (error == null) {
      return;
    }

    error = null;
    notifyListeners();
  }

  Future<void> _fetchAndSave({
    required AssetPriceRepository repository,
    required AssetHolding holding,
  }) async {
    late final MarketQuote quote;

    switch (holding.kind) {
      case AssetKind.gold:
        quote = await repository.fetchGoldPriceInIdrPerGram();

      case AssetKind.stock:
        final quoteSymbol = holding.quoteSymbol;

        if (quoteSymbol == null) {
          throw StateError(
            'A provider or ticker symbol is required for online pricing.',
          );
        }

        quote = await repository.fetchStockQuote(
          symbol: quoteSymbol,
          currencyCode: holding.normalizedCurrencyCode,
          minorUnitScale: _minorUnitScaleForCurrency(
            holding.normalizedCurrencyCode,
          ),
        );

      case AssetKind.crypto:
      case AssetKind.inventory:
      case AssetKind.other:
        throw StateError(
          'Online pricing is not supported for ${holding.name}.',
        );
    }

    _validateQuote(holding: holding, quote: quote);

    await _save(
      AssetMarketPrice.fromQuote(assetKey: holding.assetKey, quote: quote),
    );
  }

  void _validateQuote({
    required AssetHolding holding,
    required MarketQuote quote,
  }) {
    if (quote.priceMinor <= 0) {
      throw StateError('The provider returned a non-positive market price.');
    }

    if (quote.minorUnitScale <= 0) {
      throw StateError('The provider returned an invalid minor-unit scale.');
    }

    final expectedCurrency = holding.normalizedCurrencyCode;
    final returnedCurrency = quote.currencyCode.trim().toUpperCase();

    if (returnedCurrency != expectedCurrency) {
      throw StateError(
        'Currency mismatch: expected $expectedCurrency but '
        'received $returnedCurrency.',
      );
    }

    final expectedUnit = holding.normalizedUnit;
    final returnedUnit = quote.unit.trim().toLowerCase();

    if (returnedUnit != expectedUnit) {
      throw StateError(
        'Unit mismatch: expected $expectedUnit but '
        'received $returnedUnit.',
      );
    }

    final expectedSymbol = switch (holding.kind) {
      AssetKind.gold => holding.quoteSymbol ?? 'XAU',
      AssetKind.stock => holding.quoteSymbol,
      AssetKind.crypto || AssetKind.inventory || AssetKind.other => null,
    };

    if (expectedSymbol != null) {
      final normalizedExpected = expectedSymbol.trim().toUpperCase();
      final normalizedReturned = quote.symbol.trim().toUpperCase();

      if (normalizedReturned != normalizedExpected) {
        throw StateError(
          'Symbol mismatch: expected $normalizedExpected but '
          'received $normalizedReturned.',
        );
      }
    }
  }

  bool _hasSupportedProviderConfiguration(AssetHolding holding) {
    // Legacy holdings predate provider configuration and may continue using
    // the application's currently configured repository.
    if (holding.assetDefinitionId == null) {
      return true;
    }

    return holding.normalizedProviderCode == 'ALPHA_VANTAGE';
  }

  int _minorUnitScaleForCurrency(String currencyCode) {
    return switch (currencyCode.trim().toUpperCase()) {
      'IDR' || 'JPY' || 'KRW' => 1,
      _ => 100,
    };
  }

  Future<void> _save(AssetMarketPrice price) async {
    await _store.upsertAssetMarketPrice(price.toRecord());

    _pricesByKey[_normalizeKey(price.assetKey)] = price;
  }

  String _normalizeKey(String value) {
    return value.trim().toLowerCase();
  }
}
