class TelegramConnectionStatus {
  const TelegramConnectionStatus({required this.connected, this.connectedAt});

  final bool connected;
  final DateTime? connectedAt;
}

class TelegramPairingCommand {
  const TelegramPairingCommand({
    required this.command,
    required this.expiresAt,
  });

  final String command;
  final DateTime expiresAt;
}

class TelegramIntegrationException implements Exception {
  const TelegramIntegrationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class TelegramIntegrationRepository {
  Future<TelegramConnectionStatus> status(String bookId);

  Future<TelegramPairingCommand> generatePairingCommand({
    required String bookId,
    required String memberId,
  });

  Future<void> disconnect(String bookId);
}

class UnavailableTelegramIntegrationRepository
    implements TelegramIntegrationRepository {
  const UnavailableTelegramIntegrationRepository();

  static const _message =
      'Telegram connection status requires internet and configured cloud sharing.';

  @override
  Future<void> disconnect(String bookId) =>
      Future<void>.error(const TelegramIntegrationException(_message));

  @override
  Future<TelegramPairingCommand> generatePairingCommand({
    required String bookId,
    required String memberId,
  }) => Future<TelegramPairingCommand>.error(
    const TelegramIntegrationException(_message),
  );

  @override
  Future<TelegramConnectionStatus> status(String bookId) =>
      Future<TelegramConnectionStatus>.error(
        const TelegramIntegrationException(_message),
      );
}
