import 'dart:typed_data';

import 'portable_file_service_native.dart'
    if (dart.library.html) 'portable_file_service_web.dart'
    as platform;

enum PortableDestinationKind { backup, csv }

class PortableDestination {
  const PortableDestination({
    required this.displayValue,
    required this.reference,
    required this.isValid,
  });

  final String displayValue;
  final String? reference;
  final bool isValid;
}

class PortableSaveResult {
  const PortableSaveResult({
    required this.fileName,
    required this.destinationDisplayValue,
    required this.completedAt,
    required this.canOpenFolder,
    required this.canCopyPath,
    this.fullPathOrUri,
    this.recordCount = 0,
  });

  final String fileName;
  final String destinationDisplayValue;
  final String? fullPathOrUri;
  final DateTime completedAt;
  final bool canOpenFolder;
  final bool canCopyPath;
  final int recordCount;

  PortableSaveResult withRecordCount(int value) => PortableSaveResult(
    fileName: fileName,
    destinationDisplayValue: destinationDisplayValue,
    completedAt: completedAt,
    canOpenFolder: canOpenFolder,
    canCopyPath: canCopyPath,
    fullPathOrUri: fullPathOrUri,
    recordCount: value,
  );
}

class PickedPortableFile {
  const PickedPortableFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class PortableFileException implements Exception {
  const PortableFileException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PortableFileService {
  const PortableFileService();

  Future<PortableDestination?> chooseDestination(
    PortableDestinationKind kind,
  ) => platform.choosePortableDestination(kind);

  Future<PortableDestination?> rememberedDestination(
    PortableDestinationKind kind,
  ) => platform.loadPortableDestination(kind);

  Future<PortableSaveResult?> save({
    required PortableDestinationKind kind,
    required PortableDestination destination,
    required String suggestedName,
    required Uint8List bytes,
    required String extension,
    required String dialogTitle,
  }) async {
    if (!destination.isValid) {
      throw const PortableFileException('Choose a valid destination first.');
    }
    if (!hasExtension(suggestedName, extension)) {
      throw PortableFileException('The file name must end in .$extension.');
    }
    final saved = await platform.savePortableFile(
      kind: kind,
      destination: destination,
      suggestedName: suggestedName,
      bytes: bytes,
      extension: extension,
      dialogTitle: dialogTitle,
    );
    if (saved?.fullPathOrUri case final path?) {
      if (!hasExtension(path, extension)) {
        throw PortableFileException(
          'The selected file must end in .$extension.',
        );
      }
    }
    return saved;
  }

  Future<void> openFolder(PortableSaveResult result) =>
      platform.openPortableFolder(result);

  Future<void> copyPath(PortableSaveResult result) =>
      platform.copyPortablePath(result);

  Future<PickedPortableFile?> openBackup() async {
    final picked = await platform.openPortableBackup();
    if (picked != null && !hasExtension(picked.name, 'ptbackup')) {
      throw const PortableFileException(
        'Select a Pilgrim Tracker .ptbackup file.',
      );
    }
    return picked;
  }

  static bool hasExtension(String path, String extension) =>
      path.toLowerCase().endsWith('.${extension.toLowerCase()}');

  static String collisionSafeName(
    String suggestedName,
    Set<String> existingNames,
  ) {
    if (!existingNames.contains(suggestedName)) return suggestedName;
    final dot = suggestedName.lastIndexOf('.');
    final stem = dot <= 0 ? suggestedName : suggestedName.substring(0, dot);
    final extension = dot <= 0 ? '' : suggestedName.substring(dot);
    for (var suffix = 2; suffix < 10000; suffix++) {
      final candidate = '$stem-$suffix$extension';
      if (!existingNames.contains(candidate)) return candidate;
    }
    throw const PortableFileException('No available file name was found.');
  }
}
