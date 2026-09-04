import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/telegram_integration_repository.dart';

class SupabaseTelegramIntegrationRepository
    implements TelegramIntegrationRepository {
  SupabaseTelegramIntegrationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<TelegramConnectionStatus> status(String bookId) async {
    final data = await _invoke({'operation': 'status', 'book_id': bookId});
    final connectedAt = data['connected_at'] as String?;
    return TelegramConnectionStatus(
      connected: data['connected'] == true,
      connectedAt: connectedAt == null ? null : DateTime.parse(connectedAt),
    );
  }

  @override
  Future<TelegramPairingCommand> generatePairingCommand({
    required String bookId,
    required String memberId,
  }) async {
    final data = await _invoke({
      'operation': 'generate',
      'book_id': bookId,
      'member_id': memberId,
    });
    final command = data['command'];
    final expiresAt = data['expires_at'];
    if (command is! String || expiresAt is! String) {
      throw const TelegramIntegrationException(
        'Telegram pairing is temporarily unavailable.',
      );
    }
    return TelegramPairingCommand(
      command: command,
      expiresAt: DateTime.parse(expiresAt),
    );
  }

  @override
  Future<void> disconnect(String bookId) async {
    await _invoke({'operation': 'disconnect', 'book_id': bookId});
  }

  Future<Map<String, Object?>> _invoke(Map<String, Object?> body) async {
    try {
      if (_client.auth.currentUser == null) {
        throw const TelegramIntegrationException(
          'Sign in to cloud sharing before connecting Telegram.',
        );
      }
      final response = await _client.functions.invoke(
        'telegram-connection',
        body: body,
      );
      if (response.status < 200 ||
          response.status >= 300 ||
          response.data is! Map) {
        throw const TelegramIntegrationException(
          'Telegram connection is temporarily unavailable.',
        );
      }
      return (response.data as Map).cast<String, Object?>();
    } on TelegramIntegrationException {
      rethrow;
    } catch (_) {
      throw const TelegramIntegrationException(
        'Telegram connection status requires internet.',
      );
    }
  }
}
