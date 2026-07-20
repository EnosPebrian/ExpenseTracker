import 'package:flutter/material.dart';

import '../../../../core/shared/widgets/searchable_dropdown.dart';
import '../../domain/entities/transaction.dart';
import '../../../../core/shared/formatters/thousands_formatter.dart';

class TransactionFormFields extends StatelessWidget {
  const TransactionFormFields({
    super.key,
    required this.type,
    required this.amountController,
    required this.descriptionController,
    required this.quantityController,
    required this.unitController,
    required this.unitPriceController,
    required this.account,
    required this.destinationAccount,
    required this.category,
    required this.project,
    required this.date,
    required this.time,
    required this.accountOptions,
    required this.assetOptions,
    required this.categoryOptions,
    required this.projectOptions,
    required this.onTypeChanged,
    required this.onAccountChanged,
    required this.onDestinationChanged,
    required this.onCategoryChanged,
    required this.onProjectChanged,
    required this.onDateChanged,
    required this.onTimeChanged,
  });

  final TransactionType type;
  final TextEditingController amountController;
  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController unitController;
  final TextEditingController unitPriceController;
  final String account;
  final String destinationAccount;
  final String category;
  final String project;
  final DateTime date;
  final TimeOfDay time;
  final List<String> accountOptions;
  final List<String> assetOptions;
  final List<String> categoryOptions;
  final List<String> projectOptions;
  final ValueChanged<TransactionType> onTypeChanged;
  final ValueChanged<String> onAccountChanged;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;

  bool get _movesBetweenAccounts =>
      type == TransactionType.transfer ||
      type == TransactionType.assetConversion;

  @override
  Widget build(BuildContext context) {
    final movementOptions = <String>{
      ...accountOptions,
      ...assetOptions,
    }.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<TransactionType>(
          segments: const [
            ButtonSegment(
              value: TransactionType.expense,
              label: Text('Expense'),
            ),
            ButtonSegment(value: TransactionType.income, label: Text('Income')),
            ButtonSegment(
              value: TransactionType.transfer,
              label: Text('Transfer'),
            ),
            ButtonSegment(
              value: TransactionType.assetConversion,
              label: Text('Asset'),
            ),
          ],
          selected: {type},
          onSelectionChanged: (values) => onTypeChanged(values.first),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [ThousandsFormatter()],
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: 'Rp ',
          ),
        ),
        const SizedBox(height: 12),
        SearchableSelect(
          label: _movesBetweenAccounts ? 'From account / asset' : 'Account',
          value: account,
          options: _movesBetweenAccounts ? movementOptions : accountOptions,
          onChanged: onAccountChanged,
        ),
        if (_movesBetweenAccounts) ...[
          const SizedBox(height: 12),
          SearchableSelect(
            label: 'To account / asset',
            value: destinationAccount,
            options: movementOptions,
            onChanged: onDestinationChanged,
          ),
        ],
        if (type == TransactionType.expense ||
            type == TransactionType.income) ...[
          const SizedBox(height: 12),
          SearchableSelect(
            label: 'Category',
            value: category,
            options: categoryOptions,
            onChanged: onCategoryChanged,
          ),
        ],
        const SizedBox(height: 12),
        SearchableSelect(
          label: 'Project (optional)',
          value: project,
          options: projectOptions,
          onChanged: onProjectChanged,
        ),
        if (type == TransactionType.assetConversion) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: unitController,
                  decoration: const InputDecoration(labelText: 'Unit'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: unitPriceController,
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsFormatter()],
            decoration: const InputDecoration(
              labelText: 'Unit price',
              prefixText: 'Rp ',
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) onDateChanged(picked);
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 15),
                label: Text('${date.day}/${date.month}/${date.year}'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (picked != null) onTimeChanged(picked);
                },
                icon: const Icon(Icons.schedule, size: 16),
                label: Text(time.format(context)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
