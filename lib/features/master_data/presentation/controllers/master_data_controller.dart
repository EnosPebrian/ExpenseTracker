import 'package:flutter/foundation.dart';

typedef MasterDataPersist =
    Future<void> Function({
      required String entity,
      required String name,
      String? previousName,
      String? categoryType,
    });

class MasterDataController extends ChangeNotifier {
  MasterDataController({required this.persist});

  final MasterDataPersist persist;

  final _accounts = <String>[];
  final _expenseCategories = <String>[];
  final _incomeCategories = <String>[];
  final _projects = <String>[];

  List<String> get accounts => List<String>.unmodifiable(_accounts);

  List<String> get expenseCategories =>
      List<String>.unmodifiable(_expenseCategories);

  List<String> get incomeCategories =>
      List<String>.unmodifiable(_incomeCategories);

  List<String> get projects => List<String>.unmodifiable(_projects);

  void replaceAll({
    required Iterable<String> accounts,
    required Iterable<String> expenseCategories,
    required Iterable<String> incomeCategories,
    required Iterable<String> projects,
  }) {
    _accounts
      ..clear()
      ..addAll(accounts);

    _expenseCategories
      ..clear()
      ..addAll(expenseCategories);

    _incomeCategories
      ..clear()
      ..addAll(incomeCategories);

    _projects
      ..clear()
      ..addAll(projects);

    notifyListeners();
  }

  Future<void> save({
    required String entity,
    required String name,
    String? previousName,
    String? categoryType,
  }) async {
    final normalizedName = name.trim();

    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Master data name cannot be empty.',
      );
    }

    final target = _resolveTarget(entity, categoryType);

    final currentIndex = previousName == null
        ? -1
        : target.indexOf(previousName);

    if (previousName != null && previousName.trim() == normalizedName) {
      return;
    }

    final duplicateIndex = target.indexWhere(
      (item) => item.trim().toLowerCase() == normalizedName.toLowerCase(),
    );

    if (duplicateIndex >= 0 && duplicateIndex != currentIndex) {
      throw StateError('$normalizedName already exists.');
    }

    await persist(
      entity: entity,
      name: normalizedName,
      previousName: previousName,
      categoryType: categoryType,
    );

    if (previousName == null) {
      target.add(normalizedName);
    } else if (currentIndex >= 0) {
      target[currentIndex] = normalizedName;
    } else {
      target.add(normalizedName);
    }

    notifyListeners();
  }

  List<String> _resolveTarget(String entity, String? categoryType) {
    switch (entity) {
      case 'accounts':
        return _accounts;

      case 'projects':
        return _projects;

      case 'categories':
        switch (categoryType) {
          case 'expense':
            return _expenseCategories;

          case 'income':
            return _incomeCategories;

          default:
            throw ArgumentError.value(
              categoryType,
              'categoryType',
              'Category type must be expense or income.',
            );
        }

      default:
        throw ArgumentError.value(
          entity,
          'entity',
          'Unsupported master data entity.',
        );
    }
  }
}
