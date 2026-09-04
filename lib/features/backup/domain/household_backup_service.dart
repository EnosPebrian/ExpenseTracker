import 'dart:typed_data';

import '../data/portable_backup_codec.dart';
import 'backup_models.dart';
import 'household_backup_integrity.dart';
import 'restore_classifier.dart';

abstract interface class HouseholdBackupStore {
  int get schemaVersion;

  Future<Map<String, List<Map<String, Object?>>>> snapshot(String bookId);

  Future<List<Map<String, Object?>>> localHouseholds();

  Future<void> activate(
    Map<String, List<Map<String, Object?>>> snapshot, {
    String? replaceBookId,
    bool idempotent = false,
  });
}

class HouseholdBackupService {
  HouseholdBackupService(this.store)
    : codec = PortableBackupCodec(databaseSchemaVersion: store.schemaVersion);

  final HouseholdBackupStore store;
  final PortableBackupCodec codec;

  Future<CreatedBackup> create({
    required String bookId,
    required String password,
    DateTime? exportedAt,
  }) async {
    return codec.encode(
      snapshot: await store.snapshot(bookId),
      password: password,
      exportedAt: exportedAt,
    );
  }

  Future<DecodedBackup> validate(Uint8List bytes, String password) {
    return codec.decode(bytes, password);
  }

  Future<RestorePreview> preview({
    required DecodedBackup backup,
    required RestoreMode mode,
    required String activeBookId,
    bool remapOnCollision = false,
  }) async {
    final foreignRecords = _foreignRecordCount(backup.snapshot);
    final existingHouseholds = await store.localHouseholds();
    final collision = existingHouseholds.any(
      (book) => book['id'] == backup.manifest.bookId,
    );
    final remapAsCopy =
        mode == RestoreMode.newHousehold && remapOnCollision && collision;
    final compatibleSnapshot = await _withPreservedLegacyEntities(
      backup,
      mode: mode,
      activeBookId: activeBookId,
    );
    Map<String, List<Map<String, Object?>>> prepared;
    try {
      prepared = HouseholdBackupIntegrity.prepareForRestore(
        compatibleSnapshot,
        remapAsCopy: remapAsCopy,
      );
    } catch (_) {
      return _invalidPreview(
        mode,
        'The backup does not contain a valid household structure.',
      );
    }
    final existing = collision && !remapAsCopy
        ? HouseholdBackupIntegrity.sanitize(
            await store.snapshot(backup.manifest.bookId),
          )
        : <String, List<Map<String, Object?>>>{};
    var result = RestoreClassifier.classify(
      incoming: remapAsCopy
          ? prepared
          : HouseholdBackupIntegrity.sanitize(compatibleSnapshot),
      existing: existing,
      mode: mode,
    );
    final blockingErrors = [...result.blockingErrors];
    if (mode == RestoreMode.replaceMatchingHousehold) {
      if (backup.manifest.bookId != activeBookId) {
        blockingErrors.add(
          'Replacement requires the backup household ID to match the active household.',
        );
      } else if (!collision) {
        blockingErrors.add(
          'The matching active household no longer exists locally.',
        );
      }
    }
    if (foreignRecords > 0) {
      result = _copyPreview(
        result,
        blockingErrors: [
          ...blockingErrors,
          'The backup contains records owned by another household.',
        ],
        details: [
          ...result.details,
          'Backup contains foreign-household records.',
        ],
      );
    } else {
      result = _copyPreview(result, blockingErrors: blockingErrors);
    }
    if (backup.manifest.formatVersion < 2) {
      result = _copyPreview(
        result,
        details: [
          ...result.details,
          'This backup was created before monthly budgets were supported.',
        ],
      );
    }
    if (backup.manifest.formatVersion < 3) {
      result = _copyPreview(
        result,
        details: [
          ...result.details,
          'This backup was created before transaction import rules were supported.',
        ],
      );
    }
    if (backup.manifest.formatVersion < 4) {
      result = _copyPreview(
        result,
        details: [
          ...result.details,
          'This backup was created before canonical internal transfers were supported.',
        ],
      );
    }
    if (result.invalidRecords == 0) {
      String? integrityError;
      try {
        HouseholdBackupIntegrity.validate(prepared);
        HouseholdBackupIntegrity.financialSummary(prepared);
      } on BackupValidationException catch (error) {
        integrityError = error.message;
      } catch (_) {
        integrityError =
            'The backup failed structural or accounting validation.';
      }
      if (integrityError != null) {
        result = _copyPreview(
          result,
          blockingErrors: [...result.blockingErrors, integrityError],
          details: [...result.details, integrityError],
        );
      }
    }
    return result;
  }

