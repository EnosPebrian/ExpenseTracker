import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../domain/cloud_models.dart';
import '../domain/cloud_sharing_repository.dart';
import '../../sync/data/supabase_sync_transport.dart';
import '../../sync/data/supabase_initial_sync_transport.dart';
import '../../sync/domain/initial_sync_transport.dart';
import '../../sync/domain/sync_transport.dart';
import 'supabase_cloud_sharing_repository.dart';
import 'unconfigured_cloud_sharing_repository.dart';
import '../../telegram_integration/data/supabase_telegram_integration_repository.dart';
import '../../telegram_integration/domain/telegram_integration_repository.dart';

class CloudSharingBootstrap {
  const CloudSharingBootstrap._();

  static Future<CloudSharingRepository> createRepository() async {
    return (await createServices()).sharingRepository;
  }

  static Future<CloudServices> createServices() async {
    final diagnostics = AppEnvironment.supabaseDiagnostics;
    if (!diagnostics.isValid) {
      return CloudServices(
        sharingRepository: UnconfiguredCloudSharingRepository(
          configurationState: diagnostics.urlPresent && !diagnostics.urlValid
              ? CloudConfigurationState.invalid
              : CloudConfigurationState.unconfigured,
          urlValid: diagnostics.urlValid,
          publishableKeyPresent: diagnostics.publishableKeyPresent,
        ),
        syncTransport: UnavailableSyncTransport(),
        initialSyncTransport: UnavailableInitialSyncTransport(),
        telegramIntegrationRepository:
            const UnavailableTelegramIntegrationRepository(),
      );
    }
    try {
      await Supabase.initialize(
        url: AppEnvironment.supabaseUrl,
        publishableKey: AppEnvironment.supabaseClientKey,
      );
      final client = Supabase.instance.client;
      return CloudServices(
        sharingRepository: SupabaseCloudSharingRepository(client),
        syncTransport: SupabaseSyncTransport(client),
        initialSyncTransport: SupabaseInitialSyncTransport(client),
        telegramIntegrationRepository: SupabaseTelegramIntegrationRepository(
          client,
        ),
      );
    } catch (_) {
      return CloudServices(
        sharingRepository: UnconfiguredCloudSharingRepository(
          configurationState: CloudConfigurationState.failed,
          urlValid: diagnostics.urlValid,
          publishableKeyPresent: diagnostics.publishableKeyPresent,
          configurationError:
              'Cloud sharing is temporarily unavailable. Local finance remains usable.',
        ),
        syncTransport: UnavailableSyncTransport(configured: true),
        initialSyncTransport: UnavailableInitialSyncTransport(configured: true),
        telegramIntegrationRepository:
            const UnavailableTelegramIntegrationRepository(),
      );
    }
  }
}

class CloudServices {
  const CloudServices({
    required this.sharingRepository,
    required this.syncTransport,
    required this.initialSyncTransport,
    required this.telegramIntegrationRepository,
  });

  final CloudSharingRepository sharingRepository;
  final SyncTransport syncTransport;
  final InitialSyncTransport initialSyncTransport;
  final TelegramIntegrationRepository telegramIntegrationRepository;
}
