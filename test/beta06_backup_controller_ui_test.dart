import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/backup/data/portable_file_service.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_integrity.dart';
import 'package:pilgrim_tracker/features/backup/domain/household_backup_service.dart';
import 'package:pilgrim_tracker/features/backup/presentation/controllers/backup_export_controller.dart';
import 'package:pilgrim_tracker/features/backup/presentation/screens/backup_export_screen.dart';
import 'package:pilgrim_tracker/features/backup/presentation/widgets/backup_destination_widgets.dart';

import 'support/beta06_fixture.dart';

void main() {
  testWidgets('backup screen exposes recovery, restore, and CSV actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _MemoryStore();
    final controller = BackupExportController(
      backupService: HouseholdBackupService(store),
      fileService: _FakeFiles(),
    );
    addTearDown(controller.dispose);
    await controller.load('book-beta06');

    await tester.pumpWidget(
      MaterialApp(home: BackupExportScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backup & Export'), findsOneWidget);
    expect(find.text('Create encrypted backup'), findsOneWidget);
    expect(find.text('Select .ptbackup'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Export CSV ZIP'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Export CSV ZIP'), findsOneWidget);
    expect(find.textContaining('cannot be recovered'), findsOneWidget);
    expect(find.textContaining('2 transactions selected'), findsOneWidget);
  });

  test(
    'replacement is blocked when the safety backup save is cancelled',
    () async {
      final store = _MemoryStore();
      final service = HouseholdBackupService(store);
      final portable = await service.create(
        bookId: 'book-beta06',
        password: 'strong-password',
      );
      store.data = HouseholdBackupIntegrity.prepareForRestore(store.data);
      final files = _FakeFiles(
        picked: PickedPortableFile(
          name: 'test.ptbackup',
          bytes: portable.bytes,
        ),
        cancelSave: true,
      );
      final controller = BackupExportController(
        backupService: service,
        fileService: files,
      );
      addTearDown(controller.dispose);
      await controller.load('book-beta06');
      await controller.pickBackup();
      await controller.validateSelectedBackup('strong-password');
      await controller.restoreValidated(
        mode: RestoreMode.replaceMatchingHousehold,
        safetyBackupPassword: 'safety-password',
        confirmedHouseholdName: 'Beta Household',
      );

      expect(controller.error, contains('safety backup was not saved'));
      expect(store.activationCount, 0);
      expect(files.saveCalls, 1);
    },
  );

  test(
    'invalid replacement preflight never opens the safety-backup dialog',
    () async {
      final store = _MemoryStore();
      final service = HouseholdBackupService(store);
      final portable = await service.create(
        bookId: 'book-beta06',
        password: 'strong-password',
      );
      final files = _FakeFiles(
        picked: PickedPortableFile(
          name: 'test.ptbackup',
          bytes: portable.bytes,
        ),
      );
      final controller = BackupExportController(
        backupService: service,
        fileService: files,
      );
      addTearDown(controller.dispose);
      await controller.load('book-beta06');
      await controller.pickBackup();
      await controller.validateSelectedBackup(
        'strong-password',
        mode: RestoreMode.replaceMatchingHousehold,
      );
      controller.validatedBackup!.snapshot['accounts']!.first['book_id'] =
          'foreign-book';

      await controller.restoreValidated(
        mode: RestoreMode.replaceMatchingHousehold,
        safetyBackupPassword: 'safety-password',
        confirmedHouseholdName: 'Beta Household',
      );

      expect(controller.error, contains('foreign-household'));
      expect(files.saveCalls, 0);
      expect(store.activationCount, 0);
    },
  );

  test('failed safety-backup write leaves the household unchanged', () async {
    final store = _MemoryStore();
    final before = store.data.toString();
    final service = HouseholdBackupService(store);
    final portable = await service.create(
      bookId: 'book-beta06',
      password: 'strong-password',
    );
    final controller = BackupExportController(
      backupService: service,
      fileService: _FakeFiles(
        picked: PickedPortableFile(
          name: 'test.ptbackup',
          bytes: portable.bytes,
        ),
        throwOnSave: true,
      ),
    );
    addTearDown(controller.dispose);
    await controller.load('book-beta06');
    await controller.pickBackup();
    await controller.validateSelectedBackup(
      'strong-password',
      mode: RestoreMode.replaceMatchingHousehold,
    );

    await controller.restoreValidated(
      mode: RestoreMode.replaceMatchingHousehold,
      safetyBackupPassword: 'safety-password',
      confirmedHouseholdName: 'Beta Household',
    );

    expect(controller.error, contains('Write failed'));
    expect(store.activationCount, 0);
    expect(store.data.toString(), before);
  });

  test('successful safety backup proceeds to atomic replacement', () async {
    final store = _MemoryStore();
    final service = HouseholdBackupService(store);
    final portable = await service.create(
      bookId: 'book-beta06',
      password: 'strong-password',
    );
    final files = _FakeFiles(
      picked: PickedPortableFile(name: 'test.ptbackup', bytes: portable.bytes),
    );
    final controller = BackupExportController(
      backupService: service,
      fileService: files,
    );
    addTearDown(controller.dispose);
    await controller.load('book-beta06');
    await controller.pickBackup();
    await controller.validateSelectedBackup(
      'strong-password',
      mode: RestoreMode.replaceMatchingHousehold,
    );

    await controller.restoreValidated(
      mode: RestoreMode.replaceMatchingHousehold,
      safetyBackupPassword: 'safety-password',
      confirmedHouseholdName: 'Beta Household',
    );

    expect(files.saveCalls, 1);
    expect(store.activationCount, 1);
    expect(store.lastReplaceBookId, 'book-beta06');
    expect(controller.restoreNotice, contains('local-only'));
  });

  testWidgets('replacement preview uses replacement-specific copy', (
    tester,
  ) async {
    const preview = RestorePreview(
      mode: RestoreMode.replaceMatchingHousehold,
      newByEntity: {'accounts': 1},
      identicalByEntity: {'members': 2},
      replacementByEntity: {'transactions': 3},
      conflictingByEntity: {},
      invalidByEntity: {},
      expectedFinalTotals: {'accounts': 1, 'members': 2, 'transactions': 3},
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RestorePreviewPanel(preview: preview)),
      ),
    );

    expect(find.text('Records to replace: 3'), findsOneWidget);
    expect(find.text('Records unchanged: 2'), findsOneWidget);
    expect(find.text('New supporting records: 1'), findsOneWidget);
    expect(find.text('Blocking integrity errors: 0'), findsOneWidget);
    expect(find.text('Expected final total: 6'), findsOneWidget);
  });

  test('missing category requires confirmation then permits backup', () async {
    final store = _MemoryStore();
    store.data['transactions']!.first['category'] = 'Removed category';
    final files = _FakeFiles();
    final controller = BackupExportController(
      backupService: HouseholdBackupService(store),
      fileService: files,
    );
    addTearDown(controller.dispose);
    await controller.load('book-beta06');
    await controller.createEncryptedBackup(
      password: 'strong-password',
      confirmation: 'strong-password',
    );
    expect(controller.backupNotice, contains('Confirm the warning'));
    expect(files.saveCalls, 0);
    await controller.createEncryptedBackup(
      password: 'strong-password',
      confirmation: 'strong-password',
      confirmWarnings: true,
    );
    expect(files.saveCalls, 1);
    expect(controller.backupNotice, contains('successfully'));
  });

  test('portable extension checks reject unrelated restore files', () {
    expect(
      PortableFileService.hasExtension('backup.ptbackup', 'ptbackup'),
      isTrue,
    );
    expect(PortableFileService.hasExtension('photo.jpg', 'ptbackup'), isFalse);
    expect(PortableFileService.hasExtension('photo.jpeg', 'ptbackup'), isFalse);
    expect(PortableFileService.hasExtension('image.png', 'ptbackup'), isFalse);
    expect(PortableFileService.hasExtension('report.pdf', 'ptbackup'), isFalse);
    expect(PortableFileService.hasExtension('export.zip', 'ptbackup'), isFalse);
    expect(PortableFileService.hasExtension('backup.ptbackup', 'zip'), isFalse);
    expect(PortableFileService.hasExtension('export.zip', 'zip'), isTrue);
  });

  test('backup busy state blocks repeat submission', () async {
    final saveGate = Completer<void>();
    final files = _FakeFiles(saveGate: saveGate);
    final controller = BackupExportController(
      backupService: HouseholdBackupService(_MemoryStore()),
      fileService: files,
    );
    addTearDown(controller.dispose);
    await controller.load('book-beta06');

    final first = controller.createEncryptedBackup(
      password: 'strong-password',
      confirmation: 'strong-password',
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isTrue);
    expect(controller.activeAction, BackupAction.backup);
    final second = controller.createEncryptedBackup(
      password: 'strong-password',
      confirmation: 'strong-password',
    );
    for (var attempt = 0; attempt < 500 && files.saveCalls == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(files.saveCalls, 1);

    saveGate.complete();
    await Future.wait([first, second]);
    expect(controller.busy, isFalse);
    expect(files.saveCalls, 1);
  });

  test(
    'backup and CSV cancellation are reported beside their actions',
    () async {
      final controller = BackupExportController(
        backupService: HouseholdBackupService(_MemoryStore()),
        fileService: _FakeFiles(cancelSave: true),
      );
      addTearDown(controller.dispose);
      await controller.load('book-beta06');
      await controller.createEncryptedBackup(
        password: 'strong-password',
        confirmation: 'strong-password',
      );
      expect(controller.backupNotice, 'Backup save cancelled.');

      await controller.exportCsv(const CsvExportFilter());
      expect(controller.csvNotice, 'CSV export save cancelled.');
    },
  );

  test('CSV busy state blocks repeat submission', () async {
    final saveGate = Completer<void>();
    final files = _FakeFiles(saveGate: saveGate);
    final controller = BackupExportController(
      backupService: HouseholdBackupService(_MemoryStore()),
      fileService: files,
    );
    addTearDown(controller.dispose);
    await controller.load('book-beta06');

    final first = controller.exportCsv(const CsvExportFilter());
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isTrue);
    final second = controller.exportCsv(const CsvExportFilter());
    await Future<void>.delayed(Duration.zero);
    expect(files.saveCalls, 1);

    saveGate.complete();
    await Future.wait([first, second]);
    expect(controller.busy, isFalse);
    expect(files.saveCalls, 1);
  });

  test(
    'destinations, timestamp names, completion, and copy are explicit',
    () async {
      final files = _FakeFiles();
      final controller = BackupExportController(
        backupService: HouseholdBackupService(_MemoryStore()),
        fileService: files,
        now: () => DateTime(2026, 7, 31, 14, 5, 9),
      );
      addTearDown(controller.dispose);
      await controller.load('book-beta06');
      expect(
        controller.backupFileName,
        'pilgrim-tracker-backup-20260731-140509.ptbackup',
      );
      expect(
        controller.csvFileName,
        'pilgrim-tracker-export-20260731-140509.zip',
      );
      expect(
        controller.canCreateBackup(
          password: 'strong-password',
          confirmation: 'strong-password',
          confirmWarnings: false,
        ),
        isTrue,
      );
      await controller.createEncryptedBackup(
        password: 'strong-password',
        confirmation: 'strong-password',
      );
      expect(
        controller.backupResult?.fullPathOrUri,
        r'C:\Exports\pilgrim-tracker-backup-20260731-140509.ptbackup',
      );
      await controller.copyBackupPath();
      expect(
        files.copied,
        r'C:\Exports\pilgrim-tracker-backup-20260731-140509.ptbackup',
      );
    },
  );

  test('missing or invalid remembered destination disables export', () async {
    final files = _FakeFiles(hasRemembered: false);
    final controller = BackupExportController(
      backupService: HouseholdBackupService(_MemoryStore()),
      fileService: files,
    );
    addTearDown(controller.dispose);
    await controller.load('book-beta06');
    expect(controller.backupDestination, isNull);
    expect(controller.canExportCsv(confirmWarnings: false), isFalse);
    await controller.chooseCsvDestination();
    expect(controller.csvDestination?.displayValue, r'C:\Chosen');
  });

  test(
    'cancelled destination selection retains the previous destination',
    () async {
      final files = _FakeFiles(cancelChoose: true);
      final controller = BackupExportController(
        backupService: HouseholdBackupService(_MemoryStore()),
        fileService: files,
      );
      addTearDown(controller.dispose);
      await controller.load('book-beta06');
      final before = controller.backupDestination;
      await controller.chooseBackupDestination();
      expect(controller.backupDestination, same(before));
    },
  );

  test('collision suffixes never silently overwrite', () {
    expect(
      PortableFileService.collisionSafeName(
        'pilgrim-tracker-export-20260731-140509.zip',
        {
          'pilgrim-tracker-export-20260731-140509.zip',
          'pilgrim-tracker-export-20260731-140509-2.zip',
        },
      ),
      'pilgrim-tracker-export-20260731-140509-3.zip',
    );
  });

  test('CSV completion uses the exact saved location', () async {
    final files = _FakeFiles();
    final controller = BackupExportController(
      backupService: HouseholdBackupService(_MemoryStore()),
      fileService: files,
      now: () => DateTime(2026, 7, 31, 15, 30),
    );
    addTearDown(controller.dispose);
    await controller.load('book-beta06');
    await controller.exportCsv(const CsvExportFilter());

    expect(
      controller.csvResult?.fullPathOrUri,
      r'C:\Exports\pilgrim-tracker-export-20260731-153000.zip',
    );
    expect(controller.csvTransactionCount, 2);
    expect(controller.csvResult?.canOpenFolder, isTrue);
    expect(controller.csvResult?.canCopyPath, isTrue);
  });

  test('write failure never creates a false completion result', () async {
    final controller = BackupExportController(
      backupService: HouseholdBackupService(_MemoryStore()),
      fileService: _FakeFiles(throwOnSave: true),
    );
    addTearDown(controller.dispose);
    await controller.load('book-beta06');
    await controller.createEncryptedBackup(
      password: 'strong-password',
      confirmation: 'strong-password',
    );

    expect(controller.backupResult, isNull);
    expect(controller.error, contains('Write failed'));
  });

  test('successful retry clears the stale backup error', () async {
    final files = _FakeFiles(failuresRemaining: 1);
    final controller = BackupExportController(
      backupService: HouseholdBackupService(_MemoryStore()),
      fileService: files,
    );
    addTearDown(controller.dispose);
    await controller.load('book-beta06');

    await controller.createEncryptedBackup(
      password: 'strong-password',
      confirmation: 'strong-password',
    );
    expect(controller.backupNotice, contains('Write failed'));

    await controller.createEncryptedBackup(
      password: 'strong-password',
      confirmation: 'strong-password',
    );
    expect(controller.error, isNull);
    expect(controller.backupNotice, 'Backup created successfully.');
  });
}

