import 'package:flutter/material.dart';

import 'presentation/screens/app_shell.dart';
import 'theme/app_theme.dart';

class PilgrimApp extends StatelessWidget {
  const PilgrimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pilgrim Tracker',
      debugShowCheckedModeBanner: false,
      theme: PilgrimTheme.light(),
      home: const AppShell(),
    );
  }
}
