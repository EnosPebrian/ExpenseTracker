import 'package:flutter/material.dart';

import '../../transactions/domain/entities/transaction.dart';
import '../../transactions/domain/entities/asset_market_reference_source.dart';
import '../domain/entities/asset_definition.dart';
import '../domain/entities/asset_kind.dart';
import '../domain/entities/asset_market_price.dart';
import '../domain/services/asset_execution_analysis.dart';
import '../domain/services/asset_numeric_policy.dart';
import '../domain/services/asset_definition_retirement_policy.dart';
import '../domain/services/asset_definition_usage_policy.dart';
import '../domain/services/asset_stock_lot_policy.dart';
import '../domain/services/asset_trade_validator.dart';
import '../domain/services/asset_transaction_sequence_validator.dart';
import 'asset_execution_reference_controller.dart';

class AssetConversionController extends ChangeNotifier {
  AssetConversionController({
    required List<String> accounts,
    required List<AssetDefinition> assets,
    List<AssetMarketPrice> marketPrices = const [],
    this.existingTransactionsProvider,
    this.sequenceValidator = const AssetTransactionSequenceValidator(),
    this.retirementPolicy = const AssetDefinitionRetirementPolicy(),
    this.usagePolicy = const AssetDefinitionUsagePolicy(),
    AssetTradeValidator? tradeValidator,
  }) : accounts = List<String>.unmodifiable(accounts),
       marketPrices = List<AssetMarketPrice>.unmodifiable(marketPrices),
       tradeValidator =
           tradeValidator ??
           AssetTradeValidator(sequenceValidator: sequenceValidator) {
    if (this.accounts.isEmpty) {
      throw ArgumentError.value(
        accounts,
        'accounts',
        'At least one financial account is required.',
      );
    }

    final activeAssets = assets.where((asset) => !asset.isDeleted).toList();
    final transactions = existingTransactionsProvider?.call() ?? const [];
    final selectableAssets = <AssetDefinition>[];
    final buyOptionLabels = <String>[];
    final sellOptionLabels = <String>[];

    for (final asset in activeAssets) {
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
      final usage = usagePolicy.analyze(
        definition: asset,
        transactions: transactions,
      );
      final canBuy = retirementPolicy.canBuy(asset);
      final canSell = retirementPolicy.canSell(asset, usage);
      if (canBuy || canSell) selectableAssets.add(asset);
      if (canBuy) buyOptionLabels.add(optionLabel);
      if (canSell) sellOptionLabels.add(optionLabel);
    }

    if (buyOptionLabels.isEmpty) {
      throw ArgumentError.value(
        assets,
        'assets',
        'At least one active measurable asset available for purchase is required.',
      );
    }

    this.assets = List<AssetDefinition>.unmodifiable(selectableAssets);
    _buyAssetOptions = List<String>.unmodifiable(buyOptionLabels);
    _sellAssetOptions = List<String>.unmodifiable(sellOptionLabels);

    source = this.accounts.first;
    destination = _buyAssetOptions.first;

    executionReference = AssetExecutionReferenceController(
      definitionProvider: () => selectedAssetDefinition,
      marketPrices: this.marketPrices,
      onChanged: _handleInputChanged,
    );

    cashController.addListener(_handleInputChanged);
    quantityController.addListener(_handleInputChanged);
    feeController.addListener(_handleFeeInputChanged);
  }

  final List<String> accounts;
  late final List<AssetDefinition> assets;
  final List<AssetMarketPrice> marketPrices;
  final List<Transaction> Function()? existingTransactionsProvider;
  final AssetTransactionSequenceValidator sequenceValidator;
  final AssetTradeValidator tradeValidator;
  final AssetDefinitionRetirementPolicy retirementPolicy;
  final AssetDefinitionUsagePolicy usagePolicy;
  late final AssetExecutionReferenceController executionReference;

  final Map<String, AssetDefinition> _assetsByOption = {};
  late final List<String> _buyAssetOptions;
  late final List<String> _sellAssetOptions;

  final TextEditingController cashController = TextEditingController(
    text: '50.000.000',
  );

  final TextEditingController quantityController = TextEditingController(
    text: '20',
  );

  final TextEditingController feeController = TextEditingController();

  TextEditingController get referencePriceController =>
      executionReference.priceController;
  AssetMarketReferenceSource? get marketReferenceSource =>
      executionReference.source;
  DateTime? get marketReferenceQuotedAt => executionReference.quotedAt;

  bool sellAsset = false;

  late String source;
  late String destination;

  AssetFeeTreatment feeTreatment = AssetFeeTreatment.none;
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
    if (cash <= 0 || !quantityValidation.isValid) {
      return 0;
    }

