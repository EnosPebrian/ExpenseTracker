import 'package:uuid/uuid.dart';

/// Stable identities for reviewed brokerage statement events and child rows.
class BrokerageImportIdentity {
  const BrokerageImportIdentity._();

  static const namespace = '2170d38b-e8e9-5bcb-a84d-0d4e1a610586';

  static String event({
    required String bookId,
    required String brokerageAccountId,
    required String sourceFingerprint,
    required Object sourceRowIdentity,
    required String sourceRowFingerprint,
  }) => const Uuid().v5(
    namespace,
    '$bookId|$brokerageAccountId|$sourceFingerprint|$sourceRowIdentity|'
    '$sourceRowFingerprint',
  );

  static String child(String eventId, String role) =>
      const Uuid().v5(namespace, '$eventId|$role');

  static String instrument({
    required String bookId,
    required String symbol,
    required String currencyCode,
  }) => const Uuid().v5(
    namespace,
    '$bookId|instrument|${symbol.trim().toUpperCase()}|'
    '${currencyCode.trim().toUpperCase()}',
  );
}
