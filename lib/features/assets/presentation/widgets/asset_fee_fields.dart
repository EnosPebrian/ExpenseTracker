import 'package:flutter/material.dart';

import '../../../../core/shared/formatters/thousands_formatter.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../controllers/asset_conversion_controller.dart';

class AssetFeeFields extends StatelessWidget {
  const AssetFeeFields({super.key, required this.controller});

  final AssetConversionController controller;

  @override
  Widget build(BuildContext context) {
    final feeError = controller.feeValidationMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller.feeController,
          keyboardType: TextInputType.number,
          inputFormatters: const [ThousandsFormatter()],
          decoration: const InputDecoration(
            labelText: 'Transaction fee',
            prefixText: 'Rp ',
            hintText: '0',
          ),
        ),
        if (controller.feeAmount > 0) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<AssetFeeTreatment>(
            key: ValueKey(controller.feeTreatment),
            initialValue: controller.feeTreatment,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Fee handling',
              errorText: feeError,
              helperText: controller.sellAsset
                  ? 'Subtract the fee from gross sale proceeds.'
                  : 'Include the fee in the asset acquisition cost.',
            ),
            items: controller.feeTreatmentOptions
                .map(
                  (treatment) => DropdownMenuItem<AssetFeeTreatment>(
                    value: treatment,
                    child: Text(
                      controller.feeTreatmentLabel(treatment),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                controller.setFeeTreatment(value);
              }
            },
          ),
        ],
      ],
    );
  }
}