    return AssetNumericPolicy.deriveUnitPrice(amount: cash, quantity: quantity);
  }

  int? get marketReferenceUnitPrice => executionReference.unitPrice;

  AssetMarketPrice? get latestCompatibleMarketPrice =>
      executionReference.latestCompatible;

  String? get marketReferenceValidationMessage =>
      executionReference.validationMessage;

  AssetExecutionAnalysisResult? get executionAnalysis {
    final reference = marketReferenceUnitPrice;
    if (reference == null || unitPrice <= 0 || !quantityValidation.isValid) {
      return null;
    }
    return AssetExecutionAnalysis.calculate(
      action: sellAsset ? AssetAction.sell : AssetAction.buy,
      quantity: quantity,
      executionUnitPrice: unitPrice,
      referenceUnitPrice: reference,
    );
  }

  void useManualMarketReference() => executionReference.useManual();

  bool useLatestCachedMarketReference() => executionReference.useLatestCached();

  void clearMarketReference() => executionReference.clear();

  AssetQuantityValidationResult get quantityValidation =>
      AssetNumericPolicy.validateQuantity(
        quantity: quantity,
        kind: selectedAssetDefinition.kind,
        symbol: selectedAssetDefinition.normalizedSymbol,
      );

  String? get quantityValidationMessage => quantityValidation.message;

  int get quantityDecimalPlaces =>
      AssetNumericPolicy.quantityDecimalPlacesFor(selectedAssetDefinition.kind);

  bool get supportsDecimalQuantity =>
      selectedAssetDefinition.kind != AssetKind.stock;

  String get quantityPrecisionHint =>
      selectedAssetDefinition.kind == AssetKind.stock
      ? 'Enter whole shares.'
      : 'Supports up to $quantityDecimalPlaces decimal places.';

  int get lotSize => selectedAssetDefinition.lotSize;

  double get requestedLots => lotSize > 0 ? quantity / lotSize : 0;

  int get feeAmount {
    return int.tryParse(feeController.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
        0;
  }

  int get grossTradeAmount => cash;

  int get totalCashPaid {
    return cash + (feeTreatment == AssetFeeTreatment.none ? 0 : feeAmount);
  }

  int get netProceeds {
    return cash - (feeTreatment == AssetFeeTreatment.none ? 0 : feeAmount);
  }

  int get costBasisAdded =>
      cash +
      (feeTreatment == AssetFeeTreatment.capitalizeIntoCostBasis
          ? feeAmount
          : 0);

  int get cashEffectUnitPrice {
    if (!quantityValidation.isValid) return 0;
    final amount = sellAsset ? netProceeds : totalCashPaid;
    if (amount <= 0) return 0;
    return AssetNumericPolicy.deriveUnitPrice(
      amount: amount,
      quantity: quantity,
    );
  }

  bool get recordsFeeAsExpense =>
      feeTreatment == AssetFeeTreatment.recordAsSeparateExpense;

  List<AssetFeeTreatment> get feeTreatmentOptions => [
    AssetFeeTreatment.none,
    sellAsset
        ? AssetFeeTreatment.deductFromSaleProceeds
        : AssetFeeTreatment.capitalizeIntoCostBasis,
    AssetFeeTreatment.recordAsSeparateExpense,
  ];

  String feeTreatmentLabel(AssetFeeTreatment treatment) {
    return switch (treatment) {
      AssetFeeTreatment.none => 'No fee',
      AssetFeeTreatment.capitalizeIntoCostBasis => 'Add fee to cost basis',
      AssetFeeTreatment.deductFromSaleProceeds => 'Deduct fee from proceeds',
      AssetFeeTreatment.recordAsSeparateExpense => 'Record fee as expense',
    };
  }

  String? get feeValidationMessage {
    if (feeAmount == 0) {
      return null;
    }

    if (feeTreatment == AssetFeeTreatment.none) {
      return 'Choose how to handle the transaction fee.';
    }

    if (!feeTreatmentOptions.contains(feeTreatment)) {
      return sellAsset
          ? 'Sell fees can only be deducted from proceeds or recorded as an expense.'
          : 'Buy fees can only be added to cost basis or recorded as an expense.';
    }

    if (sellAsset &&
        feeTreatment == AssetFeeTreatment.deductFromSaleProceeds &&
        feeAmount >= cash) {
      return 'The transaction fee must be less than the gross sale amount.';
    }

    return null;
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

  bool get isLegacyCloseOnly {
    return retirementPolicy.isRetiredSystemDefinition(selectedAssetDefinition);
  }

  String get currencySymbol {
    return selectedAssetDefinition.normalizedSymbol ?? unit.toUpperCase();
  }

  bool get supportsSelectedCurrency {
    return currencyCode == 'IDR';
  }

  bool get canSave =>
      _hasValidInputs &&
      (tradeValidation?.isValid ?? true) &&
      (lotValidation?.isValid ?? true);

  AssetTradeValidationResult? get tradeValidation {
    if (existingTransactionsProvider == null || !quantityValidation.isValid) {
      return null;
    }

    return tradeValidator.validateCandidate(
      existingTransactions: existingTransactionsProvider!(),
      candidate: _buildCandidate(),
      definition: selectedAssetDefinition,
    );
  }

  AssetStockLotValidationResult? get lotValidation {
    if (selectedAssetDefinition.kind != AssetKind.stock ||
        !quantityValidation.isValid) {
      return null;
    }

    final coordinated = tradeValidation?.lotValidation;
    if (coordinated != null) {
      return coordinated;
    }

    return tradeValidator.stockLotPolicy.evaluate(
      definition: selectedAssetDefinition,
      action: sellAsset ? AssetAction.sell : AssetAction.buy,
      requestedShares: quantity,
      availableShares: sellAsset ? quantity : 0,
    );
  }

  String? get lotValidationMessage => lotValidation?.message;

  AssetSequenceValidationResult? get saleValidation {
    if (!sellAsset ||
        existingTransactionsProvider == null ||
        !quantityValidation.isValid) {
      return null;
    }

    return tradeValidation?.sequenceValidation;
  }

  double? get availableQuantity => saleValidation?.availableQuantity;

  String? get oversellMessage {
    final result = saleValidation;
    return result != null && !result.isValid ? result.message : null;
  }

  String get sourceLabel {
    return sellAsset ? 'From asset' : 'From account';
  }

  String get destinationLabel {
    return sellAsset ? 'To account' : 'To asset';
  }

  String get cashLabel {
    return sellAsset ? 'Gross proceeds' : 'Trade amount';
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
    return sellAsset ? _sellAssetOptions : accounts;
  }

  List<String> get destinationOptions {
    return sellAsset ? accounts : _buyAssetOptions;
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

    if (!feeTreatmentOptions.contains(feeTreatment)) {
      feeTreatment = AssetFeeTreatment.none;
    }

    source = sellAsset ? _sellAssetOptions.first : accounts.first;
    destination = sellAsset ? accounts.first : _buyAssetOptions.first;

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

  void setFeeTreatment(AssetFeeTreatment value) {
    if (!feeTreatmentOptions.contains(value) || feeTreatment == value) {
      return;
    }

    feeTreatment = value;

    if (value == AssetFeeTreatment.none) {
      feeController.clear();
    }

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

    if (!sellAsset && !retirementPolicy.canBuy(selectedAssetDefinition)) {
      throw StateError(
        'This legacy stock definition can only be used to close its existing '
        'holding.',
      );
    }

    if (!supportsSelectedCurrency) {
      throw StateError(
        'Asset Conversion currently supports IDR-valued assets only. '
        '$currencyCode assets require currency conversion support.',
      );
    }

    final referenceError = marketReferenceValidationMessage;
    if (referenceError != null) {
      throw StateError(referenceError);
    }

    if (!_hasValidInputs) {
      final quantityError = quantityValidationMessage;

      if (quantityError != null) {
        throw StateError(quantityError);
      }

      final feeError = feeValidationMessage;

      if (feeError != null) {
        throw StateError(feeError);
      }

      throw StateError(
        'Cash value and quantity must both be greater than zero.',
      );
    }

    final lotResult = lotValidation;
    if (lotResult != null && !lotResult.isValid) {
      throw StateError(lotResult.message ?? 'The stock lot is invalid.');
    }

    final validation = tradeValidation;

    if (validation != null && !validation.isValid) {
      throw StateError(validation.message ?? 'The asset trade is invalid.');
    }

    return _buildCandidate();
  }

  bool get _hasValidInputs {
    return cash > 0 &&
        quantityValidation.isValid &&
        supportsSelectedCurrency &&
        !selectedAssetDefinition.isDeleted &&
        feeValidationMessage == null &&
        marketReferenceValidationMessage == null;
  }

  Transaction _buildCandidate({double? quantityOverride}) {
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
      quantity: quantityOverride ?? quantity,
      unit: asset.normalizedUnit,
      unitPrice: unitPrice,
      assetDefinitionId: asset.id,
      assetName: asset.displayName.trim(),
      assetSymbol: symbol,
      assetAction: sellAsset ? AssetAction.sell : AssetAction.buy,
      feeAmount: feeAmount,
      feeTreatment: feeTreatment,
      marketReferenceUnitPrice: marketReferenceUnitPrice,
      marketReferenceCurrencyCode: marketReferenceSource == null
          ? null
          : selectedAssetDefinition.normalizedCurrencyCode,
      marketReferenceUnit: marketReferenceSource == null
          ? null
          : selectedAssetDefinition.normalizedUnit,
      marketReferenceSource: marketReferenceSource,
      marketReferenceQuotedAt: marketReferenceQuotedAt,
    );
  }

  void _handleInputChanged() {
    notifyListeners();
  }

  void _handleFeeInputChanged() {
    if (feeAmount == 0) {
      feeTreatment = AssetFeeTreatment.none;
    } else if (feeTreatment == AssetFeeTreatment.none) {
      feeTreatment = sellAsset
          ? AssetFeeTreatment.deductFromSaleProceeds
          : AssetFeeTreatment.capitalizeIntoCostBasis;
    }

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
    feeController.removeListener(_handleFeeInputChanged);

    cashController.dispose();
    quantityController.dispose();
    feeController.dispose();
    executionReference.dispose();

    super.dispose();
  }
}
