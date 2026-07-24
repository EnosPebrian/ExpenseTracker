import 'package:flutter/material.dart';

import '../../../../../core/shared/widgets/searchable_dropdown.dart';
import '../../../../assets/presentation/widgets/asset_fee_fields.dart';
import '../../../../assets/presentation/widgets/asset_execution_reference_fields.dart';
import '../quick_add_controller.dart';

class QuickAddAdvancedOptions extends StatelessWidget {
  const QuickAddAdvancedOptions({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onToggle,
  });

  final QuickAddController controller;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: const Color(0xFF6C5CE7),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'More options',
                    style: TextStyle(
                      color: Color(0xFF6C5CE7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              children: [
                SearchableSelect(
                  label: 'Project',
                  value: controller.project ?? 'No project',
                  options: controller.projectOptions,
                  onChanged: controller.setProject,
                ),
                if (controller.isAssetConversion) ...[
                  const SizedBox(height: 12),
                  AssetFeeFields(controller: controller.assetConversion),
                  const SizedBox(height: 12),
                  AssetExecutionReferenceFields(
                    controller: controller.assetConversion,
                    compact: true,
                  ),
                ],
                const SizedBox(height: 12),
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date', style: TextStyle(fontSize: 12)),
                    subtitle: Text(
                      '${controller.date.day}/'
                      '${controller.date.month}/'
                      '${controller.date.year}',
                    ),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: controller.date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );

                      if (selected != null && context.mounted) {
                        controller.setDate(selected);
                      }
                    },
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Time', style: TextStyle(fontSize: 12)),
                    subtitle: Text(controller.time.format(context)),
                    trailing: const Icon(Icons.access_time, size: 18),
                    onTap: () async {
                      final selected = await showTimePicker(
                        context: context,
                        initialTime: controller.time,
                      );

                      if (selected != null && context.mounted) {
                        controller.setTime(selected);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }
}
