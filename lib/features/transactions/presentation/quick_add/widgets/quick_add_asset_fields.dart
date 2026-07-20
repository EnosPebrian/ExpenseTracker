import 'package:flutter/material.dart';

import '../../../../../core/shared/widgets/searchable_dropdown.dart';
import '../quick_add_controller.dart';

class QuickAddAssetModeSelector extends StatelessWidget {
  const QuickAddAssetModeSelector({super.key, required this.controller});

  final QuickAddController controller;

  @override
  Widget build(BuildContext context) {
    final conversion = controller.assetConversion;

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        segments: const [
          ButtonSegment<bool>(
            value: false,
            icon: Icon(Icons.shopping_cart_outlined, size: 16),
            label: Text('Buy asset'),
          ),
          ButtonSegment<bool>(
            value: true,
            icon: Icon(Icons.sell_outlined, size: 16),
            label: Text('Sell asset'),
          ),
        ],
        selected: {conversion.sellAsset},
        onSelectionChanged: (selection) {
          conversion.setSellAsset(selection.first);
        },
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(42)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? const Color(0xFFEDE9FF)
                : const Color(0xFFF7F8FA);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? const Color(0xFF6C5CE7)
                : const Color(0xFF555461);
          }),
          side: const WidgetStatePropertyAll(BorderSide.none),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class QuickAddAssetAccountFields extends StatelessWidget {
  const QuickAddAssetAccountFields({super.key, required this.controller});

  final QuickAddController controller;

  @override
  Widget build(BuildContext context) {
    final conversion = controller.assetConversion;

    return Column(
      children: [
        SearchableSelect(
          label: conversion.sourceLabel,
          value: conversion.source,
          options: conversion.sourceOptions,
          onChanged: conversion.setSource,
        ),
        const SizedBox(height: 14),
        SearchableSelect(
          label: conversion.destinationLabel,
          value: conversion.destination,
          options: conversion.destinationOptions,
          onChanged: conversion.setDestination,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: conversion.quantityController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: conversion.quantityLabel,
            hintText: '0',
            suffixText: conversion.unit,
          ),
        ),
      ],
    );
  }
}
