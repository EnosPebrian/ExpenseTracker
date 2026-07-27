import 'package:flutter/material.dart';

import 'presentation/screens/app_shell.dart';
import 'theme/app_theme.dart';
import '../features/cloud_sharing/data/unconfigured_cloud_sharing_repository.dart';
import '../features/cloud_sharing/domain/cloud_sharing_repository.dart';
import '../features/sync/domain/sync_transport.dart';
import '../features/sync/domain/initial_sync_transport.dart';

class PilgrimApp extends StatelessWidget {
  const PilgrimApp({
    super.key,
    this.cloudSharingRepository = const UnconfiguredCloudSharingRepository(),
    this.syncTransport = const UnavailableSyncTransport(),
    this.initialSyncTransport = const UnavailableInitialSyncTransport(),
  });

  final CloudSharingRepository cloudSharingRepository;
  final SyncTransport syncTransport;
  final InitialSyncTransport initialSyncTransport;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pilgrim Tracker',
      debugShowCheckedModeBanner: false,
      theme: PilgrimTheme.light(),
      home: AppShell(
        cloudSharingRepository: cloudSharingRepository,
        syncTransport: syncTransport,
        initialSyncTransport: initialSyncTransport,
      ),
    );
  }
}
