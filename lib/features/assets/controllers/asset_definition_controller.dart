import 'package:flutter/foundation.dart';

import '../../transactions/domain/entities/transaction.dart';
import '../domain/entities/asset_definition.dart';
import '../domain/repositories/asset_definition_repository.dart';
import '../domain/services/asset_definition_integrity_policy.dart';
import '../domain/services/asset_definition_retirement_policy.dart';
import '../domain/services/asset_definition_usage_policy.dart';

typedef AssetDefinitionTransactionsProvider =
    Future<List<Transaction>> Function();

class AssetDefinitionIntegrityException implements Exception {
  const AssetDefinitionIntegrityException(this.result);

  final AssetDefinitionIntegrityResult result;

  @override
  String toString() =>
      result.firstIssue?.message ??
      'The asset definition conflicts with existing data.';
}

class AssetDefinitionLifecycleException implements Exception {
  const AssetDefinitionLifecycleException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AssetDefinitionController extends ChangeNotifier {
  AssetDefinitionController({
    required AssetDefinitionRepository repository,
    DateTime Function()? now,
    AssetDefinitionTransactionsProvider? transactionsProvider,
    AssetDefinitionIntegrityPolicy integrityPolicy =
        const AssetDefinitionIntegrityPolicy(),
    AssetDefinitionUsagePolicy usagePolicy = const AssetDefinitionUsagePolicy(),
    AssetDefinitionRetirementPolicy retirementPolicy =
        const AssetDefinitionRetirementPolicy(),
  }) : this._(
         repository,
         now ?? DateTime.now,
         transactionsProvider,
         integrityPolicy,
         usagePolicy,
         retirementPolicy,
       );

  AssetDefinitionController._(
    this._repository,
    this._now,
    this._transactionsProvider,
    this._integrityPolicy,
    this._usagePolicy,
    this._retirementPolicy,
  );

  final AssetDefinitionRepository _repository;
  final DateTime Function() _now;
  final AssetDefinitionTransactionsProvider? _transactionsProvider;
  final AssetDefinitionIntegrityPolicy _integrityPolicy;
  final AssetDefinitionUsagePolicy _usagePolicy;
  final AssetDefinitionRetirementPolicy _retirementPolicy;

  List<AssetDefinition> _definitions = const [];
  List<AssetDefinition> _archivedDefinitions = const [];
  List<AssetDefinition> _allDefinitions = const [];
  List<Transaction> _transactions = const [];

  bool isLoading = false;
  bool isSaving = false;
  String? error;
  AssetDefinitionIntegrityResult? integrityResult;
  AssetDefinitionEditResult? editResult;

  List<AssetDefinition> get definitions {
    return List<AssetDefinition>.unmodifiable(_definitions);
  }

  List<AssetDefinition> get archivedDefinitions =>
      List<AssetDefinition>.unmodifiable(_archivedDefinitions);

  List<AssetDefinition> get allDefinitions =>
      List<AssetDefinition>.unmodifiable(_allDefinitions);

  List<String> get names {
    return List<String>.unmodifiable(
      _definitions.map((definition) => definition.displayName),
    );
  }

  AssetDefinition? definitionById(String id) {
    for (final definition in _allDefinitions) {
      if (definition.id == id) {
        return definition;
      }
    }

    return null;
  }

  AssetDefinitionUsageResult usageFor(AssetDefinition definition) {
    return _usagePolicy.analyze(
      definition: definition,
      transactions: _transactions,
    );
  }

  Future<void> initialize({Iterable<AssetDefinition> seeds = const []}) async {
    if (isLoading) {
      return;
    }

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final seedValues = seeds
          .where(
            (definition) =>
                !_retirementPolicy.isRetiredSystemDefinition(definition),
          )
          .toList(growable: false);

      if (seedValues.isNotEmpty) {
        await _validateSeeds(seedValues);
        await _repository.ensureSeeds(seedValues);
      }

      await _retireObsoleteSeedIfEligible();
      await _reloadDefinitions();
    } catch (exception) {
      error = 'Could not load asset definitions. $exception';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    if (isLoading) {
      return;
    }

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      await _retireObsoleteSeedIfEligible();
      await _reloadDefinitions();
    } catch (exception) {
      error = 'Could not load asset definitions. $exception';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<AssetDefinition> save(AssetDefinition definition) async {
    if (isSaving) {
      throw StateError('Another asset definition is currently being saved.');
    }

    isSaving = true;
    error = null;
    integrityResult = null;
    editResult = null;
    notifyListeners();

    try {
      final normalized = AssetDefinition.fromRecord(definition.toRecord());

      if (_retirementPolicy.isRetiredSystemDefinition(normalized)) {
        throw const AssetDefinitionLifecycleException(
          AssetDefinitionRetirementPolicy.editBlockedMessage,
        );
      }

      final existing = await _repository.getById(normalized.id);
      if (existing?.isDeleted ?? false) {
        throw const AssetDefinitionLifecycleException(
          'Restore this asset before editing it.',
        );
      }
      final timestamp = _now().toUtc();

      final candidate = normalized.copyWith(
        createdAt: existing?.createdAt ?? timestamp,
        updatedAt: timestamp,
        deletedAt: null,
        version: existing == null ? 1 : existing.version + 1,
        deviceId: existing?.deviceId ?? normalized.deviceId,
        syncStatus: 'pending',
      );

      if (existing != null) {
        final transactions = await _loadTransactions();
        final usage = _usagePolicy.analyze(
          definition: existing,
          transactions: transactions,
        );
        final protection = _usagePolicy.validateEdit(
          existing: existing,
          candidate: candidate,
          usage: usage,
        );
        if (!protection.isValid) {
          editResult = protection;
          error = protection.firstIssue?.message;
          throw AssetDefinitionLifecycleException(error!);
        }
      }

      final allDefinitions = await _repository.getAll(includeDeleted: true);
      final result = _integrityPolicy.validate(
        candidate: candidate,
        existingDefinitions: allDefinitions,
        editingDefinitionId: existing?.id,
      );
      if (!result.isValid) {
        integrityResult = result;
        error = result.firstIssue?.message;
        throw AssetDefinitionIntegrityException(result);
      }

      final validationErrors = candidate.validate();

      if (validationErrors.isNotEmpty) {
        throw ArgumentError.value(
          candidate,
          'definition',
          validationErrors.join(' '),
        );
      }

      await _repository.upsert(candidate);
      await _reloadDefinitions();

      return candidate;
    } catch (exception) {
      error ??= 'Could not save the asset definition. $exception';
      rethrow;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<void> archive(AssetDefinition definition) async {
    if (isSaving) {
      throw StateError('Another asset definition is currently being changed.');
    }

    isSaving = true;
    error = null;
    notifyListeners();

    try {
      final existing = await _repository.getById(definition.id);
      if (existing == null) {
        throw const AssetDefinitionLifecycleException(
          'This asset definition no longer exists.',
        );
      }
      if (existing.isDeleted) {
        await _reloadDefinitions();
        return;
      }
      final transactions = await _loadTransactions();
      final usage = _usagePolicy.analyze(
        definition: existing,
        transactions: transactions,
      );
      if (!usage.canArchive) {
        throw const AssetDefinitionLifecycleException(
          'Close the open holding before archiving this asset.',
        );
      }

      await _repository.softDelete(existing.id, deletedAt: _now().toUtc());

      await _reloadDefinitions();
    } catch (exception) {
      error = 'Could not archive ${definition.displayName}. $exception';
      rethrow;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<void> delete(AssetDefinition definition) => archive(definition);

  Future<AssetDefinition> restore(AssetDefinition definition) async {
    if (isSaving) {
      throw StateError('Another asset definition is currently being changed.');
    }

    isSaving = true;
    error = null;
    integrityResult = null;
    editResult = null;
    notifyListeners();

    try {
      final existing = await _repository.getById(definition.id);
      if (existing == null) {
        throw const AssetDefinitionLifecycleException(
          'This asset definition no longer exists.',
        );
      }
      if (!existing.isDeleted) {
        await _reloadDefinitions();
        return existing;
      }

      if (!_retirementPolicy.canRestore(existing)) {
        throw const AssetDefinitionLifecycleException(
          AssetDefinitionRetirementPolicy.restoreBlockedMessage,
        );
      }

      final timestamp = _now().toUtc();
      final candidate = existing.copyWith(
        deletedAt: null,
        updatedAt: timestamp,
        version: existing.version + 1,
        syncStatus: 'pending',
      );
      final allDefinitions = await _repository.getAll(includeDeleted: true);
      final result = _integrityPolicy.validate(
        candidate: candidate,
        existingDefinitions: allDefinitions,
        editingDefinitionId: existing.id,
      );
      if (!result.isValid) {
        integrityResult = result;
        error =
            'Cannot restore ${existing.displayName}. '
            '${result.firstIssue?.message}';
        throw AssetDefinitionIntegrityException(result);
      }
      final validationErrors = candidate.validate();
      if (validationErrors.isNotEmpty) {
        throw ArgumentError.value(
          candidate,
          'definition',
          validationErrors.join(' '),
        );
      }

      await _repository.upsert(candidate);
      await _reloadDefinitions();
      return candidate;
    } catch (exception) {
      error ??= 'Could not restore ${definition.displayName}. $exception';
      rethrow;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (error == null && integrityResult == null && editResult == null) {
      return;
    }

    error = null;
    integrityResult = null;
    editResult = null;
    notifyListeners();
  }

  String? fieldError(AssetDefinitionIntegrityField field) {
    return integrityResult?.errorFor(field) ?? _editFieldError(field);
  }

  void clearValidationErrors() {
    if (integrityResult == null && editResult == null && error == null) return;
    integrityResult = null;
    editResult = null;
    error = null;
    notifyListeners();
  }

  Future<void> _reloadDefinitions() async {
    final allValues = await _repository.getAll(includeDeleted: true);
    final active = allValues
        .where((definition) => !definition.isDeleted)
        .toList();
    final archived = allValues
        .where((definition) => definition.isDeleted)
        .toList();

    int compare(AssetDefinition left, AssetDefinition right) {
      return left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      );
    }

    active.sort(compare);
    archived.sort(compare);

    _definitions = List<AssetDefinition>.unmodifiable(active);
    _archivedDefinitions = List<AssetDefinition>.unmodifiable(archived);
    _allDefinitions = List<AssetDefinition>.unmodifiable([
      ...active,
      ...archived,
    ]);
    _transactions = List<Transaction>.unmodifiable(await _loadTransactions());
  }

  Future<List<Transaction>> _loadTransactions() async {
    return await _transactionsProvider?.call() ?? const [];
  }

  Future<void> _retireObsoleteSeedIfEligible() async {
    final definition = await _repository.getById(
      AssetDefinitionRetirementPolicy.retiredStockPortfolioId,
    );
    if (definition == null || definition.isDeleted) return;

    final usage = _usagePolicy.analyze(
      definition: definition,
      transactions: await _loadTransactions(),
    );
    if (_retirementPolicy.shouldArchive(definition, usage)) {
      await _repository.softDelete(definition.id, deletedAt: _now().toUtc());
    }
  }

  String? _editFieldError(AssetDefinitionIntegrityField field) {
    final protectedField = switch (field) {
      AssetDefinitionIntegrityField.symbol =>
        AssetDefinitionProtectedField.symbol,
      AssetDefinitionIntegrityField.exchangeCode =>
        AssetDefinitionProtectedField.exchangeCode,
      AssetDefinitionIntegrityField.currencyCode =>
        AssetDefinitionProtectedField.currencyCode,
      AssetDefinitionIntegrityField.unit => AssetDefinitionProtectedField.unit,
      AssetDefinitionIntegrityField.lotSize =>
        AssetDefinitionProtectedField.lotSize,
      _ => null,
    };
    return protectedField == null ? null : editResult?.errorFor(protectedField);
  }

  Future<void> _validateSeeds(List<AssetDefinition> seeds) async {
    final known = await _repository.getAll(includeDeleted: true);
    for (final seed in seeds) {
      final existing = known
          .where((definition) => definition.id == seed.id)
          .firstOrNull;
      final result = _integrityPolicy.validate(
        candidate: seed,
        existingDefinitions: known,
        editingDefinitionId: existing?.id,
      );
      if (!result.isValid) {
        integrityResult = result;
        throw AssetDefinitionIntegrityException(result);
      }
      final structuralErrors = seed.validate();
      if (structuralErrors.isNotEmpty) {
        throw ArgumentError.value(seed, 'seed', structuralErrors.join(' '));
      }
      if (existing == null) known.add(seed);
    }
  }
}
