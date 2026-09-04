import '../../transactions/domain/services/transaction_duplicate_detector.dart';
import 'backup_models.dart';
import 'backup_recovery_models.dart';
import 'household_backup_integrity.dart';
import 'restore_classifier.dart';

abstract interface class BackupRecoveryStore {
  Future<Map<String, List<Map<String, Object?>>>> recoverySnapshot(
    String bookId,
  );

  Future<BackupRecoveryCloudState> recoveryCloudState(String bookId);

  Future<int> commitRecovery(
    String bookId,
    Map<String, List<Map<String, Object?>>> records, {
    required bool enqueueSync,
  });
}

abstract interface class BackupRecoveryRemoteReader {
  bool get available;

  Future<Map<String, List<Map<String, Object?>>>> read(String bookId);
}

class BackupRecoveryService {
  const BackupRecoveryService({
    required this.store,
    this.remoteReader,
    this.duplicateDetector = const TransactionDuplicateDetector(),
  });

  final BackupRecoveryStore store;
  final BackupRecoveryRemoteReader? remoteReader;
  final TransactionDuplicateDetector duplicateDetector;

  static const supportedEntityTypes = {
    'accounts',
    'categories',
    'projects',
    'asset_definitions',
    'budgets',
    'transaction_import_rules',
    'transactions',
    'transfer_links',
  };

  Future<BackupRecoveryPreview> analyze({
    required DecodedBackup backup,
    required String activeBookId,
  }) async {
    if (backup.manifest.bookId != activeBookId) {
      return _blocked(
        backup,
        const BackupRecoveryCloudState(linked: false, ready: false),
        'This backup belongs to a different household. Use Restore as new household instead.',
      );
    }
    final incoming = HouseholdBackupIntegrity.sanitize(backup.snapshot);
    try {
      HouseholdBackupIntegrity.validate(incoming);
    } on BackupValidationException catch (error) {
      return _blocked(
        backup,
        const BackupRecoveryCloudState(linked: false, ready: false),
        error.message,
      );
    }
    final local = HouseholdBackupIntegrity.sanitize(
      await store.recoverySnapshot(activeBookId),
    );
    final cloudState = await store.recoveryCloudState(activeBookId);
    Map<String, List<Map<String, Object?>>>? remote;
    String? remoteError;
    if (cloudState.linked) {
      if (!cloudState.ready) {
        remoteError =
            'Cloud verification requires a synchronized household in Ready state.';
      } else if (remoteReader?.available != true) {
        remoteError =
            'Cloud verification is required before recovery into this shared household.';
      } else {
        try {
          remote = HouseholdBackupIntegrity.sanitize(
            await remoteReader!.read(activeBookId),
          );
        } catch (_) {
          remoteError =
              'Cloud verification is required before recovery into this shared household.';
        }
      }
    }

    final candidates = _classify(
      incoming: incoming,
      local: local,
      remote: remote,
      bookId: activeBookId,
    );
    return BackupRecoveryPreview(
      backupHouseholdName: backup.manifest.bookName,
      currentHouseholdName:
          local['household']!.single['name'] as String? ?? 'Current household',
      formatVersion: backup.manifest.formatVersion,
      exportedAt: backup.manifest.exportedAt,
      cloudState: cloudState,
      remoteVerified: !cloudState.linked || remote != null,
      candidates: candidates,
      blockingErrors: [?remoteError],
    );
  }

  BackupRecoveryPlan buildPlan(
    BackupRecoveryPreview preview,
    Set<String> requestedKeys,
  ) {
    if (!preview.canRecover) {
      throw BackupValidationException(preview.blockingErrors.first);
    }
    final byKey = {
      for (final candidate in preview.candidates) candidate.key: candidate,
    };
    final selected = <String>{};

    void include(String key) {
      if (!selected.add(key)) return;
      final candidate = byKey[key];
      if (candidate == null || !candidate.selectable) {
        throw BackupValidationException(
          'A selected recovery record is no longer safe.',
        );
      }
      for (final dependency in candidate.dependencies) {
        include(dependency);
      }
    }

    for (final key in requestedKeys) {
      include(key);
    }
    final records = <String, List<Map<String, Object?>>>{};
    for (final key in selected) {
      final candidate = byKey[key]!;
      records.putIfAbsent(candidate.entityType, () => []).add(candidate.record);
    }
    return BackupRecoveryPlan(records: records, selectedKeys: selected);
  }