class _MemoryStore implements HouseholdBackupStore {
  Map<String, List<Map<String, Object?>>> data = beta06Snapshot();
  int activationCount = 0;
  String? lastReplaceBookId;

  @override
  int get schemaVersion => 20;

  @override
  Future<void> activate(
    Map<String, List<Map<String, Object?>>> snapshot, {
    String? replaceBookId,
    bool idempotent = false,
  }) async {
    activationCount++;
    lastReplaceBookId = replaceBookId;
    data = snapshot;
  }

  @override
  Future<List<Map<String, Object?>>> localHouseholds() async => [
    data['household']!.single,
  ];

  @override
  Future<Map<String, List<Map<String, Object?>>>> snapshot(
    String bookId,
  ) async {
    return data;
  }
}

class _FakeFiles extends PortableFileService {
  _FakeFiles({
    this.picked,
    this.hasRemembered = true,
    this.cancelChoose = false,
    this.cancelSave = false,
    bool throwOnSave = false,
    int failuresRemaining = 0,
    this.saveGate,
  }) : failuresRemaining = throwOnSave ? 1000 : failuresRemaining;

  final PickedPortableFile? picked;
  final bool hasRemembered;
  final bool cancelChoose;
  final bool cancelSave;
  int failuresRemaining;
  final Completer<void>? saveGate;
  int saveCalls = 0;
  String? copied;
  String? savedName;

