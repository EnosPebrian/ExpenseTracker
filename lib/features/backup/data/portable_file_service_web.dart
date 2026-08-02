import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'portable_file_service.dart';

const _browserDestination = PortableDestination(
  displayValue: 'Browser downloads',
  reference: null,
  isValid: true,
);

Future<PortableDestination?> choosePortableDestination(
  PortableDestinationKind kind,
) async => _browserDestination;

Future<PortableDestination?> loadPortableDestination(
  PortableDestinationKind kind,
) async => _browserDestination;

Future<PortableSaveResult?> savePortableFile({
  required PortableDestinationKind kind,
  required PortableDestination destination,
  required String suggestedName,
  required Uint8List bytes,
  required String extension,
  required String dialogTitle,
}) async {
  final saved = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: suggestedName,
    type: FileType.custom,
    allowedExtensions: [extension],
    bytes: bytes,
  );
  if (saved == null) return null;
  return PortableSaveResult(
    fileName: suggestedName,
    destinationDisplayValue: 'Browser downloads',
    fullPathOrUri: null,
    completedAt: DateTime.now(),
    canOpenFolder: false,
    canCopyPath: false,
  );
}

Future<void> openPortableFolder(PortableSaveResult result) async {}

Future<void> copyPortablePath(PortableSaveResult result) async {
  final path = result.fullPathOrUri;
  if (path != null) await Clipboard.setData(ClipboardData(text: path));
}

Future<PickedPortableFile?> openPortableBackup() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['ptbackup'],
    withData: true,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null) {
    throw const PortableFileException('The selected backup could not be read.');
  }
  return PickedPortableFile(name: file.name, bytes: bytes);
}