  Future<BackupRecoveryResult> recover({
    required BackupRecoveryPreview preview,
    required Set<String> selectedKeys,
    DateTime? completedAt,
  }) async {
    final plan = buildPlan(preview, selectedKeys);
    final pending = await store.commitRecovery(
      preview.candidates.firstOrNull?.record['book_id'] as String? ??
          _householdId(preview),
      plan.records,
      enqueueSync: preview.cloudState.linked,
    );
    return BackupRecoveryResult(
      recoveredByEntity: {
        for (final entry in plan.records.entries) entry.key: entry.value.length,
      },
      skippedAlreadyPresent: preview.count(
        BackupRecoveryClassification.identical,
      ),
      skippedDuplicates:
          preview.count(BackupRecoveryClassification.semanticDuplicate) +
          preview.count(BackupRecoveryClassification.possibleDuplicate),
      conflictsKeptCurrent: preview.count(
        BackupRecoveryClassification.changedConflict,
      ),
      blocked:
          preview.count(BackupRecoveryClassification.invalidReference) +
          preview.count(BackupRecoveryClassification.remoteDeleted) +
          preview.count(BackupRecoveryClassification.unsupported),
      pendingCount: pending,
      completedAt: completedAt ?? DateTime.now(),
    );
  }

  static String _householdId(BackupRecoveryPreview preview) {
    final household = preview.candidates.firstWhere(
      (candidate) => candidate.entityType == 'household',
    );
    return household.id;
  }

  List<BackupRecoveryCandidate> _classify({
    required Map<String, List<Map<String, Object?>>> incoming,
    required Map<String, List<Map<String, Object?>>> local,
    required Map<String, List<Map<String, Object?>>>? remote,
    required String bookId,
  }) {
    final result = <BackupRecoveryCandidate>[];
    final localTransactions = local['transactions'] ?? const [];
    final currentTransactions = [
      ...localTransactions,
      ...?remote?['transactions'],
    ];

    for (final entityType in portableBackupEntityKeys) {
      final localById = _byIdentity(entityType, local[entityType] ?? const []);
      final remoteById = _byIdentity(
        entityType,
        remote?[entityType] ?? const [],
      );
      for (final record in incoming[entityType] ?? const []) {
        final id = RestoreClassifier.identity(entityType, record);
        if (id.isEmpty ||
            (entityType == 'household'
                ? record['id'] != bookId
                : record['book_id'] != bookId)) {
          result.add(
            _candidate(
              entityType,
              id,
              record,
              BackupRecoveryClassification.foreignHousehold,
              reason: 'Record is outside the active household.',
            ),
          );
          continue;
        }
        if (record['deleted_at'] != null ||
            remoteById[id]?['deleted_at'] != null) {
          result.add(
            _candidate(
              entityType,
              id,
              record,
              BackupRecoveryClassification.remoteDeleted,
              reason: 'Deleted from shared household.',
            ),
          );
          continue;
        }
        final current = remoteById[id] ?? localById[id];
        if (current != null) {
          result.add(
            _candidate(
              entityType,
              id,
              record,
              _sameBusinessRecord(current, record)
                  ? BackupRecoveryClassification.identical
                  : BackupRecoveryClassification.changedConflict,
              reason: _sameBusinessRecord(current, record)
                  ? 'Already present.'
                  : 'Current record differs; keep current.',
            ),
          );
          continue;
        }
        if (entityType == 'household' ||
            entityType == 'members' ||
            entityType == 'manual_market_prices') {
          result.add(
            _candidate(
              entityType,
              id,
              record,
              BackupRecoveryClassification.unsupported,
              reason: entityType == 'members'
                  ? 'Hosted member authority cannot be recovered from backup.'
                  : 'Recovery not supported yet.',
            ),
          );
          continue;
        }
        if (!supportedEntityTypes.contains(entityType)) {
          result.add(
            _candidate(
              entityType,
              id,
              record,
              BackupRecoveryClassification.unsupported,
              reason: 'Recovery not supported yet.',
            ),
          );
          continue;
        }
        final currentRows = <Map<String, Object?>>[
          ...local[entityType] ?? const [],
          ...?remote?[entityType],
        ];
        if (_hasSemanticIdentityCollision(entityType, record, currentRows)) {
          result.add(
            _candidate(
              entityType,
              id,
              record,
              BackupRecoveryClassification.changedConflict,
              reason: 'A current record already uses this business identity.',
            ),
          );
          continue;
        }
        if (entityType == 'transactions') {
          final duplicate = duplicateDetector.classify(
            record,
            currentTransactions,
          );
          if (duplicate.classification ==
              TransactionCandidateClassification.semanticDuplicate) {
            result.add(
              _candidate(
                entityType,
                id,
                record,
                BackupRecoveryClassification.semanticDuplicate,
                reason:
                    'A different record appears to describe this transaction.',
              ),
            );
            continue;
          }
          if (duplicate.classification ==
              TransactionCandidateClassification.possibleDuplicate) {
            result.add(
              _candidate(
                entityType,
                id,
                record,
                BackupRecoveryClassification.possibleDuplicate,
                reason: 'Review a possible existing transaction.',
              ),
            );
            continue;
          }
        }
        if (entityType == 'budgets') {
          final collision =
              [...local['budgets'] ?? const [], ...?remote?['budgets']].any(
                (row) =>
                    row['deleted_at'] == null &&
                    row['category_id'] == record['category_id'] &&
                    row['month_start'] == record['month_start'],
              );
          if (collision) {
            result.add(
              _candidate(
                entityType,
                id,
                record,
                BackupRecoveryClassification.changedConflict,
                reason: 'A budget already exists for this category and month.',
              ),
            );
            continue;
          }
        }
        result.add(
          _candidate(
            entityType,
            id,
            record,
            BackupRecoveryClassification.missing,
          ),
        );
      }
    }
    return _attachDependencies(result, local, remote);
  }

