import 'package:flutter/material.dart';

import '../../domain/entities/local_profile.dart';

class LocalProfileSetupPage extends StatefulWidget {
  const LocalProfileSetupPage({super.key, required this.onSave});

  final Future<void> Function(LocalProfile profile) onSave;

  @override
  State<LocalProfileSetupPage> createState() => _LocalProfileSetupPageState();
}

class _LocalProfileSetupPageState extends State<LocalProfileSetupPage> {
  final _nameController = TextEditingController();
  final _currencyController = TextEditingController(text: 'IDR');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final currency = _currencyController.text.trim().toUpperCase();
    if (name.isEmpty || currency.isEmpty) {
      setState(
        () => _error = 'Display name and default currency are required.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        LocalProfile(displayName: name, defaultCurrencyCode: currency),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Set up your local profile',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This profile stays on this device. It is not secure '
                      'authentication or an online account.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      key: const Key('profile-display-name-field'),
                      controller: _nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('profile-currency-field'),
                      controller: _currencyController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 3,
                      decoration: const InputDecoration(
                        labelText: 'Default currency',
                        counterText: '',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('save-local-profile-button'),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving' : 'Continue'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
