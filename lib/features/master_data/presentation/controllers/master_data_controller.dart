import 'package:flutter/foundation.dart';

import '../../domain/entities/account.dart';

typedef MasterDataPersist =
    Future<void> Function({
      required String entity,
      required String name,
      String? previousName,
      String? categoryType,
    });

typedef AccountPersist = Future<void> Function(Account account);

class MasterDataController extends ChangeNotifier {
  MasterDataController({required this.persist, this.persistAccount});

  final MasterDataPersist persist;
  final AccountPersist? persistAccount;

  final _accounts = <String>[];
  final _accountRecords = <Account>[];
  final _expenseCategories = <String>[];
  final _incomeCategories = <String>[];
  final _projects = <String>[];

  List<String> get accounts => List<String>.unmodifiable(_accounts);
  List<Account> get accountRecords =>
      List<Account>.unmodifiable(_accountRecords);

  List<String> get expenseCategories =>
      List<String>.unmodifiable(_expenseCategories);

  List<String> get incomeCategories =>
      List<String>.unmodifiable(_incomeCategories);

  List<String> get projects => List<String>.unmodifiable(_projects);

  void replaceAll({
    required Iterable<String> accounts,
    Iterable<Account>? accountRecords,
    required Iterable<String> expenseCategories,
    required Iterable<String> incomeCategories,
    required Iterable<String> projects,
  }) {
    _accounts
      ..clear()
      ..addAll(accounts);

    _accountRecords
      ..clear()
      ..addAll(accountRecords ?? accounts.map((name) => Account(name: name)));

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

    if (entity == 'accounts' && persistAccount != null) {
      final existing = previousName == null
          ? null
          : _accountRecords.cast<Account?>().firstWhere(
              (account) => account?.name == previousName,
              orElse: () => null,
            );
      await saveAccount(
        existing == null
            ? Account(name: normalizedName)
            : existing.copyWith(name: normalizedName),
      );
      return;
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

  Future<void> saveAccount(Account account) async {
    final normalizedName = account.name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        account.name,
        'name',
        'Account name cannot be empty.',
      );
    }

    final currentIndex = _accountRecords.indexWhere(
      (item) => item.id == account.id,
    );
    final duplicate = _accountRecords.indexWhere(
      (item) =>
          item.deletedAt == null &&
          item.name.trim().toLowerCase() == normalizedName.toLowerCase() &&
          item.id != account.id,
    );
    if (duplicate >= 0) {
      throw StateError('$normalizedName already exists.');
    }

    final now = DateTime.now();
    final prepared = currentIndex >= 0
        ? account.copyWith(
            name: normalizedName,
            createdAt: _accountRecords[currentIndex].createdAt,
            updatedAt: now,
            version: _accountRecords[currentIndex].version + 1,
            syncStatus: 'pending',
          )
        : account.copyWith(
            name: normalizedName,
            updatedAt: now,
            syncStatus: 'pending',
          );

    final writer = persistAccount;
    if (writer == null) {
      await persist(entity: 'accounts', name: normalizedName);
    } else {
      await writer(prepared);
    }

    if (currentIndex >= 0) {
      _accountRecords[currentIndex] = prepared;
    } else {
      _accountRecords.add(prepared);
    }
    _accounts
      ..clear()
      ..addAll(
        _accountRecords
            .where((item) => item.deletedAt == null)
            .map((item) => item.name),
      );
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
