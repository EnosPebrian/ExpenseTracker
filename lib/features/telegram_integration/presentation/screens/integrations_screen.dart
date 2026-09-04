import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/app_colors.dart';
import '../../domain/telegram_integration_repository.dart';
import '../controllers/telegram_integration_controller.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({
    super.key,
    required this.repository,
    required this.bookId,
    required this.memberId,
  });

  final TelegramIntegrationRepository repository;
  final String bookId;
  final String memberId;

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  late final TelegramIntegrationController controller =
      TelegramIntegrationController(
        widget.repository,
        bookId: widget.bookId,
        memberId: widget.memberId,
      )..addListener(_changed);

  @override
  void initState() {
    super.initState();
    controller.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairing = controller.pairing;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text('Integrations', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('Connect private ingestion services to this household.'),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.telegram_rounded, color: violet),
                    SizedBox(width: 12),
                    Text(
                      'Telegram',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(controller.connected ? 'Connected' : 'Not connected'),
                const SizedBox(height: 8),
                const Text(
                  'Telegram adds supported private attachments to Import Inbox. It cannot create financial transactions.',
                ),
                if (controller.error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(error, style: const TextStyle(color: Colors.red)),
                ],
                if (pairing != null) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Send this one-time command to the Pilgrim Tracker bot:',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    pairing.command,
                    key: const Key('telegram-pairing-command'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('Expires ${pairing.expiresAt.toLocal()}'),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: pairing.command),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Pairing command copied.'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy command'),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: controller.loading
                      ? null
                      : controller.connected
                      ? controller.disconnect
                      : controller.connect,
                  child: Text(
                    controller.loading
                        ? 'Please wait…'
                        : controller.connected
                        ? 'Disconnect'
                        : pairing == null
                        ? 'Connect Telegram'
                        : 'Generate new command',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