  List<BackupRecoveryCandidate> _attachDependencies(
    List<BackupRecoveryCandidate> candidates,
    Map<String, List<Map<String, Object?>>> local,
    Map<String, List<Map<String, Object?>>>? remote,
  ) {
    final byKey = {
      for (final candidate in candidates) candidate.key: candidate,
    };
    final current = <String, Set<String>>{
      for (final type in portableBackupEntityKeys)
        type: {
          for (final row in [...local[type] ?? const [], ...?remote?[type]])
            RestoreClassifier.identity(type, row),
        },
    };
    final currentAccountNames = {
      for (final row in [
        ...local['accounts'] ?? const [],
        ...?remote?['accounts'],
      ])
        (row['name'] as String).trim().toLowerCase(),
    };
    final backupAccountByName = {
      for (final candidate in candidates.where(
        (c) => c.entityType == 'accounts',
      ))
        (candidate.record['name'] as String).trim().toLowerCase(): candidate,
    };
    final requiredKeys = <String>{};
    final output = <BackupRecoveryCandidate>[];
    for (final candidate in candidates) {
      if (candidate.classification != BackupRecoveryClassification.missing) {
        output.add(candidate);
        continue;
      }
      final dependencies = <String>[];
      String? invalid;
      void require(String type, Object? id) {
        if (id is! String || id.isEmpty || current[type]!.contains(id)) return;
        final key = '$type::$id';
        final dependency = byKey[key];
        if (dependency?.selectable == true) {
          dependencies.add(key);
          requiredKeys.add(key);
        } else {
          invalid ??= 'A required $type record is unavailable.';
        }
      }

      if (candidate.entityType == 'accounts') {
        require('members', candidate.record['owner_member_id']);
      } else if (candidate.entityType == 'budgets') {
        require('categories', candidate.record['category_id']);
      } else if (candidate.entityType == 'transaction_import_rules') {
        require('categories', candidate.record['category_id']);
        require('accounts', candidate.record['account_id']);
      } else if (candidate.entityType == 'transactions') {
        final account = (candidate.record['account'] as String? ?? '')
            .trim()
            .toLowerCase();
        if (account.isNotEmpty && !currentAccountNames.contains(account)) {
          final dependency = backupAccountByName[account];
          if (dependency?.selectable == true) {
            dependencies.add(dependency!.key);
            requiredKeys.add(dependency.key);
          } else {
            invalid = 'The transaction account is unavailable.';
          }
        }
        require('members', candidate.record['entered_by_member_id']);
        require('projects', candidate.record['project_id']);
        require('asset_definitions', candidate.record['asset_definition_id']);
        require('transactions', candidate.record['related_transaction_id']);
      } else if (candidate.entityType == 'transfer_links') {
        require('transactions', candidate.record['outgoing_transaction_id']);
        require('transactions', candidate.record['incoming_transaction_id']);
        require('accounts', candidate.record['source_account_id']);
        require('accounts', candidate.record['destination_account_id']);
      }
      output.add(
        candidate.copyWith(
          classification: invalid == null
              ? candidate.classification
              : BackupRecoveryClassification.invalidReference,
          dependencies: dependencies,
          reason: invalid,
        ),
      );
    }
    return [
      for (final candidate in output)
        requiredKeys.contains(candidate.key) &&
                candidate.classification == BackupRecoveryClassification.missing
            ? candidate.copyWith(
                classification:
                    BackupRecoveryClassification.recoverableDependency,
                reason: 'Required by another recoverable record.',
              )
            : candidate,
    ];
  }

