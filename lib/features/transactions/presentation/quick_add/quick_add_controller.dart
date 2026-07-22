import 'package:flutter/material.dart';

import '../../../assets/controllers/asset_conversion_controller.dart';
import '../../domain/entities/transaction.dart';
import '../controllers/transaction_controller.dart';
import '../../../assets/domain/entities/asset_definition.dart';
import '../../../assets/domain/entities/asset_kind.dart';

class QuickAddConfig {
  const QuickAddConfig({
    required this.accounts,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.projects,
    this.assets = const [
      'Gold Holdings',
      'Stock Portfolio',
      'Bitcoin Wallet',
      'Inventory',
    ],
    this.assetDefinitions = const [],
    this.defaultProject = 'Life',
    this.defaultAccount,
    this.defaultExpenseCategory,
    this.defaultIncomeCategory,
    this.projectShortcuts,
    this.accountShortcuts,
    this.expenseCategoryShortcuts,
    this.incomeCategoryShortcuts,
  });

  final List<String> accounts;
  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final List<String> projects;

  /// Legacy asset-name options retained temporarily for compatibility.
  ///
  /// Production application composition should provide [assetDefinitions].
  final List<String> assets;

  /// Concrete measurable or tradable assets used by Asset Conversion.
  final List<AssetDefinition> assetDefinitions;

  final String defaultProject;
  final String? defaultAccount;
  final String? defaultExpenseCategory;
  final String? defaultIncomeCategory;

  final List<String>? projectShortcuts;
  final List<String>? accountShortcuts;
  final List<String>? expenseCategoryShortcuts;
  final List<String>? incomeCategoryShortcuts;

  List<String> choices(List<String> configured, String? selected) {
    final values = <String>[];
    final candidates = [...configured];

    if (selected != null) {
      candidates.add(selected);
    }

    for (final value in candidates) {
      if (value.isNotEmpty && !values.contains(value)) {
        values.add(value);
      }
    }

    return values;
  }
}

class QuickAddController extends ChangeNotifier {
  QuickAddController({required this.transactions, required this.config})
    : type = TransactionType.expense,
      project = config.projects.contains(config.defaultProject)
          ? config.defaultProject
          : null,
      account = config.accounts.contains(config.defaultAccount)
          ? config.defaultAccount!
          : config.accounts.first,
      toAccount = config.accounts.length > 1 ? config.accounts[1] : null,
      category =
          config.defaultExpenseCategory != null &&
              config.expenseCategories.contains(config.defaultExpenseCategory)
          ? config.defaultExpenseCategory!
          : config.expenseCategories.first,
      date = DateTime.now(),
      time = TimeOfDay.now() {
    assetConversion = AssetConversionController(
      accounts: config.accounts,
      assets: _resolveAssetDefinitions(config),
    );

    // The dedicated Asset Conversion screen has demo defaults.
    // Quick Add should begin empty.
    assetConversion.cashController.clear();
    assetConversion.quantityController.clear();

    assetConversion.addListener(_handleAssetConversionChanged);
  }

  final TransactionController transactions;
  final QuickAddConfig config;

  late final AssetConversionController assetConversion;

  TransactionType type;
  String? project;
  String account;
  String? toAccount;
  String category;
  DateTime date;
  TimeOfDay time;

  String amountText = '';
  String description = '';

  bool saving = false;
  String? error;

  bool get isAssetConversion {
    return type == TransactionType.assetConversion;
  }

  List<String> get categories {
    return type == TransactionType.income
        ? config.incomeCategories
        : config.expenseCategories;
  }

  List<String> get projectOptions {
    return ['No project', ...config.projects];
  }

  void setType(TransactionType value) {
    if (type == value) {
      return;
    }

    type = value;
    error = null;

    if (type == TransactionType.expense || type == TransactionType.income) {
      final options = categories;

      final preferred = type == TransactionType.income
          ? config.defaultIncomeCategory
          : config.defaultExpenseCategory;

      category = preferred != null && options.contains(preferred)
          ? preferred
          : options.first;
    }

    if (type == TransactionType.transfer && toAccount == account) {
      toAccount = _findDifferentAccount(account);
    }

    if (isAssetConversion) {
      _synchronizeAssetCash();
    }

    notifyListeners();
  }

  void setAmountText(String value) {
    amountText = value;

    if (isAssetConversion) {
      _synchronizeAssetCash();
    }

    if (error != null) {
      error = null;
    }

    notifyListeners();
  }

  void setProject(String value) {
    project = value == 'No project' ? null : value;

    notifyListeners();
  }

  void setAccount(String value) {
    account = value;

    if (type == TransactionType.transfer && toAccount == value) {
      toAccount = _findDifferentAccount(value);
    }

    notifyListeners();
  }

  void setToAccount(String value) {
    toAccount = value;
    notifyListeners();
  }

  void setCategory(String value) {
    category = value;
    notifyListeners();
  }

  void setDate(DateTime value) {
    date = value;
    notifyListeners();
  }

  void setTime(TimeOfDay value) {
    time = value;
    notifyListeners();
  }

