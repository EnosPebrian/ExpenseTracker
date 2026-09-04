import 'package:flutter/material.dart';

import '../../domain/import/transaction_import_models.dart';

class TransactionImportMappingPanel extends StatefulWidget {
  const TransactionImportMappingPanel({
    super.key,
    required this.headers,
    required this.initial,
    required this.onChanged,
  });
  final List<String> headers;
  final TransactionImportMapping? initial;
  final ValueChanged<TransactionImportMapping> onChanged;

  @override
  State<TransactionImportMappingPanel> createState() => _MappingPanelState();
}

class _MappingPanelState extends State<TransactionImportMappingPanel> {
  late CsvAmountStrategy strategy;
  late int date;
  late int description;
  int? amount;
  int? debit;
  int? credit;
  int? type;
  int? category;
  int? reference;
  int? note;
  late CsvDateFormat dateFormat;
  late CsvSeparator decimal;
  late CsvSeparator thousands;
  late CsvSignConvention sign;
  bool stripSymbols = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    strategy = initial?.amountStrategy ?? CsvAmountStrategy.signedAmount;
    date = initial?.dateColumn ?? 0;
    description =
        initial?.descriptionColumn ?? (widget.headers.length > 1 ? 1 : 0);
    amount = initial?.amountColumn;
    debit = initial?.debitColumn;
    credit = initial?.creditColumn;
    type = initial?.typeColumn;
    category = initial?.categoryColumn;
    reference = initial?.referenceColumn;
    note = initial?.noteColumn;
    dateFormat = initial?.dateFormat ?? CsvDateFormat.automatic;
    decimal = initial?.decimalSeparator ?? CsvSeparator.none;
    thousands = initial?.thousandsSeparator ?? CsvSeparator.none;
    sign = initial?.signConvention ?? CsvSignConvention.negativeExpense;
    stripSymbols = initial?.stripCurrencySymbols ?? false;
  }

  void emit() {
    widget.onChanged(
      TransactionImportMapping(
        dateColumn: date,
        descriptionColumn: description,
        amountColumn: amount,
        debitColumn: debit,
        creditColumn: credit,
        typeColumn: type,
        categoryColumn: category,
        referenceColumn: reference,
        noteColumn: note,
        amountStrategy: strategy,
        signConvention: sign,
        dateFormat: dateFormat,
        decimalSeparator: decimal,
        thousandsSeparator: thousands,
        stripCurrencySymbols: stripSymbols,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _enum<CsvAmountStrategy>(
              'Amount strategy',
              strategy,
              CsvAmountStrategy.values,
              (value) {
                setState(() => strategy = value);
                emit();
              },
            ),
            _column('Date', date, (value) {
              setState(() => date = value!);
              emit();
            }, optional: false),
            _column('Description', description, (value) {
              setState(() => description = value!);
              emit();
            }, optional: false),
            if (strategy != CsvAmountStrategy.debitCredit)
              _column('Amount', amount, (value) {
                setState(() => amount = value);
                emit();
              }, optional: false),
            if (strategy == CsvAmountStrategy.canonical)
              _column('Type', type, (value) {
                setState(() => type = value);
                emit();
              }, optional: false),
            if (strategy == CsvAmountStrategy.debitCredit) ...[
              _column('Debit', debit, (value) {
                setState(() => debit = value);
                emit();
              }, optional: false),
              _column('Credit', credit, (value) {
                setState(() => credit = value);
                emit();
              }, optional: false),
            ],
            _column('Category', category, (value) {
              setState(() => category = value);
              emit();
            }),
            _column('Reference', reference, (value) {
              setState(() => reference = value);
              emit();
            }),
            _column('Note', note, (value) {
              setState(() => note = value);
              emit();
            }),
            _enum<CsvDateFormat>(
              'Date format',
              dateFormat,
              CsvDateFormat.values,
              (value) {
                setState(() => dateFormat = value);
                emit();
              },
            ),
            _enum<CsvSeparator>(
              'Decimal separator',
              decimal,
              CsvSeparator.values,
              (value) {
                setState(() => decimal = value);
                emit();
              },
            ),
            _enum<CsvSeparator>(
              'Thousands separator',
              thousands,
              CsvSeparator.values,
              (value) {
                setState(() => thousands = value);
                emit();
              },
            ),
            if (strategy == CsvAmountStrategy.signedAmount)
              _enum<CsvSignConvention>(
                'Sign convention',
                sign,
                CsvSignConvention.values,
                (value) {
                  setState(() => sign = value);
                  emit();
                },
              ),
            SizedBox(
              width: 240,
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Strip configured currency symbols'),
                value: stripSymbols,
                onChanged: (value) {
                  setState(() => stripSymbols = value ?? false);
                  emit();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(
    String label,
    int? value,
    ValueChanged<int?> changed, {
    bool optional = true,
  }) => SizedBox(
    width: 220,
    child: DropdownButtonFormField<int?>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        if (optional)
          const DropdownMenuItem(value: null, child: Text('Not mapped')),
        ...List.generate(
          widget.headers.length,
          (index) => DropdownMenuItem(
            value: index,
            child: Text(widget.headers[index]),
          ),
        ),
      ],
      onChanged: changed,
    ),
  );

  Widget _enum<T extends Enum>(
    String label,
    T value,
    List<T> values,
    ValueChanged<T> changed,
  ) => SizedBox(
    width: 220,
    child: DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: values
          .map((item) => DropdownMenuItem(value: item, child: Text(item.name)))
          .toList(),
      onChanged: (item) {
        if (item != null) changed(item);
      },
    ),
  );
}