  static Map<String, Map<String, Object?>> _byIdentity(
    String type,
    List<Map<String, Object?>> rows,
  ) => {for (final row in rows) RestoreClassifier.identity(type, row): row};

  static bool _sameBusinessRecord(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    const ignored = {
      'updated_at',
      'version',
      'device_id',
      'sync_status',
      'remote_linked_at',
      'auth_user_id',
    };
    final keys = {...left.keys, ...right.keys}..removeAll(ignored);
    for (final key in keys) {
      final a = left[key];
      final b = right[key];
      if (a is bool && b is num) {
        if ((a ? 1 : 0) != b) return false;
      } else if (b is bool && a is num) {
        if ((b ? 1 : 0) != a) return false;
      } else if (a != b) {
        return false;
      }
    }
    return true;
  }

  static bool _hasSemanticIdentityCollision(
    String entityType,
    Map<String, Object?> candidate,
    Iterable<Map<String, Object?>> current,
  ) {
    String text(Object? value) => value?.toString().trim().toLowerCase() ?? '';
    return current.where((row) => row['deleted_at'] == null).any((row) {
      return switch (entityType) {
        'accounts' => text(row['name']) == text(candidate['name']),
        'categories' =>
          text(row['name']) == text(candidate['name']) &&
              row['category_type'] == candidate['category_type'],
        'projects' => text(row['name']) == text(candidate['name']),
        'asset_definitions' =>
          text(row['display_name']) == text(candidate['display_name']),
        'transaction_import_rules' =>
          row['transaction_type'] == candidate['transaction_type'] &&
              row['match_field'] == candidate['match_field'] &&
              row['match_operator'] == candidate['match_operator'] &&
              row['pattern_key'] == candidate['pattern_key'] &&
              row['account_id'] == candidate['account_id'],
        _ => false,
      };
    });
  }

  static BackupRecoveryCandidate _candidate(
    String entityType,
    String id,
    Map<String, Object?> record,
    BackupRecoveryClassification classification, {
    String? reason,
  }) => BackupRecoveryCandidate(
    entityType: entityType,
    id: id,
    record: record,
    classification: classification,
    reason: reason,
  );

  static BackupRecoveryPreview _blocked(
    DecodedBackup backup,
    BackupRecoveryCloudState cloudState,
    String error,
  ) => BackupRecoveryPreview(
    backupHouseholdName: backup.manifest.bookName,
    currentHouseholdName: 'Current household',
    formatVersion: backup.manifest.formatVersion,
    exportedAt: backup.manifest.exportedAt,
    cloudState: cloudState,
    remoteVerified: false,
    candidates: const [],
    blockingErrors: [error],
  );
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
