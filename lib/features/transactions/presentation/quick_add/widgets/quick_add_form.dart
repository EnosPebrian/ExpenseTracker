import 'package:flutter/material.dart';

import '../../../../../core/shared/widgets/searchable_dropdown.dart';
import '../../../domain/entities/transaction.dart';
import '../quick_add_controller.dart';
import 'amount_keypad.dart';
import 'quick_add_advanced_options.dart';
import 'quick_add_asset_fields.dart';
import 'quick_add_header.dart';
import 'transaction_type_selector.dart';

class QuickAddForm extends StatefulWidget {
  const QuickAddForm({super.key, required this.controller});

  final QuickAddController controller;

  @override
  State<QuickAddForm> createState() => _QuickAddFormState();
}

class _QuickAddFormState extends State<QuickAddForm> {
  bool advancedExpanded = false;

  QuickAddController get controller {
    return widget.controller;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          width: 420,
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Theme(
            data: Theme.of(
              context,
            ).copyWith(inputDecorationTheme: _inputTheme()),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  QuickAddHeader(
                    onClose: controller.saving
                        ? null
                        : () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 22),
                  TransactionTypeSelector(
                    value: controller.type,
                    onChanged: controller.setType,
                  ),
                  if (controller.isAssetConversion) ...[
                    const SizedBox(height: 14),
                    QuickAddAssetModeSelector(controller: controller),
                  ],
                  const SizedBox(height: 20),
                  AmountKeypad(onChanged: controller.setAmountText),
                  const SizedBox(height: 14),
                  if (controller.isAssetConversion)
                    QuickAddAssetAccountFields(controller: controller)
                  else ...[
                    SearchableSelect(
                      label: controller.type == TransactionType.transfer
                          ? 'From account'
                          : 'Account',
                      value: controller.account,
                      options: controller.config.accounts,
                      onChanged: controller.setAccount,
                    ),
                    const SizedBox(height: 14),
                    if (controller.type == TransactionType.transfer)
                      SearchableSelect(
                        label: 'To account',
                        value: controller.toAccount ?? controller.account,
                        options: controller.config.accounts,
                        onChanged: controller.setToAccount,
                      )
                    else
                      SearchableSelect(
                        label: 'Category',
                        value: controller.category,
                        options: controller.categories,
                        onChanged: controller.setCategory,
                      ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    onChanged: (value) {
                      controller.description = value;
                    },
                    decoration: InputDecoration(
                      hintText: controller.isAssetConversion
                          ? 'What was this conversion for?'
                          : 'What was this for?',
                    ),
                  ),
                  const SizedBox(height: 16),
                  QuickAddAdvancedOptions(
                    controller: controller,
                    expanded: advancedExpanded,
                    onToggle: () {
                      setState(() {
                        advancedExpanded = !advancedExpanded;
                      });
                    },
                  ),
                  if (controller.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      controller.error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: controller.saving
                          ? null
                          : () async {
                              final saved = await controller.save();

                              if (saved && context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                      icon: Icon(
                        controller.isAssetConversion
                            ? Icons.currency_exchange
                            : Icons.north_east,
                        size: 17,
                      ),
                      label: Text(
                        controller.saving
                            ? 'Saving...'
                            : controller.isAssetConversion
                            ? 'Record conversion'
                            : 'Save transaction',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6C5CE7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  InputDecorationTheme _inputTheme() {
    return const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFFF7F8FA),
      labelStyle: TextStyle(color: Color(0xFF858491), fontSize: 11),
      hintStyle: TextStyle(color: Color(0xFFA4A3B1), fontSize: 11),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFFE6E8EE)),
      ),
    );
  }
}
