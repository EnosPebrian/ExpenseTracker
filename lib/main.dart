import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/cloud_sharing/data/cloud_sharing_bootstrap.dart';

export 'app/app.dart' show PilgrimApp;
export 'core/shared/widgets/searchable_dropdown.dart'
    show SearchableDropdown, SearchableSelect;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cloudServices = await CloudSharingBootstrap.createServices();
  runApp(
    PilgrimApp(
      cloudSharingRepository: cloudServices.sharingRepository,
      syncTransport: cloudServices.syncTransport,
      initialSyncTransport: cloudServices.initialSyncTransport,
      telegramIntegrationRepository:
          cloudServices.telegramIntegrationRepository,
    ),
  );
}
