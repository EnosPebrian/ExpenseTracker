import 'package:flutter/material.dart';

import '../../transactions/domain/entities/transaction.dart';

class AssetConversionController extends ChangeNotifier {
  AssetConversionController({
    required List<String> accounts,
    required List<String> assets,
  }) : accounts = accounts,
       assets = assets {
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
        'At least one measurable asset is required.',
      );
    }

    source = this.accounts.first;
    destination = this.assets.first;

    cashController.addListener(_handleInputChanged);
    quantityController.addListener(_handleInputChanged);
  }

  static const feeTreatments = <String>[
    'Capitalize into cost basis',
    'Record as separate expense',
  ];

  final List<String> accounts;
  final List<String> assets;

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

  bool get canSave => cash > 0 && quantity > 0;

  String get selectedAsset {
    return sellAsset ? source : destination;
  }

  String get unit {
    switch (selectedAsset) {
      case 'Gold Holdings':
        return 'gram';
      case 'Stock Portfolio':
        return 'share';
      case 'Bitcoin Wallet':
        return 'BTC';
      case 'Inventory':
        return 'unit';
      default:
        return 'unit';
    }
  }

  String get sourceLabel {
    return sellAsset ? 'From asset' : 'From account';
  }

  String get destinationLabel {
    return sellAsset ? 'To account' : 'To asset account';
  }

  String get cashLabel {
    return sellAsset ? 'Cash value received' : 'Cash paid';
  }

  String get quantityLabel {
    return sellAsset ? 'Quantity sold' : 'Quantity received';
  }

  List<String> get sourceOptions {
    return sellAsset ? assets : accounts;
  }

  List<String> get destinationOptions {
    return sellAsset ? accounts : assets;
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

    source = sellAsset ? assets.first : accounts.first;
    destination = sellAsset ? accounts.first : assets.first;

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
    if (!canSave) {
      throw StateError(
        'Cash value and quantity must both be greater than zero.',
      );
    }

    return Transaction(
      title: sellAsset ? '$source sale' : '$destination acquisition',
      category: 'Asset conversion',
      account: '$source -> $destination',
      date: transactionDate,
      amount: cash,
      type: TransactionType.assetConversion,
      quantity: quantity,
      unit: unit,
      unitPrice: unitPrice,
    );
  }

  void _handleInputChanged() {
    notifyListeners();
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
