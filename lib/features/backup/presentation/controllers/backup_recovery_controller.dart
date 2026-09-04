import 'package:flutter/foundation.dart';

import '../../data/portable_file_service.dart';
import '../../domain/backup_models.dart';
import '../../domain/backup_recovery_models.dart';
import '../../domain/backup_recovery_service.dart';
import '../../domain/household_backup_service.dart';

enum BackupRecoveryFilter { all, recoverable, duplicate, conflict, blocked }

class BackupRecoveryController extends ChangeNotifier {
  BackupRecoveryController({
    required this.backupService,
    required this.recoveryService,
    required this.fileService,
    this.onRecovered,
    this.onViewTransactions,
  });

  final HouseholdBackupService backupService;
  final BackupRecoveryService recoveryService;
  final PortableFileService fileService;
  final Future<void> Function()? onRecovered;
  final VoidCallback? onViewTransactions;

  String? _bookId;
  Uint8List? _bytes;
  String? selectedFileName;
  BackupRecoveryPreview? preview;
  BackupRecoveryResult? result;
  final Set<String> selectedKeys = {};
  bool busy = false;
  String? error;
  String search = '';
  BackupRecoveryFilter filter = BackupRecoveryFilter.all;

  void load(String bookId) {
    _bookId = bookId;
    clear();
  }

  void clear() {
    _bytes = null;
    selectedFileName = null;
    preview = null;
    result = null;
    selectedKeys.clear();
    error = null;
    notifyListeners();
  }

  Future<void> pickBackup() => _run(() async {
    final picked = await fileService.openBackup();
    if (picked == null) return;
    _bytes = picked.bytes;
    selectedFileName = picked.name;
    preview = null;
    result = null;
    selectedKeys.clear();
  });

  Future<void> analyze(String password) => _run(() async {
    if (password.isEmpty) {
      throw const BackupValidationException('Enter the backup password.');
    }
    final bytes = _bytes;
    final bookId = _bookId;
    if (bytes == null) {
      throw const BackupValidationException('Select a .ptbackup file first.');
    }
    if (bookId == null) {
      throw const BackupValidationException('No active household is loaded.');
    }
    final decoded = await backupService.validate(bytes, password);
    preview = await recoveryService.analyze(
      backup: decoded,
      activeBookId: bookId,
    );
    selectedKeys
      ..clear()
      ..addAll(
        preview!.candidates
            .where(
              (candidate) =>
                  candidate.classification ==
                  BackupRecoveryClassification.missing,
            )
            .map((candidate) => candidate.key),
      );
  });

  List<BackupRecoveryCandidate> get visibleCandidates {
    final query = search.trim().toLowerCase();
    return (preview?.candidates ?? const []).where((candidate) {
      final matchesSearch =
          query.isEmpty ||
          candidate.record.values.any(
            (value) => value?.toString().toLowerCase().contains(query) == true,
          );
      return matchesSearch && _matchesFilter(candidate);
    }).toList();
  }

  void setSearch(String value) {
    search = value;
    notifyListeners();
  }

  void setFilter(BackupRecoveryFilter value) {
    filter = value;
    notifyListeners();
  }

  void toggle(String key, bool selected) {
    final candidate = preview?.candidates
        .where((item) => item.key == key)
        .firstOrNull;
    if (candidate == null || !candidate.selectable) return;
    if (selected) {
      selectedKeys.add(key);
      selectedKeys.addAll(candidate.dependencies);
    } else {
      selectedKeys.remove(key);
      for (final dependent in preview!.candidates.where(
        (item) => item.dependencies.contains(key),
      )) {
        selectedKeys.remove(dependent.key);
      }
    }
    notifyListeners();
  }

  Future<void> recoverSelected() => _run(() async {
    final value = preview;
    if (value == null || selectedKeys.isEmpty) {
      throw const BackupValidationException('Select records to recover.');
    }
    result = await recoveryService.recover(
      preview: value,
      selectedKeys: Set.of(selectedKeys),
    );
    await onRecovered?.call();
  });

  bool _matchesFilter(BackupRecoveryCandidate candidate) => switch (filter) {
    BackupRecoveryFilter.all => true,
    BackupRecoveryFilter.recoverable => candidate.selectable,
    BackupRecoveryFilter.duplicate =>
      candidate.classification ==
              BackupRecoveryClassification.semanticDuplicate ||
          candidate.classification ==
              BackupRecoveryClassification.possibleDuplicate,
    BackupRecoveryFilter.conflict =>
      candidate.classification ==
              BackupRecoveryClassification.changedConflict ||
          candidate.classification ==
              BackupRecoveryClassification.remoteDeleted,
    BackupRecoveryFilter.blocked =>
      candidate.classification ==
              BackupRecoveryClassification.invalidReference ||
          candidate.classification ==
              BackupRecoveryClassification.foreignHousehold ||
          candidate.classification == BackupRecoveryClassification.unsupported,
  };

  Future<void> _run(Future<void> Function() operation) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } catch (exception) {
      error = switch (exception) {
        BackupValidationException() => exception.message,
        BackupPasswordOrCorruptionException() => exception.toString(),
        UnsupportedBackupVersionException() => exception.toString(),
        PortableFileException() => exception.message,
        _ => 'Recovery could not be completed safely.',
      };
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
