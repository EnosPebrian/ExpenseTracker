import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/core/database/native_database_path.dart';

void main() {
  test('default database path is stable across working directories', () async {
    final root = await Directory.systemTemp.createTemp('pilgrim-path-');
    addTearDown(() => root.delete(recursive: true));
    final appData = p.join(root.path, 'app-data');

    final first = await NativeDatabasePath.resolve(
      environment: {'APPDATA': appData, 'HOME': appData},
      workingDirectory: p.join(root.path, 'first'),
      executableDirectory: p.join(root.path, 'bin'),
    );
    final second = await NativeDatabasePath.resolve(
      environment: {'APPDATA': appData, 'HOME': appData},
      workingDirectory: p.join(root.path, 'second'),
      executableDirectory: p.join(root.path, 'other-bin'),
    );

    expect(first, second);
    expect(first, p.join(appData, 'Pilgrim Tracker', 'pilgrim_tracker.db'));
  });

  test(
    'adopts a known legacy database only when destination is absent',
    () async {
      final root = await Directory.systemTemp.createTemp('pilgrim-adopt-');
      addTearDown(() => root.delete(recursive: true));
      final appData = p.join(root.path, 'app-data');
      final working = p.join(root.path, 'working');
      final legacy = File(
        p.join(
          working,
          '.dart_tool',
          'sqflite_common_ffi',
          'databases',
          'pilgrim_tracker.db',
        ),
      );
      await legacy.parent.create(recursive: true);
      await legacy.writeAsString('legacy-data');

      final destination = await NativeDatabasePath.resolve(
        environment: {'APPDATA': appData, 'HOME': appData},
        workingDirectory: working,
        executableDirectory: p.join(root.path, 'bin'),
      );
      expect(await File(destination).readAsString(), 'legacy-data');

      await File(destination).writeAsString('existing-data');
      await legacy.writeAsString('changed-legacy-data');
      await NativeDatabasePath.resolve(
        environment: {'APPDATA': appData, 'HOME': appData},
        workingDirectory: working,
        executableDirectory: p.join(root.path, 'bin'),
      );
      expect(await File(destination).readAsString(), 'existing-data');
    },
  );
}
