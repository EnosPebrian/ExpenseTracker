import 'dart:io';

import 'package:path/path.dart' as p;

class NativeDatabasePath {
  const NativeDatabasePath._();

  static const _applicationDirectoryName = 'Pilgrim Tracker';
  static const _databaseFileName = 'pilgrim_tracker.db';

  static Future<String> resolve({
    Map<String, String>? environment,
    String? workingDirectory,
    String? executableDirectory,
  }) async {
    final env = environment ?? Platform.environment;
    final supportRoot = _supportRoot(env);
    final directory = Directory(p.join(supportRoot, _applicationDirectoryName));
    await directory.create(recursive: true);
    final destination = p.join(directory.path, _databaseFileName);

    if (!await File(destination).exists()) {
      await _adoptLegacyDatabase(
        destination: destination,
        workingDirectory: workingDirectory ?? Directory.current.path,
        executableDirectory:
            executableDirectory ??
            File(Platform.resolvedExecutable).parent.path,
      );
    }
    return destination;
  }

  static String _supportRoot(Map<String, String> environment) {
    if (Platform.isWindows) {
      final appData = environment['APPDATA'];
      if (appData != null && appData.trim().isNotEmpty) return appData;
    }
    if (Platform.isMacOS) {
      final home = environment['HOME'];
      if (home != null && home.trim().isNotEmpty) {
        return p.join(home, 'Library', 'Application Support');
      }
    }
    final xdgDataHome = environment['XDG_DATA_HOME'];
    if (xdgDataHome != null && xdgDataHome.trim().isNotEmpty) {
      return xdgDataHome;
    }
    final home = environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return p.join(home, '.local', 'share');
    }
    throw StateError(
      'Could not locate the per-user application data directory.',
    );
  }

  static Future<void> _adoptLegacyDatabase({
    required String destination,
    required String workingDirectory,
    required String executableDirectory,
  }) async {
    final directories = <String>{workingDirectory, executableDirectory};
    for (final base in directories) {
      final legacyPath = p.join(
        base,
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        _databaseFileName,
      );
      final legacyFile = File(legacyPath);
      if (!await legacyFile.exists() || await legacyFile.length() == 0) {
        continue;
      }
      await legacyFile.copy(destination);
      for (final suffix in const ['-wal', '-shm']) {
        final sidecar = File('$legacyPath$suffix');
        if (await sidecar.exists()) {
          await sidecar.copy('$destination$suffix');
        }
      }
      return;
    }
  }
}
