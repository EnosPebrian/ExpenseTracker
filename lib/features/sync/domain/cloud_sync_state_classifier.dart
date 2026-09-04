import '../../master_data/domain/entities/financial_book.dart';
import 'initial_sync_models.dart';
import 'sync_models.dart';

enum CloudSyncClassification {
  alreadySynced,
  reconnectSameHostedHousehold,
  downloadAdditionalHostedHousehold,
  genuinePrimaryUploadRequired,
  authenticationRequired,
  membershipRequired,
  remoteStateChecking,
  blocked,
}

class CloudSyncDecision {
  const CloudSyncDecision(
    this.classification, {
    required this.reason,
    this.targetBookId,
  });

  final CloudSyncClassification classification;
  final String reason;
  final String? targetBookId;

  bool get isReconnect =>
      classification == CloudSyncClassification.reconnectSameHostedHousehold ||
      classification ==
          CloudSyncClassification.downloadAdditionalHostedHousehold;
}

class CloudSyncStateClassifier {
  const CloudSyncStateClassifier();

  CloudSyncDecision classify({
    required bool cloudConfigured,
    required bool remoteStateLoaded,
    required bool authenticated,
    required FinancialBook? localBook,
    required bool matchingMembershipIsOwner,
    required List<String> hostedBookIds,
    required Map<String, InitialSyncManifest> remoteManifests,
    required Set<String> failedManifestBookIds,
    required SyncCursor? localCursor,
    String? preferredAdditionalBookId,
    String? remoteStateError,
  }) {
    if (!cloudConfigured) {
      return const CloudSyncDecision(
        CloudSyncClassification.blocked,
        reason: 'cloud-not-configured',
      );
    }
    if (!remoteStateLoaded) {
      return const CloudSyncDecision(
        CloudSyncClassification.remoteStateChecking,
        reason: 'remote-state-not-loaded',
      );
    }
    if (!authenticated) {
      return const CloudSyncDecision(
        CloudSyncClassification.authenticationRequired,
        reason: 'authentication-required',
      );
    }
    if (remoteStateError != null) {
      return const CloudSyncDecision(
        CloudSyncClassification.blocked,
        reason: 'remote-membership-error',
      );
    }
    if (hostedBookIds.isEmpty) {
      return const CloudSyncDecision(
        CloudSyncClassification.membershipRequired,
        reason: 'active-membership-required',
      );
    }

    final localBookId = localBook?.id;
    final matchingHosted =
        localBookId != null && hostedBookIds.contains(localBookId);
    if (matchingHosted) {
      if (failedManifestBookIds.contains(localBookId)) {
        return CloudSyncDecision(
          CloudSyncClassification.blocked,
          reason: 'matching-remote-manifest-failed',
          targetBookId: localBookId,
        );
      }
      final manifest = remoteManifests[localBookId];
      if (manifest == null) {
        return CloudSyncDecision(
          CloudSyncClassification.remoteStateChecking,
          reason: 'matching-remote-manifest-pending',
          targetBookId: localBookId,
        );
      }
      if (manifest.remoteInitializationComplete) {
        final incrementallyReady =
            localBook?.remoteLinkedAt != null &&
            localCursor?.initializationState == SyncInitializationState.ready;
        return CloudSyncDecision(
          incrementallyReady
              ? CloudSyncClassification.alreadySynced
              : CloudSyncClassification.reconnectSameHostedHousehold,
          reason: incrementallyReady
              ? 'matching-remote-initialized-and-local-ready'
              : 'matching-remote-initialized-local-not-ready',
          targetBookId: localBookId,
        );
      }
      if (!matchingMembershipIsOwner) {
        return CloudSyncDecision(
          CloudSyncClassification.blocked,
          reason: 'uninitialized-remote-requires-owner',
          targetBookId: localBookId,
        );
      }
      return CloudSyncDecision(
        CloudSyncClassification.genuinePrimaryUploadRequired,
        reason: 'authoritative-remote-uninitialized',
        targetBookId: localBookId,
      );
    }

    final additionalBookIds = <String>[
      if (preferredAdditionalBookId != null &&
          hostedBookIds.contains(preferredAdditionalBookId))
        preferredAdditionalBookId,
      ...hostedBookIds.where((bookId) => bookId != preferredAdditionalBookId),
    ];
    for (final bookId in additionalBookIds) {
      final manifest = remoteManifests[bookId];
      if (manifest?.remoteInitializationComplete == true) {
        return CloudSyncDecision(
          CloudSyncClassification.downloadAdditionalHostedHousehold,
          reason: 'initialized-additional-hosted-household',
          targetBookId: bookId,
        );
      }
    }
    if (failedManifestBookIds.isNotEmpty) {
      return const CloudSyncDecision(
        CloudSyncClassification.blocked,
        reason: 'hosted-manifest-failed',
      );
    }
    return const CloudSyncDecision(
      CloudSyncClassification.blocked,
      reason: 'no-initialized-hosted-household',
    );
  }
}
