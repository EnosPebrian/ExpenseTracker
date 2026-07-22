import 'package:flutter/foundation.dart';

import '../domain/entities/asset_definition.dart';
import '../domain/repositories/asset_definition_repository.dart';

class AssetDefinitionController extends ChangeNotifier {
  AssetDefinitionController({
    required AssetDefinitionRepository repository,
    DateTime Function()? now,
  }) : this._(repository, now ?? DateTime.now);

  AssetDefinitionController._(this._repository, this._now);

  final AssetDefinitionRepository _repository;
  final DateTime Function() _now;

  List<AssetDefinition> _definitions = const [];

  bool isLoading = false;
  bool isSaving = false;
  String? error;

  List<AssetDefinition> get definitions {
    return List<AssetDefinition>.unmodifiable(_definitions);
  }

  List<String> get names {
    return List<String>.unmodifiable(
      _definitions.map((definition) => definition.displayName),
    );
  }

  AssetDefinition? definitionById(String id) {
    for (final definition in _definitions) {
      if (definition.id == id) {
        return definition;
      }
    }

    return null;
  }

  Future<void> initialize({Iterable<AssetDefinition> seeds = const []}) async {
    if (isLoading) {
      return;
    }

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final seedValues = seeds.toList(growable: false);

      if (seedValues.isNotEmpty) {
        await _repository.ensureSeeds(seedValues);
      }

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
    notifyListeners();

    try {
      final normalized = AssetDefinition.fromRecord(definition.toRecord());

      final existing = await _repository.getById(normalized.id);
      final timestamp = _now().toUtc();

      final candidate = normalized.copyWith(
        createdAt: existing?.createdAt ?? timestamp,
        updatedAt: timestamp,
        deletedAt: null,
        version: existing == null ? 1 : existing.version + 1,
        deviceId: existing?.deviceId ?? normalized.deviceId,
        syncStatus: 'pending',
      );

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
      error = 'Could not save the asset definition. $exception';
      rethrow;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<void> delete(AssetDefinition definition) async {
    if (isSaving) {
      throw StateError('Another asset definition is currently being changed.');
    }

    isSaving = true;
    error = null;
    notifyListeners();

    try {
      await _repository.softDelete(definition.id, deletedAt: _now().toUtc());

      await _reloadDefinitions();
    } catch (exception) {
      error = 'Could not delete ${definition.displayName}. $exception';
      rethrow;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (error == null) {
      return;
    }

    error = null;
    notifyListeners();
  }

  Future<void> _reloadDefinitions() async {
    final values = await _repository.getAll();

    values.sort((left, right) {
      return left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      );
    });

    _definitions = List<AssetDefinition>.unmodifiable(values);
  }
}
