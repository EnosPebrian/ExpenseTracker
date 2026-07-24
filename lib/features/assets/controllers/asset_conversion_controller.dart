import 'package:flutter/material.dart';

import '../../transactions/domain/entities/transaction.dart';
import '../domain/entities/asset_definition.dart';
import '../domain/entities/asset_kind.dart';

class AssetConversionController extends ChangeNotifier {
  AssetConversionController({
    required List<String> accounts,
    required List<AssetDefinition> assets,
  }) : accounts = List<String>.unmodifiable(accounts),
       assets = List<AssetDefinition>.unmodifiable(
         assets.where((asset) => !asset.isDeleted),
       ) {
    if (this.accounts.isEmpty) {
      throw ArgumentError.value(
        accounts,
        'accounts',
        'At least one financial account is required.',
      );
    }

    if (this.assets.isEmpty) {
      throw ArgumentError.value(
        assets,
        'assets',
        'At least one active measurable asset is required.',
      );
    }

    final optionLabels = <String>[];

    for (final asset in this.assets) {
      final validationErrors = asset.validate();

      if (validationErrors.isNotEmpty) {
        throw ArgumentError.value(asset, 'assets', validationErrors.join(' '));
      }

      final optionLabel = _optionLabel(asset);

      if (_assetsByOption.containsKey(optionLabel)) {
        throw ArgumentError.value(
          assets,
          'assets',
          'Asset selection labels must be unique. '
              'Duplicate label: $optionLabel.',
        );
      }

      _assetsByOption[optionLabel] = asset;
      optionLabels.add(optionLabel);
    }

    _assetOptions = List<String>.unmodifiable(optionLabels);

    source = this.accounts.first;
    destination = _assetOptions.first;

    cashController.addListener(_handleInputChanged);
    quantityController.addListener(_handleInputChanged);
  }

  static const feeTreatments = <String>[
    'Capitalize into cost basis',
    'Record as separate expense',
  ];

  final List<String> accounts;
  final List<AssetDefinition> assets;

  final Map<String, AssetDefinition> _assetsByOption = {};
  late final List<String> _assetOptions;

  final TextEditingController cashController = TextEditingController(
    text: '50.000.000',
  );

  final TextEditingController quantityController = TextEditingController(
    text: '20',
  );

  bool sellAsset = false;

  late String source;
  late String destination;

  String feeTreatment = feeTreatments.first;
  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();

  int get cash {
    return int.tryParse(
          cashController.text.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;
  }

  double get quantity {
    final normalized = quantityController.text.trim().replaceAll(',', '.');

    return double.tryParse(normalized) ?? 0;
  }

  int get unitPrice {
    if (quantity <= 0) {
      return 0;
    }

    return (cash / quantity).round();
  }

  String get selectedAssetOption {
    return sellAsset ? source : destination;
  }

  AssetDefinition get selectedAssetDefinition {
    final definition = _assetsByOption[selectedAssetOption];

    if (definition == null) {
      throw StateError('The selected asset definition could not be found.');
    }

    return definition;
  }

  String get unit {
    return selectedAssetDefinition.normalizedUnit;
  }

  String get currencyCode {
    return selectedAssetDefinition.normalizedCurrencyCode;
  }

  bool get isForeignCurrency {
    return selectedAssetDefinition.kind == AssetKind.foreignCurrency;
  }

  String get currencySymbol {
    return selectedAssetDefinition.normalizedSymbol ?? unit.toUpperCase();
  }

  bool get supportsSelectedCurrency {
    return currencyCode == 'IDR';
  }

  bool get canSave {
    return cash > 0 &&
        quantity > 0 &&
        supportsSelectedCurrency &&
        !selectedAssetDefinition.isDeleted;
  }

  String get sourceLabel {
    return sellAsset ? 'From asset' : 'From account';
  }

  String get destinationLabel {
    return sellAsset ? 'To account' : 'To asset';
  }

  String get cashLabel {
    if (isForeignCurrency) {
      return sellAsset ? 'IDR received' : 'IDR paid';
    }

    return sellAsset ? 'Cash value received' : 'Cash paid';
  }

  String get quantityLabel {
    if (isForeignCurrency) {
      return sellAsset ? '$currencySymbol sold' : '$currencySymbol received';
    }

    return sellAsset ? 'Quantity sold' : 'Quantity received';
  }

  String get calculatedRateLabel {
    if (!isForeignCurrency) {
      return 'Average unit value';
    }

    return 'Calculated rate: Rp ${_formatInteger(unitPrice)} per '
        '$currencySymbol';
  }

  List<String> get sourceOptions {
    return sellAsset ? _assetOptions : accounts;
  }

  List<String> get destinationOptions {
    return sellAsset ? accounts : _assetOptions;
  }

  DateTime get transactionDate {
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
  }

  void setSellAsset(bool value) {
    if (sellAsset == value) {
      return;
    }

    sellAsset = value;

    source = sellAsset ? _assetOptions.first : accounts.first;
    destination = sellAsset ? accounts.first : _assetOptions.first;

    notifyListeners();
  }

  void setSource(String value) {
    if (!sourceOptions.contains(value) || source == value) {
      return;
    }

    source = value;
    notifyListeners();
  }

  void setDestination(String value) {
    if (!destinationOptions.contains(value) || destination == value) {
      return;
    }

    destination = value;
    notifyListeners();
  }

  void setFeeTreatment(String value) {
    if (!feeTreatments.contains(value) || feeTreatment == value) {
      return;
    }

    feeTreatment = value;
    notifyListeners();
  }

  void setDate(DateTime value) {
    selectedDate = DateTime(value.year, value.month, value.day);

    notifyListeners();
  }

  void setTime(TimeOfDay value) {
    selectedTime = value;
    notifyListeners();
  }

  Transaction buildTransaction() {
    if (selectedAssetDefinition.isDeleted) {
      throw StateError('The selected asset definition is no longer active.');
    }

    if (!supportsSelectedCurrency) {
      throw StateError(
        'Asset Conversion currently supports IDR-valued assets only. '
        '$currencyCode assets require currency conversion support.',
      );
    }

    if (!canSave) {
      throw StateError(
        'Cash value and quantity must both be greater than zero.',
      );
    }

    final asset = selectedAssetDefinition;
    final symbol = asset.normalizedSymbol;

    final titleLabel = symbol ?? asset.displayName.trim();

    return Transaction(
      title: sellAsset ? '$titleLabel sale' : '$titleLabel acquisition',
      category: 'Asset conversion',
      account: '$source -> $destination',
      date: transactionDate,
      amount: cash,
      type: TransactionType.assetConversion,
      quantity: quantity,
      unit: asset.normalizedUnit,
      unitPrice: unitPrice,
      assetDefinitionId: asset.id,
      assetName: asset.displayName.trim(),
      assetSymbol: symbol,
      assetAction: sellAsset ? AssetAction.sell : AssetAction.buy,
    );
  }

  void _handleInputChanged() {
    notifyListeners();
  }

  static String _optionLabel(AssetDefinition definition) {
    final symbol = definition.normalizedSymbol;

    if (symbol == null) {
      return definition.displayName.trim();
    }

    return '${definition.displayName.trim()} ($symbol)';
  }

  static String _formatInteger(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];

    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }

    final prefix = value < 0 ? '-' : '';
    return '$prefix${groups.join('.')}';
  }

  @override
  void dispose() {
    cashController.removeListener(_handleInputChanged);
    quantityController.removeListener(_handleInputChanged);

    cashController.dispose();
    quantityController.dispose();

    super.dispose();
  }
}
