import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/telegram_integration_repository.dart';

class TelegramIntegrationController extends ChangeNotifier {
  TelegramIntegrationController(
    this._repository, {
    required this.bookId,
    required this.memberId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final TelegramIntegrationRepository _repository;
  final String bookId;
  final String memberId;
  final DateTime Function() _now;

  bool loading = false;
  bool connected = false;
  String? error;
  TelegramPairingCommand? pairing;
  Timer? _expiryTimer;

  Future<void> load() => _run(() async {
    final result = await _repository.status(bookId);
    connected = result.connected;
    if (connected) _clearPairing();
  });

  Future<void> connect() => _run(() async {
    final result = await _repository.generatePairingCommand(
      bookId: bookId,
      memberId: memberId,
    );
    pairing = result;
    _expiryTimer?.cancel();
    final delay = result.expiresAt.difference(_now());
    _expiryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _clearPairing();
      notifyListeners();
    });
  });

  Future<void> disconnect() => _run(() async {
    await _repository.disconnect(bookId);
    connected = false;
    _clearPairing();
  });

  Future<void> _run(Future<void> Function() action) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on TelegramIntegrationException catch (exception) {
      error = exception.message;
    } catch (_) {
      error = 'Telegram connection is temporarily unavailable.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _clearPairing() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    pairing = null;
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
