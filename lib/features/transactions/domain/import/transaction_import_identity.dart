import 'package:uuid/uuid.dart';

/// The one canonical BETA-08B financial transaction identity algorithm.
class TransactionImportIdentity {
  const TransactionImportIdentity._();

  static const namespace = 'c76551e2-47f7-5a64-8d32-9423217b95b1';

  static String derive({
    required String bookId,
    required String accountId,
    required String sourceFingerprint,
    required Object sourceRowIdentity,
    required String sourceRowFingerprint,
  }) => const Uuid().v5(
    namespace,
    '$bookId|$accountId|$sourceFingerprint|$sourceRowIdentity|'
    '$sourceRowFingerprint',
  );
}