  static const destination = PortableDestination(
    displayValue: r'C:\Exports',
    reference: r'C:\Exports',
    isValid: true,
  );

  @override
  Future<PortableDestination?> rememberedDestination(
    PortableDestinationKind kind,
  ) async => hasRemembered ? destination : null;

  @override
  Future<PortableDestination?> chooseDestination(
    PortableDestinationKind kind,
  ) async => cancelChoose
      ? null
      : const PortableDestination(
          displayValue: r'C:\Chosen',
          reference: r'C:\Chosen',
          isValid: true,
        );

  @override
  Future<PickedPortableFile?> openBackup() async => picked;

  @override
  Future<PortableSaveResult?> save({
    required PortableDestinationKind kind,
    required PortableDestination destination,
    required String suggestedName,
    required Uint8List bytes,
    required String extension,
    required String dialogTitle,
  }) async {
    saveCalls++;
    savedName = suggestedName;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const PortableFileException('Write failed.');
    }
    await saveGate?.future;
    if (cancelSave) return null;
    return PortableSaveResult(
      fileName: suggestedName,
      destinationDisplayValue: destination.displayValue,
      fullPathOrUri: '${destination.reference}\\$suggestedName',
      completedAt: DateTime(2026, 7, 31, 14, 6),
      canOpenFolder: true,
      canCopyPath: true,
    );
  }

  @override
  Future<void> copyPath(PortableSaveResult result) async {
    copied = result.fullPathOrUri;
  }
}