  Future<bool> save() async {
    final amount = int.tryParse(amountText.replaceAll(RegExp(r'[^0-9]'), ''));

    if (amount == null || amount <= 0) {
      error = 'Enter an amount greater than zero.';
      notifyListeners();
      return false;
    }

    if (type == TransactionType.transfer &&
        (toAccount == null || toAccount == account)) {
      error = 'Choose different source and destination accounts.';
      notifyListeners();
      return false;
    }

    if (isAssetConversion) {
      _synchronizeAssetCash();
      if (!assetConversion.supportsSelectedCurrency) {
        error =
            'Asset Conversion currently supports IDR-valued assets only. '
            '${assetConversion.currencyCode} assets require currency '
            'conversion support.';
        notifyListeners();
        return false;
      }
      if (assetConversion.quantity <= 0) {
        error = 'Enter an asset quantity greater than zero.';
        notifyListeners();
        return false;
      }

      if (assetConversion.source == assetConversion.destination) {
        error = 'Choose different source and destination accounts.';
        notifyListeners();
        return false;
      }
    }

    saving = true;
    error = null;
    notifyListeners();

    try {
      final transactionDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      final transaction = isAssetConversion
          ? _buildAssetConversionTransaction(
              amount: amount,
              transactionDate: transactionDate,
            )
          : _buildOrdinaryTransaction(
              amount: amount,
              transactionDate: transactionDate,
            );

      await transactions.createTransaction(transaction);

      return true;
    } catch (exception) {
      error = exception.toString();
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Transaction _buildOrdinaryTransaction({
    required int amount,
    required DateTime transactionDate,
  }) {
    return Transaction(
      projectId: project == null ? null : _projectId(project!),
      title: description.trim().isEmpty
          ? 'New transaction'
          : description.trim(),
      category: type == TransactionType.transfer ? 'Transfer' : category,
      account: type == TransactionType.transfer
          ? '$account -> $toAccount'
          : account,
      date: transactionDate,
      amount: amount,
      type: type,
    );
  }

  Transaction _buildAssetConversionTransaction({
    required int amount,
    required DateTime transactionDate,
  }) {
    final conversion = assetConversion;
    final asset = conversion.selectedAssetDefinition;

    final titleLabel = asset.normalizedSymbol ?? asset.displayName.trim();

    final generatedTitle = conversion.sellAsset
        ? '$titleLabel sale'
        : '$titleLabel acquisition';

    return Transaction(
      projectId: project == null ? null : _projectId(project!),
      title: description.trim().isEmpty ? generatedTitle : description.trim(),
      category: 'Asset conversion',
      account: '${conversion.source} -> ${conversion.destination}',
      date: transactionDate,
      amount: amount,
      type: TransactionType.assetConversion,
      quantity: conversion.quantity,
      unit: asset.normalizedUnit,
      unitPrice: conversion.unitPrice,
      assetDefinitionId: asset.id,
      assetName: asset.displayName.trim(),
      assetSymbol: asset.normalizedSymbol,
      assetAction: conversion.sellAsset ? AssetAction.sell : AssetAction.buy,
    );
  }

  String? _findDifferentAccount(String currentAccount) {
    for (final candidate in config.accounts) {
      if (candidate != currentAccount) {
        return candidate;
      }
    }

    return null;
  }

  void _synchronizeAssetCash() {
    if (assetConversion.cashController.text == amountText) {
      return;
    }

    assetConversion.cashController.value = TextEditingValue(
      text: amountText,
      selection: TextSelection.collapsed(offset: amountText.length),
    );
  }

  void _handleAssetConversionChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    assetConversion.removeListener(_handleAssetConversionChanged);

    assetConversion.dispose();

    super.dispose();
  }

  static List<AssetDefinition> _resolveAssetDefinitions(QuickAddConfig config) {
    if (config.assetDefinitions.isNotEmpty) {
      return List<AssetDefinition>.unmodifiable(config.assetDefinitions);
    }

    // Temporary compatibility path for older tests or callers that still
    // provide asset names. AppShell supplies concrete definitions.
    return List<AssetDefinition>.unmodifiable(
      config.assets.map(_legacyAssetDefinition),
    );
  }

  static AssetDefinition _legacyAssetDefinition(String name) {
    final normalizedName = name.trim();
    final now = DateTime.now().toUtc();

    final configuration = switch (normalizedName) {
      'Gold Holdings' => (
        kind: AssetKind.gold,
        symbol: null,
        providerCode: 'alpha_vantage',
        providerSymbol: 'XAU',
        currencyCode: 'IDR',
        unit: 'gram',
        lotSize: 1,
        onlinePricingEnabled: true,
      ),
      'Stock Portfolio' => (
        kind: AssetKind.stock,
        symbol: 'STOCK',
        providerCode: null,
        providerSymbol: null,
        currencyCode: 'IDR',
        unit: 'share',
        lotSize: 100,
        onlinePricingEnabled: false,
      ),
      'Bitcoin Wallet' => (
        kind: AssetKind.crypto,
        symbol: 'BTC',
        providerCode: null,
        providerSymbol: null,
        currencyCode: 'IDR',
        unit: 'btc',
        lotSize: 1,
        onlinePricingEnabled: false,
      ),
      'Inventory' => (
        kind: AssetKind.inventory,
        symbol: null,
        providerCode: null,
        providerSymbol: null,
        currencyCode: 'IDR',
        unit: 'unit',
        lotSize: 1,
        onlinePricingEnabled: false,
      ),
      _ => (
        kind: AssetKind.other,
        symbol: null,
        providerCode: null,
        providerSymbol: null,
        currencyCode: 'IDR',
        unit: 'unit',
        lotSize: 1,
        onlinePricingEnabled: false,
      ),
    };

    return AssetDefinition(
      id: 'legacy-${normalizedName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
      displayName: normalizedName,
      kind: configuration.kind,
      symbol: configuration.symbol,
      providerCode: configuration.providerCode,
      providerSymbol: configuration.providerSymbol,
      exchangeCode: null,
      currencyCode: configuration.currencyCode,
      unit: configuration.unit,
      lotSize: configuration.lotSize,
      onlinePricingEnabled: configuration.onlinePricingEnabled,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: 'local-device',
      syncStatus: 'local_only',
    );
  }

  static String _projectId(String value) {
    return value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-');
  }
}
