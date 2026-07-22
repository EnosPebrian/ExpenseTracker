import 'package:flutter/material.dart';

import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../../core/shared/widgets/page_layout.dart';
import '../../../../core/shared/widgets/searchable_dropdown.dart';
import '../../controllers/asset_conversion_controller.dart';

class AssetConversionForm extends StatelessWidget {
  const AssetConversionForm({
    super.key,
    required this.controller,
    required this.onSave,
    required this.saving,
  });

  final AssetConversionController controller;
  final Future<void> Function() onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle(
              'New conversion',
              'A conversion moves value without creating income or expense.',
            ),
            const SizedBox(height: 22),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(Icons.shopping_cart_outlined),
                  label: Text('Buy asset'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(Icons.sell_outlined),
                  label: Text('Sell asset'),
                ),
              ],
              selected: {controller.sellAsset},
              onSelectionChanged: (selection) {
                controller.setSellAsset(selection.first);
              },
            ),
            const SizedBox(height: 16),
            SearchableSelect(
              label: controller.sourceLabel,
              value: controller.source,
              options: controller.sourceOptions,
              onChanged: controller.setSource,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.cashController,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsFormatter()],
              decoration: InputDecoration(
                labelText: controller.cashLabel,
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 12),
            SearchableSelect(
              label: controller.destinationLabel,
              value: controller.destination,
              options: controller.destinationOptions,
              onChanged: controller.setDestination,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.quantityController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: controller.quantityLabel,
                suffixText: controller.unit,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(controller.feeTreatment),
              initialValue: controller.feeTreatment,
              decoration: const InputDecoration(labelText: 'Fee treatment'),
              items: AssetConversionController.feeTreatments
                  .map(
                    (treatment) => DropdownMenuItem<String>(
                      value: treatment,
                      child: Text(treatment),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  controller.setFeeTreatment(value);
                }
              },
            ),
            const SizedBox(height: 12),
            _ConversionDateTimeFields(controller: controller),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.canSave && !saving
                    ? () async {
                        await onSave();
                      }
                    : null,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.currency_exchange),
                label: Text(saving ? 'Saving...' : 'Record conversion'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversionDateTimeFields extends StatelessWidget {
  const _ConversionDateTimeFields({required this.controller});

  final AssetConversionController controller;

  @override
  Widget build(BuildContext context) {
    final dateButton = OutlinedButton.icon(
      onPressed: () => _pickDate(context),
      icon: const Icon(Icons.calendar_today_outlined, size: 15),
      label: Text(
        'Date: '
        '${controller.selectedDate.day}/'
        '${controller.selectedDate.month}/'
        '${controller.selectedDate.year}',
      ),
    );

    final timeButton = OutlinedButton.icon(
      onPressed: () => _pickTime(context),
      icon: const Icon(Icons.schedule, size: 16),
      label: Text('Time: ${controller.selectedTime.format(context)}'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [dateButton, const SizedBox(height: 10), timeButton],
          );
        }

        return Row(
          children: [
            Expanded(child: dateButton),
            const SizedBox(width: 10),
            Expanded(child: timeButton),
          ],
        );
      },
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: controller.selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2035),
    );

    if (selected != null && context.mounted) {
      controller.setDate(selected);
    }
  }

  Future<void> _pickTime(BuildContext context) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: controller.selectedTime,
    );

    if (selected != null && context.mounted) {
      controller.setTime(selected);
    }
  }
}