  Future<String> restore({
    required DecodedBackup backup,
    required RestoreMode mode,
    required String activeBookId,
    String? confirmedHouseholdName,
    bool remapOnCollision = false,
  }) async {
    if (_foreignRecordCount(backup.snapshot) > 0) {
      throw const BackupValidationException(
        'The backup contains records owned by another household.',
      );
    }
    final preview = await this.preview(
      backup: backup,
      mode: mode,
      activeBookId: activeBookId,
      remapOnCollision: remapOnCollision,
    );
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
      final prepared = HouseholdBackupIntegrity.prepareForRestore(
        await _withPreservedLegacyEntities(
          backup,
          mode: mode,
          activeBookId: activeBookId,
        ),
      );
      await store.activate(prepared, replaceBookId: activeBookId);
      return backup.manifest.bookId;
    }

    final collision = (await store.localHouseholds()).any(
      (book) => book['id'] == backup.manifest.bookId,
    );
    final prepared = HouseholdBackupIntegrity.prepareForRestore(
      backup.snapshot,
      remapAsCopy: remapOnCollision && collision,
    );
    await store.activate(prepared);
    return prepared['household']!.single['id'] as String;
  }

  static RestorePreview _copyPreview(
    RestorePreview source, {
    List<String>? blockingErrors,
    List<String>? details,
  }) => RestorePreview(
    mode: source.mode,
    newByEntity: source.newByEntity,
    identicalByEntity: source.identicalByEntity,
    replacementByEntity: source.replacementByEntity,
    conflictingByEntity: source.conflictingByEntity,
    invalidByEntity: source.invalidByEntity,
    expectedFinalTotals: source.expectedFinalTotals,
    blockingErrors: blockingErrors ?? source.blockingErrors,
    details: details ?? source.details,
  );

  static RestorePreview _invalidPreview(RestoreMode mode, String message) =>
      RestorePreview(
        mode: mode,
        newByEntity: const {},
        identicalByEntity: const {},
        replacementByEntity: const {},
        conflictingByEntity: const {},
        invalidByEntity: const {'backup': 1},
        expectedFinalTotals: const {},
        blockingErrors: [message],
        details: [message],
      );

  static int _foreignRecordCount(
    Map<String, List<Map<String, Object?>>> snapshot,
  ) {
    final households = snapshot['household'] ?? const [];
    if (households.length != 1) return 1;
    final bookId = households.single['id'];
    return snapshot.entries
        .where((entry) => entry.key != 'household')
        .expand((entry) => entry.value)
        .where((record) => record['book_id'] != bookId)
        .length;
  }

  Future<Map<String, List<Map<String, Object?>>>> _withPreservedLegacyEntities(
    DecodedBackup backup, {
    required RestoreMode mode,
    required String activeBookId,
  }) async {
    if (backup.manifest.formatVersion >= 4 ||
        mode != RestoreMode.replaceMatchingHousehold ||
        backup.manifest.bookId != activeBookId) {
      return backup.snapshot;
    }
    final existing = await store.snapshot(activeBookId);
    return {
      ...backup.snapshot,
      if (backup.manifest.formatVersion < 2)
        'budgets': existing['budgets'] ?? const [],
      if (backup.manifest.formatVersion < 3)
        'transaction_import_rules':
            existing['transaction_import_rules'] ?? const [],
      'transfer_links': existing['transfer_links'] ?? const [],
    };
  }
}
