import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/design/app_colors.dart';
import '../../controllers/asset_definition_controller.dart';
import '../../domain/entities/asset_definition.dart';
import '../../domain/entities/asset_kind.dart';
import '../../domain/services/asset_definition_integrity_policy.dart';
import '../../domain/services/asset_definition_usage_policy.dart';
import '../models/asset_definition_catalog_query.dart';
import '../models/asset_definition_form_presets.dart';

class AssetDefinitionEditorDialog extends StatefulWidget {
  const AssetDefinitionEditorDialog({
    super.key,
    required this.controller,
    this.definition,
  });

  final AssetDefinitionController controller;
  final AssetDefinition? definition;

  @override
  State<AssetDefinitionEditorDialog> createState() =>
      _AssetDefinitionEditorDialogState();
}

class _AssetDefinitionEditorDialogState
    extends State<AssetDefinitionEditorDialog> {
  static const presets = AssetDefinitionFormPresets();
  final formKey = GlobalKey<FormState>();
  final dirtyFields = <AssetDefinitionPresetField>{};

  late final TextEditingController nameController;
  late final TextEditingController symbolController;
  late final TextEditingController providerController;
  late final TextEditingController providerSymbolController;
  late final TextEditingController exchangeController;
  late final TextEditingController currencyController;
  late final TextEditingController unitController;
  late final TextEditingController lotSizeController;
  late AssetKind kind;
  late bool onlinePricingEnabled;
  late final AssetDefinitionUsageResult? usage;

  bool get isCreating => widget.definition == null;
  bool get identityProtected => usage?.hasLinkedTransactions ?? false;
  bool get archived => widget.definition?.isDeleted ?? false;

  @override
  void initState() {
    super.initState();
    final definition = widget.definition;
    usage = definition == null ? null : widget.controller.usageFor(definition);
    kind = definition?.kind ?? AssetKind.stock;
    onlinePricingEnabled = definition?.onlinePricingEnabled ?? false;
    nameController = TextEditingController(text: definition?.displayName ?? '');
    symbolController = TextEditingController(text: definition?.symbol ?? '');
    providerController = TextEditingController(
      text: definition?.providerCode ?? '',
    );
    providerSymbolController = TextEditingController(
      text: definition?.providerSymbol ?? '',
    );
    exchangeController = TextEditingController(
      text: definition?.exchangeCode ?? '',
    );
    currencyController = TextEditingController(
      text: definition?.currencyCode ?? '',
    );
    unitController = TextEditingController(text: definition?.unit ?? '');
    lotSizeController = TextEditingController(
      text: definition?.lotSize.toString() ?? '',
    );
    if (isCreating) {
      _writeValues(
        presets.applyKindDefaults(
          kind: kind,
          current: _readValues(),
          dirtyFields: dirtyFields,
          isCreating: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    symbolController.dispose();
    providerController.dispose();
    providerSymbolController.dispose();
    exchangeController.dispose();
    currencyController.dispose();
    unitController.dispose();
    lotSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isCreating ? 'Add asset' : 'Edit asset'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FormSectionTitle(
                  key: Key('asset-section-identity'),
                  title: 'Identity',
                  subtitle: 'The name and type shown across the portfolio.',
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('asset-name-field'),
                  controller: nameController,
                  autofocus: true,
                  readOnly: archived,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    hintText: 'Bank Central Asia',
                  ),
                  onChanged: (_) => _clearIntegrityErrors(),
                  validator: (value) =>
                      _requiredValidator(value) ??
                      _integrityError(
                        AssetDefinitionIntegrityField.displayName,
                      ),
                ),
                if (identityProtected) ...[
                  const SizedBox(height: 12),
                  const Text(
                    key: Key('linked-edit-explanation'),
                    'Identity and accounting fields are locked because this '
                    'asset is already used by transactions. Display name and '
                    'online provider settings remain editable.',
                    style: TextStyle(color: muted, fontSize: 11, height: 1.4),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<AssetKind>(
                  key: const Key('asset-kind-field'),
                  initialValue: kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Asset kind'),
                  items: [
                    for (final value in AssetKind.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(value.catalogLabel),
                      ),
                  ],
                  onChanged: identityProtected || archived
                      ? null
                      : (value) {
                          if (value == null) return;
                          widget.controller.clearValidationErrors();
                          setState(() {
                            kind = value;
                            _writeValues(
                              presets.applyKindDefaults(
                                kind: kind,
                                current: _readValues(),
                                dirtyFields: dirtyFields,
                                isCreating: isCreating,
                              ),
                            );
                          });
                        },
                ),
                const SizedBox(height: 20),
                const _FormSectionTitle(
                  key: Key('asset-section-trading'),
                  title: 'Trading and measurement',
                  subtitle: 'Market identity, valuation currency, and units.',
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('asset-symbol-field'),
                  controller: symbolController,
                  readOnly: identityProtected || archived,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Symbol',
                    hintText: 'BBCA',
                  ),
                  onChanged: (_) => _handleSymbolChanged(),
                  validator: _validateSymbol,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('asset-exchange-field'),
                  controller: exchangeController,
                  readOnly: identityProtected || archived,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Exchange',
                    hintText: 'IDX',
                  ),
                  onChanged: (_) =>
                      _markDirty(AssetDefinitionPresetField.exchange),
                  validator: (_) => _integrityError(
                    AssetDefinitionIntegrityField.exchangeCode,
                  ),
                ),
                if (isCreating && kind == AssetKind.stock) ...[
                  const SizedBox(height: 8),
                  _PresetButton(
                    key: const Key('asset-use-idx-defaults'),
                    label: 'Use IDX defaults',
                    onPressed: _applyIdxDefaults,
                  ),
                ],
                const SizedBox(height: 12),
                _ResponsiveFieldRow(
                  children: [
                    TextFormField(
                      key: const Key('asset-currency-field'),
                      controller: currencyController,
                      readOnly: identityProtected || archived,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Valuation currency',
                        hintText: 'IDR',
                      ),
                      onChanged: (_) =>
                          _markDirty(AssetDefinitionPresetField.currency),
                      validator: _validateCurrency,
                    ),
                    TextFormField(
                      key: const Key('asset-unit-field'),
                      controller: unitController,
                      readOnly: identityProtected || archived,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        hintText: 'share, gram, item',
                      ),
                      onChanged: (_) =>
                          _markDirty(AssetDefinitionPresetField.unit),
                      validator: _validateUnit,
                    ),
                  ],
                ),
                if (isCreating && kind == AssetKind.foreignCurrency) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PresetButton(
                        key: const Key('asset-use-symbol-unit'),
                        label: _foreignSymbol().isEmpty
                            ? 'Use symbol as unit'
                            : 'Use ${_foreignSymbol()} as unit',
                        onPressed: _foreignSymbol().length == 3
                            ? _applySymbolAsUnit
                            : null,
                      ),
                      _PresetButton(
                        key: const Key('asset-use-provider-pair'),
                        label: _validForeignCodes
                            ? 'Use ${_foreignSymbol()}/${_valuationCurrency()} pair'
                            : 'Use currency pair',
                        onPressed: _validForeignCodes
                            ? _applyProviderPair
                            : null,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('asset-lot-size-field'),
                  controller: lotSizeController,
                  readOnly: identityProtected || archived,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Units per lot',
                    helperText:
                        'Use the actual trading lot; apply IDX defaults only '
                        'when appropriate.',
                  ),
                  onChanged: (_) =>
                      _markDirty(AssetDefinitionPresetField.lotSize),
                  validator: _validateLotSize,
                ),
                const SizedBox(height: 20),
                const _FormSectionTitle(
                  key: Key('asset-section-pricing'),
                  title: 'Pricing provider',
                  subtitle:
                      'Optional quote configuration; enabling it does not '
                      'guarantee a live price.',
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  key: const Key('asset-online-pricing-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Online pricing'),
                  subtitle: const Text(
                    'Use a configured market-data provider for this asset.',
                  ),
                  value: onlinePricingEnabled,
                  onChanged: archived
                      ? null
                      : (value) {
                          widget.controller.clearValidationErrors();
                          setState(() {
                            onlinePricingEnabled = value;
                            if (value &&
                                providerController.text.trim().isEmpty &&
                                !dirtyFields.contains(
                                  AssetDefinitionPresetField.providerCode,
                                ) &&
                                kind != AssetKind.crypto &&
                                kind != AssetKind.inventory) {
                              providerController.text = 'alpha_vantage';
                            }
                          });
                        },
                ),
                if (onlinePricingEnabled) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('asset-provider-field'),
                    controller: providerController,
                    readOnly: archived,
                    decoration: const InputDecoration(
                      labelText: 'Provider code',
                      hintText: 'alpha_vantage',
                    ),
                    onChanged: (_) =>
                        _markDirty(AssetDefinitionPresetField.providerCode),
                    validator: (value) =>
                        _requiredValidator(value) ??
                        _integrityError(
                          AssetDefinitionIntegrityField.providerCode,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('asset-provider-symbol-field'),
                    controller: providerSymbolController,
                    readOnly: archived,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Provider symbol',
                      hintText: 'BBCA.JK',
                      helperText:
                          'Use the exact symbol required by the provider.',
                    ),
                    onChanged: (_) =>
                        _markDirty(AssetDefinitionPresetField.providerSymbol),
                    validator: _validateProviderSymbol,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(archived ? 'Close' : 'Cancel'),
        ),
        if (!archived)
          FilledButton(
            key: const Key('save-asset-button'),
            onPressed: _save,
            child: const Text('Save asset'),
          ),
      ],
    );
  }

  String? _validateSymbol(String? value) {
    final isEmpty = value == null || value.trim().isEmpty;
    if (kind == AssetKind.stock && isEmpty) {
      return 'A stock symbol is required.';
    }
    if (kind == AssetKind.foreignCurrency &&
        !RegExp(r'^[A-Z]{3}$').hasMatch(value?.trim().toUpperCase() ?? '')) {
      return 'Use a three-letter currency symbol.';
    }
    return _integrityError(AssetDefinitionIntegrityField.symbol);
  }

  String? _validateCurrency(String? value) {
    final normalized = value?.trim().toUpperCase() ?? '';
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
      return 'Use a three-letter currency.';
    }
    if (kind == AssetKind.foreignCurrency && _foreignSymbol() == normalized) {
      return 'Source and valuation currencies must differ.';
    }
    return _integrityError(AssetDefinitionIntegrityField.currencyCode);
  }

  String? _validateUnit(String? value) {
    final requiredError = _requiredValidator(value);
    if (requiredError != null) return requiredError;
    if (kind == AssetKind.foreignCurrency &&
        _foreignSymbol().length == 3 &&
        value!.trim().toUpperCase() != _foreignSymbol()) {
      return 'Unit must match the currency symbol.';
    }
    return _integrityError(AssetDefinitionIntegrityField.unit);
  }

  String? _validateLotSize(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed <= 0) {
      return 'Lot size must be greater than zero.';
    }
    return _integrityError(AssetDefinitionIntegrityField.lotSize);
  }

  String? _validateProviderSymbol(String? value) {
    final normalized = value?.trim().toUpperCase() ?? '';
    if (normalized.isEmpty) return 'A provider symbol is required.';
    if (kind == AssetKind.foreignCurrency && _validForeignCodes) {
      final expectedPair = '${_foreignSymbol()}/${_valuationCurrency()}';
      if (normalized != expectedPair) {
        return 'Provider pair must be $expectedPair.';
      }
    }
    return _integrityError(AssetDefinitionIntegrityField.providerSymbol);
  }

  bool get _validForeignCodes =>
      RegExp(r'^[A-Z]{3}$').hasMatch(_foreignSymbol()) &&
      RegExp(r'^[A-Z]{3}$').hasMatch(_valuationCurrency());

  String _foreignSymbol() => symbolController.text.trim().toUpperCase();
  String _valuationCurrency() => currencyController.text.trim().toUpperCase();

  void _markDirty(AssetDefinitionPresetField field) {
    dirtyFields.add(field);
    _clearIntegrityErrors();
    if (mounted && kind == AssetKind.foreignCurrency) setState(() {});
  }

  void _handleSymbolChanged() {
    _clearIntegrityErrors();
    if (mounted && kind == AssetKind.foreignCurrency) setState(() {});
  }

  void _applyIdxDefaults() {
    setState(() {
      _writeValues(
        presets.applyIdxDefaults(
          current: _readValues(),
          dirtyFields: dirtyFields,
          isCreating: isCreating,
        ),
      );
    });
  }

  void _applySymbolAsUnit() {
    setState(() {
      _writeValues(
        presets.applySymbolAsUnit(
          current: _readValues(),
          dirtyFields: dirtyFields,
          isCreating: isCreating,
          symbol: symbolController.text,
        ),
      );
    });
  }

  void _applyProviderPair() {
    setState(() {
      _writeValues(
        presets.applyProviderPair(
          current: _readValues(),
          dirtyFields: dirtyFields,
          isCreating: isCreating,
          symbol: symbolController.text,
        ),
      );
    });
  }

  AssetDefinitionFormValues _readValues() => AssetDefinitionFormValues(
    exchange: exchangeController.text,
    currency: currencyController.text,
    unit: unitController.text,
    lotSize: lotSizeController.text,
    providerCode: providerController.text,
    providerSymbol: providerSymbolController.text,
    onlinePricingEnabled: onlinePricingEnabled,
  );

  void _writeValues(AssetDefinitionFormValues values) {
    exchangeController.text = values.exchange;
    currencyController.text = values.currency;
    unitController.text = values.unit;
    lotSizeController.text = values.lotSize;
    providerController.text = values.providerCode;
    providerSymbolController.text = values.providerSymbol;
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final definition = widget.definition;
    final timestamp = DateTime.now().toUtc();
    final candidate = AssetDefinition(
      id: definition?.id ?? const Uuid().v4(),
      displayName: nameController.text.trim(),
      kind: kind,
      symbol: _optionalValue(symbolController.text),
      providerCode: _optionalValue(providerController.text),
      providerSymbol: _optionalValue(providerSymbolController.text),
      exchangeCode: _optionalValue(exchangeController.text),
      currencyCode: currencyController.text.trim().toUpperCase(),
      unit: unitController.text.trim().toLowerCase(),
      lotSize: int.parse(lotSizeController.text.trim()),
      onlinePricingEnabled: onlinePricingEnabled,
      createdAt: definition?.createdAt ?? timestamp,
      updatedAt: timestamp,
      deletedAt: null,
      version: definition?.version ?? 1,
      deviceId: definition?.deviceId ?? 'local-device',
      syncStatus: definition?.syncStatus ?? 'local_only',
    );
    try {
      final saved = await widget.controller.save(candidate);
      if (mounted) Navigator.of(context).pop(saved);
    } on AssetDefinitionIntegrityException {
      if (mounted) setState(() => formKey.currentState?.validate());
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  String? _integrityError(AssetDefinitionIntegrityField field) {
    return widget.controller.fieldError(field);
  }

  void _clearIntegrityErrors() {
    if (widget.controller.integrityResult == null &&
        widget.controller.error == null) {
      return;
    }
    widget.controller.clearValidationErrors();
    if (mounted) setState(() {});
  }
}

class _FormSectionTitle extends StatelessWidget {
  const _FormSectionTitle({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(color: muted, fontSize: 10)),
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.auto_fix_high_outlined, size: 16),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _ResponsiveFieldRow extends StatelessWidget {
  const _ResponsiveFieldRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

String? _requiredValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'This field is required.';
  }
  return null;
}

String? _optionalValue(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
