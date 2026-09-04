import 'package:flutter/foundation.dart';

import '../../data/portable_file_service.dart';
import '../../domain/backup_models.dart';
import '../../domain/csv_export_service.dart';
import '../../domain/household_backup_service.dart';
import '../../domain/household_backup_integrity.dart';

enum BackupAction { load, backup, restore, csv }

class BackupExportController extends ChangeNotifier {
  BackupExportController({
    required this.backupService,
    required this.fileService,
    this.csvService = const CsvExportService(),
    this.onRestored,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final HouseholdBackupService backupService;
  final PortableFileService fileService;
  final CsvExportService csvService;
  final Future<void> Function()? onRestored;
  final DateTime Function() _now;

  Map<String, List<Map<String, Object?>>>? _snapshot;
  Uint8List? _selectedBackupBytes;
  DecodedBackup? _validatedBackup;
  RestorePreview? _restorePreview;
  RestoreMode? _previewMode;
  bool _previewRemapOnCollision = false;
  RestoreResult? _restoreResult;
  String? _selectedBackupName;
  String? _bookId;
  bool _busy = false;
  String? _error;
  String? _message;
  BackupAction? _activeAction;
  String? _backupNotice;
  String? _restoreNotice;
  String? _csvNotice;
  PortableDestination? _backupDestination;
  PortableDestination? _csvDestination;
  PortableSaveResult? _backupResult;
  PortableSaveResult? _csvResult;
  int _backupRecordCount = 0;
  int _csvTransactionCount = 0;
  String? _backupFileName;
  String? _csvFileName;

  bool get busy => _busy;
  String? get error => _error;
  String? get message => _message;
  BackupAction? get activeAction => _activeAction;
  String? get backupNotice => _backupNotice;
  String? get restoreNotice => _restoreNotice;
  String? get csvNotice => _csvNotice;
  PortableDestination? get backupDestination => _backupDestination;
  PortableDestination? get csvDestination => _csvDestination;
  PortableSaveResult? get backupResult => _backupResult;
  PortableSaveResult? get csvResult => _csvResult;
  int get backupRecordCount => _backupRecordCount;
  int get csvTransactionCount => _csvTransactionCount;
  String? get selectedBackupName => _selectedBackupName;
  DecodedBackup? get validatedBackup => _validatedBackup;
  RestorePreview? get restorePreview => _restorePreview;
  RestoreResult? get restoreResult => _restoreResult;
  Map<String, List<Map<String, Object?>>>? get snapshot => _snapshot;
  bool get hasHousehold => _snapshot != null;
  bool get hasReferenceWarnings {
    final value = _snapshot;
    if (value == null) return false;
    return HouseholdBackupIntegrity.referenceIssues(
      value,
    ).any((issue) => issue.severity == ReferenceIssueSeverity.warning);
  }

  String get backupFileName =>
      _backupFileName ?? 'pilgrim-tracker-backup-${_stamp(_now())}.ptbackup';
  String get csvFileName =>
      _csvFileName ?? 'pilgrim-tracker-export-${_stamp(_now())}.zip';

  bool canCreateBackup({
    required String password,
    required String confirmation,
    required bool confirmWarnings,
  }) =>
      !_busy &&
      _backupDestination?.isValid == true &&
      password.length >= 8 &&
      password == confirmation &&
      (!hasReferenceWarnings || confirmWarnings);

  bool canExportCsv({required bool confirmWarnings}) =>
      !_busy &&
      _csvDestination?.isValid == true &&
      (!hasReferenceWarnings || confirmWarnings);

  int estimateCsvCount(CsvExportFilter filter) {
    final value = _snapshot;
    if (value == null) return 0;
    try {
      return csvService.estimateTransactionCount(value, filter);
    } catch (_) {
      return 0;
    }
  }

  Future<void> load(String bookId) async {
    _bookId = bookId;
    await _run(BackupAction.load, () async {
      final value = await backupService.store.snapshot(bookId);
      _snapshot = value;
      _backupDestination = await fileService.rememberedDestination(
        PortableDestinationKind.backup,
      );
      _csvDestination = await fileService.rememberedDestination(
        PortableDestinationKind.csv,
      );
      _refreshFileNames();
    });
  }

  Future<void> chooseBackupDestination() =>
      _chooseDestination(PortableDestinationKind.backup);

  Future<PortableSaveResult?> createReconnectSafetyBackup(
    String password,
  ) async {
    if (password.length < 8) {
      throw const BackupValidationException(
        'Use at least 8 characters for the safety-backup password.',
      );
    }
    final destination = _backupDestination;
    if (destination == null || !destination.isValid) {
      throw const BackupValidationException(
        'Choose a backup folder before reconnecting.',
      );
    }
    final backup = await backupService.create(
      bookId: _requiredBookId(),
      password: password,
    );
    return fileService.save(
      kind: PortableDestinationKind.backup,
      destination: destination,
      suggestedName: 'pilgrim-tracker-pre-reconnect-${_stamp(_now())}.ptbackup',
      bytes: backup.bytes,
      extension: 'ptbackup',
      dialogTitle: 'Save required pre-reconnect safety backup',
    );
  }

  Future<void> chooseCsvDestination() =>
      _chooseDestination(PortableDestinationKind.csv);

  Future<void> createEncryptedBackup({
    required String password,
    required String confirmation,
    bool confirmWarnings = false,
  }) async {
    await _run(BackupAction.backup, () async {
      _validatePassword(password, confirmation);
      final warning = _referenceWarning();
      if (warning != null && !confirmWarnings) {
        _backupNotice = '$warning Confirm the warning to continue.';
        return;
      }
      final bookId = _requiredBookId();
      final destination = _backupDestination;
      if (destination == null || !destination.isValid) {
        throw const PortableFileException('Choose a backup folder first.');
      }
      final backup = await backupService.create(
        bookId: bookId,
        password: password,
      );
      final saved = await fileService.save(
        kind: PortableDestinationKind.backup,
        destination: destination,
        suggestedName: backupFileName,
        bytes: backup.bytes,
        extension: 'ptbackup',
        dialogTitle: 'Save encrypted Pilgrim Tracker backup',
      );
      if (saved == null) {
        _backupNotice = 'Backup save cancelled.';
      } else {
        _backupRecordCount = _snapshot!.values.fold(
          0,
          (total, records) => total + records.length,
        );
        _backupResult = saved.withRecordCount(_backupRecordCount);
        _backupNotice = 'Backup created successfully.';
      }
    });
  }

  Future<void> pickBackup() async {
    await _run(BackupAction.restore, () async {
      final picked = await fileService.openBackup();
      if (picked == null) return;
      _selectedBackupBytes = picked.bytes;
      _selectedBackupName = picked.name;
      _validatedBackup = null;
      _restorePreview = null;
      _previewMode = null;
      _previewRemapOnCollision = false;
      _restoreResult = null;
      _restoreNotice = 'Backup selected. Enter its password to validate it.';
    });
  }

  Future<void> validateSelectedBackup(
    String password, {
    RestoreMode mode = RestoreMode.newHousehold,
    bool remapOnCollision = false,
  }) async {
    await _run(BackupAction.restore, () async {
      if (password.isEmpty) {
        throw const BackupValidationException('Enter the backup password.');
      }
      final bytes = _selectedBackupBytes;
      if (bytes == null) {
        throw const BackupValidationException('Select a .ptbackup file first.');
      }
      _validatedBackup = await backupService.validate(bytes, password);
      await _refreshRestorePreview(
        mode: mode,
        remapOnCollision: remapOnCollision,
      );
    });
  }

  Future<void> previewValidatedBackup({
    required RestoreMode mode,
    bool remapOnCollision = false,
  }) async {
    await _run(BackupAction.restore, () async {
      if (_validatedBackup == null) return;
      await _refreshRestorePreview(
        mode: mode,
        remapOnCollision: remapOnCollision,
      );
    });
  }

  String? restoreBlockingReason({
    required RestoreMode mode,
    required String safetyBackupPassword,
    String? confirmedHouseholdName,
    bool remapOnCollision = false,
  }) {
    final backup = _validatedBackup;
    if (backup == null) return 'Validate the backup first.';
    if (_previewMode != mode || _previewRemapOnCollision != remapOnCollision) {
      return 'Refresh the restore preview for the selected mode.';
    }
    final previewReason = _restorePreview?.blockingReason;
    if (previewReason != null) return previewReason;
    if (mode == RestoreMode.replaceMatchingHousehold) {
      if (confirmedHouseholdName?.trim() != backup.manifest.bookName) {
        return 'Type the exact household name to confirm replacement.';
      }
      if (safetyBackupPassword.length < 8) {
        return 'Use at least 8 characters for the safety-backup password.';
      }
      if (_backupDestination?.isValid != true) {
        return 'Choose a backup folder before replacement restore.';
      }
    }
    return null;
  }

  Future<void> restoreValidated({
    required RestoreMode mode,
    required String safetyBackupPassword,
    String? confirmedHouseholdName,
    bool remapOnCollision = false,
  }) async {
    await _run(BackupAction.restore, () async {
      final backup = _validatedBackup;
      if (backup == null) {
        throw const BackupValidationException('Validate the backup first.');
      }
      final activeBookId = _requiredBookId();
      final preview = await backupService.preview(
        backup: backup,
        mode: mode,
        activeBookId: activeBookId,
        remapOnCollision: remapOnCollision,
      );
      _restorePreview = preview;
      _previewMode = mode;
      _previewRemapOnCollision = remapOnCollision;
      if (!preview.canRestore) {
        throw RestoreCollisionException(
          preview.blockingReason ?? 'Restore preflight failed.',
        );
      }
      if (mode == RestoreMode.replaceMatchingHousehold) {
        if (confirmedHouseholdName?.trim() != backup.manifest.bookName) {
          throw const BackupValidationException(
            'Type the exact household name to confirm replacement.',
          );
        }
        if (safetyBackupPassword.length < 8) {
          throw const BackupValidationException(
            'Use at least 8 characters for the required safety-backup password.',
          );
        }
        final safety = await backupService.create(
          bookId: activeBookId,
          password: safetyBackupPassword,
        );
        final destination = _backupDestination;
        if (destination == null || !destination.isValid) {
          throw const BackupValidationException(
            'Choose a backup folder before replacement restore.',
          );
        }
        final saved = await fileService.save(
          kind: PortableDestinationKind.backup,
          destination: destination,
          suggestedName:
              'pilgrim-tracker-pre-restore-${_stamp(_now())}.ptbackup',
          bytes: safety.bytes,
          extension: 'ptbackup',
          dialogTitle: 'Save required pre-restore safety backup',
        );
        if (saved == null) {
          throw const BackupValidationException(
            'Restore cancelled because the safety backup was not saved.',
          );
        }
      }
      final restoredBookId = await backupService.restore(
        backup: backup,
        mode: mode,
        activeBookId: activeBookId,
        confirmedHouseholdName: confirmedHouseholdName,
        remapOnCollision: remapOnCollision,
      );
      _bookId = restoredBookId;
      _selectedBackupBytes = null;
      _selectedBackupName = null;
      _restoreResult = RestoreResult(
        bookId: restoredBookId,
        preview: preview,
        completedAt: _now(),
      );
      await onRestored?.call();
      _snapshot = await backupService.store.snapshot(restoredBookId);
      _restoreNotice =
          'Restore completed: ${preview.newRecords} added, '
          '${preview.recordsToReplace} replaced, '
          '${preview.alreadyPresent} unchanged. Cloud sharing is '
          'local-only until relinked.';
    });
  }

  Future<void> _refreshRestorePreview({
    required RestoreMode mode,
    required bool remapOnCollision,
  }) async {
    final backup = _validatedBackup;
    if (backup == null) return;
    _previewMode = mode;
    _previewRemapOnCollision = remapOnCollision;
    _restorePreview = await backupService.preview(
      backup: backup,
      mode: mode,
      activeBookId: _requiredBookId(),
      remapOnCollision: remapOnCollision,
    );
    _restoreNotice = _restorePreview!.canRestore
        ? 'Backup integrity and ${mode == RestoreMode.replaceMatchingHousehold ? 'replacement' : 'new-household'} preview checks passed.'
        : _restorePreview!.blockingReason;
  }

  Future<void> exportCsv(
    CsvExportFilter filter, {
    bool confirmWarnings = false,
  }) async {
    await _run(BackupAction.csv, () async {
      final value = _snapshot;
      if (value == null) {
        throw const BackupValidationException('No active household is loaded.');
      }
      final warning = _referenceWarning();
      if (warning != null && !confirmWarnings) {
        _csvNotice = '$warning Confirm the warning to continue.';
        return;
      }
      final bundle = csvService.create(value, filter);
      final destination = _csvDestination;
      if (destination == null || !destination.isValid) {
        throw const PortableFileException('Choose a CSV folder first.');
      }
      final saved = await fileService.save(
        kind: PortableDestinationKind.csv,
        destination: destination,
        suggestedName: csvFileName,
        bytes: bundle.bytes,
        extension: 'zip',
        dialogTitle: 'Save Pilgrim Tracker CSV export',
      );
      if (saved != null) {
        _csvTransactionCount = bundle.recordCount;
        _csvResult = saved.withRecordCount(_csvTransactionCount);
        _csvNotice = 'CSV export saved (${bundle.recordCount} transactions).';
      } else {
        _csvNotice = 'CSV export save cancelled.';
      }
    });
  }

  Future<void> openBackupFolder() async {
    final result = _backupResult;
    if (result != null) await fileService.openFolder(result);
  }

  Future<void> openCsvFolder() async {
    final result = _csvResult;
    if (result != null) await fileService.openFolder(result);
  }

  Future<void> copyBackupPath() => _copyResultPath(_backupResult);

  Future<void> copyCsvPath() => _copyResultPath(_csvResult);

  Future<void> _copyResultPath(PortableSaveResult? result) async {
    if (result == null || !result.canCopyPath) return;
    await fileService.copyPath(result);
    _message = 'File path copied.';
    notifyListeners();
  }

  Future<void> _chooseDestination(PortableDestinationKind kind) async {
    if (_busy) return;
    final selected = await fileService.chooseDestination(kind);
    if (selected == null) return;
    if (kind == PortableDestinationKind.backup) {
      _backupDestination = selected;
      _backupResult = null;
    } else {
      _csvDestination = selected;
      _csvResult = null;
    }
    _refreshFileNames();
    notifyListeners();
  }

  void _refreshFileNames() {
    final stamp = _stamp(_now());
    _backupFileName = 'pilgrim-tracker-backup-$stamp.ptbackup';
    _csvFileName = 'pilgrim-tracker-export-$stamp.zip';
  }

  Future<void> _run(
    BackupAction action,
    Future<void> Function() operation,
  ) async {
    if (_busy) return;
    _busy = true;
    _activeAction = action;
    _error = null;
    _message = null;
    switch (action) {
      case BackupAction.backup:
        _backupNotice = null;
      case BackupAction.restore:
        _restoreNotice = null;
      case BackupAction.csv:
        _csvNotice = null;
      case BackupAction.load:
        break;
    }
    notifyListeners();
    try {
      await operation();
    } catch (exception) {
      _error = _safeError(exception);
      switch (action) {
        case BackupAction.backup:
          _backupNotice = _error;
        case BackupAction.restore:
          _restoreNotice = _error;
        case BackupAction.csv:
          _csvNotice = _error;
        case BackupAction.load:
          break;
      }
    } finally {
      _busy = false;
      _activeAction = null;
      notifyListeners();
    }
  }

  String? _referenceWarning() {
    final value = _snapshot;
    if (value == null) return null;
    final issues = HouseholdBackupIntegrity.referenceIssues(value);
    final fatal = issues.where(
      (issue) => issue.severity == ReferenceIssueSeverity.fatal,
    );
    if (fatal.isNotEmpty) throw BackupValidationException(fatal.first.message);
    final warnings = issues.where(
      (issue) => issue.severity == ReferenceIssueSeverity.warning,
    );
    if (warnings.isEmpty) return null;
    return '${warnings.length} transaction(s) retain a historical category '
        'that has no current category definition. The ledger row and category '
        'snapshot will be preserved.';
  }

  String _requiredBookId() {
    final value = _bookId;
    if (value == null) {
      throw const BackupValidationException('No active household is loaded.');
    }
    return value;
  }

  static void _validatePassword(String password, String confirmation) {
    if (password.length < 8) {
      throw const BackupValidationException(
        'Use a backup password with at least 8 characters.',
      );
    }
    if (password != confirmation) {
      throw const BackupValidationException(
        'The backup password confirmation does not match.',
      );
    }
  }

  static String _safeError(Object exception) => switch (exception) {
    BackupValidationException() => exception.message,
    RestoreCollisionException() => exception.message,
    BackupPasswordOrCorruptionException() => exception.toString(),
    UnsupportedBackupVersionException() => exception.toString(),
    PortableFileException() => exception.message,
    _ => 'The operation could not be completed safely.',
  };

  static String _stamp(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
