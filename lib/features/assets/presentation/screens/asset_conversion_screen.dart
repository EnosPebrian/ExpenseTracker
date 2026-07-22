import 'package:flutter/material.dart';

import '../../../../core/shared/widgets/page_layout.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../controllers/asset_conversion_controller.dart';
import '../widgets/asset_conversion_form.dart';
import '../widgets/conversion_summary_card.dart';
import '../../domain/entities/asset_definition.dart';

class AssetConversionScreen extends StatefulWidget {
  const AssetConversionScreen({
    super.key,
    required this.accounts,
    required this.assets,
    required this.onSave,
  });

  final List<String> accounts;
  final List<AssetDefinition> assets;
  final Future<void> Function(Transaction) onSave;

  @override
  State<AssetConversionScreen> createState() => _AssetConversionScreenState();
}

class _AssetConversionScreenState extends State<AssetConversionScreen> {
  late final AssetConversionController controller;
  bool saving = false;

  @override
  void initState() {
    super.initState();

    controller = AssetConversionController(
      accounts: widget.accounts,
      assets: widget.assets,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveConversion() async {
    if (saving) {
      return;
    }

    late final Transaction transaction;

    try {
      transaction = controller.buildTransaction();
    } on StateError catch (error) {
      _showMessage(error.message);
      return;
    }

    setState(() {
      saving = true;
    });

    try {
      await widget.onSave(transaction);

      if (!mounted) {
        return;
      }

      _showMessage('Asset conversion saved locally');
    } catch (exception) {
      if (!mounted) {
        return;
      }

      final message = exception is StateError
          ? exception.message
          : exception.toString();

      _showMessage('Could not save asset conversion. $message');
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return PageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeading(
                kicker: 'QUANTITY-BASED ASSETS',
                title: 'Asset Conversion',
                subtitle:
                    'Convert cash into gold, stocks, crypto, inventory, '
                    'or another measured asset.',
              ),
              ResponsivePair(
                left: AssetConversionForm(
                  controller: controller,
                  onSave: _saveConversion,
                  saving: saving,
                ),
                right: ConversionSummaryCard(controller: controller),
              ),
            ],
          ),
        );
      },
    );
  }
}
