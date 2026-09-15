import 'package:flutter/material.dart';
import '../../domain/entities/brokerage_settlement.dart';
import '../../domain/services/settlement_reconciliation_service.dart';
import '../controllers/brokerage_import_controller.dart';

class BrokerageSettlementsScreen extends StatefulWidget {
  const BrokerageSettlementsScreen({super.key, required this.controller});
  final BrokerageImportController controller;

  @override
  State<BrokerageSettlementsScreen> createState() =>
      _BrokerageSettlementsScreenState();
}

class _BrokerageSettlementsScreenState
    extends State<BrokerageSettlementsScreen> {
  late Future<List<BrokerageSettlement>> records =
      widget.controller.loadSettlements!();

  Future<void> _review(BrokerageSettlement evidence) async {
    final controller = widget.controller;
    final account = controller
        .accounts()
        .where((a) => a.id == evidence.brokerageAccountId)
        .firstOrNull;
    if (account == null) return;
    final trades = controller.transactions();
    final compatible = trades
        .where((trade) => evidence.isCompatibleTrade(trade, account))
        .toList();
    final suggested = const SettlementReconciliationService()
        .candidates(evidence: evidence, account: account, trades: trades)
        .map((trade) => trade.id)
        .toSet();
    final selected = {...evidence.tradeIds};
    final unavailable = evidence.tradeIds.difference(
      compatible.map((trade) => trade.id).toSet(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Review settlement links'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Links are evidence only. No cash, holdings or P&L changes. Select any number of trades; a trade may also belong to other settlements. Suggestions are not confirmed automatically.',
                  ),
                  if (unavailable.isNotEmpty)
                    CheckboxListTile(
                      value: !selected.any(unavailable.contains),
                      title: const Text('Remove unavailable reviewed links'),
                      subtitle: Text(
                        '${unavailable.length} previously linked trades are no longer available or compatible. Explicitly remove these links before saving, or cancel to preserve them.',
                      ),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selected.removeAll(unavailable);
                        } else {
                          selected.addAll(unavailable);
                        }
                      }),
                    ),
                  if (compatible.isEmpty)
                    const Text(
                      'No compatible trades. Keep this evidence unmatched.',
                    ),
                  for (final trade in compatible)
                    CheckboxListTile(
                      value: selected.contains(trade.id),
                      title: Text(trade.title),
                      subtitle: Text(
                        '${trade.date.toIso8601String().split('T').first} · ${evidence.currencyCode} ${trade.amount}${suggested.contains(trade.id) ? ' · Candidate' : ''}',
                      ),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selected.add(trade.id);
                        } else {
                          selected.remove(trade.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.any(unavailable.contains)
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Confirm reviewed links'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final updated = evidence.reconcile(
        compatible.where((t) => selected.contains(t.id)),
        account: account,
        reviewedAt: DateTime.now(),
      );
      await controller.saveSettlement!(updated, evidence.version);
      if (mounted) {
        setState(() {
          records = controller.loadSettlements!();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settlement evidence')),
    body: FutureBuilder<List<BrokerageSettlement>>(
      future: records,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('No imported settlement evidence.'));
        }
        return ListView(
          children: [
            for (final evidence in snapshot.data!)
              ListTile(
                title: Text('${evidence.type.sourceName} · ${evidence.state}'),
                subtitle: Text(
                  '${evidence.date.toIso8601String().split('T').first} · ${evidence.currencyCode} ${evidence.amount}\n${evidence.reference}\n${evidence.note}\n${evidence.tradeIds.length} reviewed trade links · No financial effect',
                ),
                trailing: const Icon(Icons.fact_check_outlined),
                onTap: () => _review(evidence),
              ),
          ],
        );
      },
    ),
  );
}
