import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'portable_file_service.dart';

Future<PortableDestination?> choosePortableDestination(
  PortableDestinationKind kind,
) async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return const PortableDestination(
      displayValue: 'System document picker',
      reference: null,
      isValid: true,
    );
  }
  final selected = await FilePicker.platform.getDirectoryPath(
    dialogTitle: switch (kind) {
      PortableDestinationKind.backup => 'Choose encrypted backup folder',
      PortableDestinationKind.csv => 'Choose CSV export folder',
      PortableDestinationKind.statement => 'Choose statement export folder',
    },
    lockParentWindow: Platform.isWindows,
  );
  if (selected == null) return null;
  final destination = await _validatedDirectory(selected);
  return destination;
}

Future<PortableDestination?> loadPortableDestination(
  PortableDestinationKind kind,
) async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return const PortableDestination(
      displayValue: 'System document picker',
      reference: null,
      isValid: true,
    );
  }
  final file = _preferencesFile();
  if (!await file.exists()) return null;
  try {
    final values = Map<String, Object?>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
    final path = values[_key(kind)] as String?;
    return path == null ? null : _validatedDirectory(path);
  } catch (_) {
    return null;
  }
}

Future<PortableSaveResult?> savePortableFile({
  required PortableDestinationKind kind,
  required PortableDestination destination,
  required String suggestedName,
  required Uint8List bytes,
  required String extension,
  required String dialogTitle,
}) async {
  if (destination.reference == null) {
    final selected = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes,
    );
    if (selected == null) return null;
    return PortableSaveResult(
      fileName: p.basename(selected),
      destinationDisplayValue: 'System document picker',
      fullPathOrUri: selected,
      completedAt: DateTime.now(),
      canOpenFolder: false,
      canCopyPath: selected.isNotEmpty,
    );
  }

  final selected = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: suggestedName,
    initialDirectory: destination.reference,
    type: FileType.custom,
    allowedExtensions: [extension],
    lockParentWindow: Platform.isWindows,
  );
  if (selected == null) return null;
  if (!PortableFileService.hasExtension(selected, extension)) {
    throw PortableFileException('The selected file must end in .$extension.');
  }

  final selectedFile = File(selected);
  final directory = selectedFile.parent;
  if (!await directory.exists()) {
    throw const PortableFileException(
      'The selected destination is no longer available.',
    );
  }
  final target = await _availableTarget(
    directory.path,
    p.basename(selectedFile.path),
  );
  final temporary = File(
    '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
  await _remember(kind, directory.path);
  return PortableSaveResult(
    fileName: p.basename(target.path),
    destinationDisplayValue: directory.path,
    fullPathOrUri: target.path,
    completedAt: DateTime.now(),
    canOpenFolder: Platform.isWindows,
    canCopyPath: true,
  );
}

Future<void> openPortableFolder(PortableSaveResult result) async {
  final path = result.fullPathOrUri;
  if (!Platform.isWindows || path == null) return;
  await Process.start('explorer.exe', ['/select,', path]);
}

Future<void> copyPortablePath(PortableSaveResult result) async {
  final path = result.fullPathOrUri;
  if (path != null) await Clipboard.setData(ClipboardData(text: path));
}

Future<PickedPortableFile?> openPortableBackup() async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'Open Pilgrim Tracker backup',
    type: FileType.custom,
    allowedExtensions: const ['ptbackup'],
    withData: true,
    allowMultiple: false,
    lockParentWindow: Platform.isWindows,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes =
      file.bytes ??
      (file.path == null ? null : await File(file.path!).readAsBytes());
  if (bytes == null) {
    throw const PortableFileException('The selected backup could not be read.');
  }
  return PickedPortableFile(name: file.name, bytes: bytes);
}

Future<PortableDestination?> _validatedDirectory(String path) async {
  final directory = Directory(path);
  if (!await directory.exists()) return null;
  return PortableDestination(
    displayValue: directory.path,
    reference: directory.path,
    isValid: true,
  );
}

Future<File> _availableTarget(String directory, String suggestedName) async {
  final names = await Directory(
    directory,
  ).list().map((entity) => p.basename(entity.path)).toSet();
  return File(
    p.join(
      directory,
      PortableFileService.collisionSafeName(suggestedName, names),
    ),
  );
}

Future<void> _remember(PortableDestinationKind kind, String directory) async {
  final file = _preferencesFile();
  await file.parent.create(recursive: true);
  var values = <String, Object?>{};
  if (await file.exists()) {
    try {
      values = Map<String, Object?>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
    } catch (_) {
      values = {};
    }
  }
  values[_key(kind)] = directory;
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(jsonEncode(values), flush: true);
  if (await file.exists()) {
    await file.delete();
  }
  await temporary.rename(file.path);
}

String _key(PortableDestinationKind kind) => switch (kind) {
  PortableDestinationKind.backup => 'backupDestination',
  PortableDestinationKind.csv => 'csvDestination',
  PortableDestinationKind.statement => 'statementDestination',
};

File _preferencesFile() {
  final root = Platform.isWindows
      ? Platform.environment['APPDATA']
      : Platform.environment['HOME'];
  if (root == null || root.trim().isEmpty) {
    throw const PortableFileException(
      'The application data folder is unavailable.',
    );
  }
  return File(p.join(root, 'Pilgrim Tracker', 'export_destinations.json'));
}
