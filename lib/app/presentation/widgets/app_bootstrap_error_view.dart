import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';

class AppBootstrapErrorView extends StatelessWidget {
  const AppBootstrapErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECE7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.storage_rounded,
                          color: Color(0xFFE28068),
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Could not open your local data',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Pilgrim Tracker could not finish loading its '
                        'database. Your existing data has not been deleted.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F3F8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          message,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 10,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onRetry,
                          style: FilledButton.styleFrom(
                            backgroundColor: violet,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text(
                            'Try again',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
