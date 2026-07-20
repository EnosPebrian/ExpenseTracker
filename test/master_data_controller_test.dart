import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/presentation/controllers/master_data_controller.dart';

class _PersistCall {
  const _PersistCall({
    required this.entity,
    required this.name,
    this.previousName,
    this.categoryType,
  });

  final String entity;
  final String name;
  final String? previousName;
  final String? categoryType;
}

void main() {
  test('replaceAll hydrates independent master data lists', () {
    final persisted = <_PersistCall>[];

    final controller = MasterDataController(
      persist:
          ({
            required String entity,
            required String name,
            String? previousName,
            String? categoryType,
          }) async {
            persisted.add(
              _PersistCall(
                entity: entity,
                name: name,
                previousName: previousName,
                categoryType: categoryType,
              ),
            );
          },
    );

    addTearDown(controller.dispose);

    final sourceAccounts = <String>['Cash'];

    controller.replaceAll(
      accounts: sourceAccounts,
      expenseCategories: const ['Food'],
      incomeCategories: const ['Salary'],
      projects: const ['Life'],
    );

    sourceAccounts.add('Bank');

    expect(controller.accounts, ['Cash']);
    expect(controller.expenseCategories, ['Food']);
    expect(controller.incomeCategories, ['Salary']);
    expect(controller.projects, ['Life']);
    expect(persisted, isEmpty);
  });

  test('save persists and adds an account', () async {
    final persisted = <_PersistCall>[];

    final controller = MasterDataController(
      persist:
          ({
            required String entity,
            required String name,
            String? previousName,
            String? categoryType,
          }) async {
            persisted.add(
              _PersistCall(
                entity: entity,
                name: name,
                previousName: previousName,
                categoryType: categoryType,
              ),
            );
          },
    );

    addTearDown(controller.dispose);

    controller.replaceAll(
      accounts: const ['Cash'],
      expenseCategories: const [],
      incomeCategories: const [],
      projects: const [],
    );

    await controller.save(entity: 'accounts', name: 'Bank');

    expect(controller.accounts, ['Cash', 'Bank']);
    expect(persisted, hasLength(1));
    expect(persisted.single.entity, 'accounts');
    expect(persisted.single.name, 'Bank');
  });

  test('rename updates only the requested category type', () async {
    final controller = MasterDataController(
      persist:
          ({
            required String entity,
            required String name,
            String? previousName,
            String? categoryType,
          }) async {},
    );

    addTearDown(controller.dispose);

    controller.replaceAll(
      accounts: const [],
      expenseCategories: const ['Food'],
      incomeCategories: const ['Salary'],
      projects: const [],
    );

    await controller.save(
      entity: 'categories',
      categoryType: 'expense',
      previousName: 'Food',
      name: 'Dining',
    );

    expect(controller.expenseCategories, ['Dining']);
    expect(controller.incomeCategories, ['Salary']);
  });

  test('persistence failure does not mutate local state', () async {
    final controller = MasterDataController(
      persist:
          ({
            required String entity,
            required String name,
            String? previousName,
            String? categoryType,
          }) async {
            throw StateError('database unavailable');
          },
    );

    addTearDown(controller.dispose);

    controller.replaceAll(
      accounts: const ['Cash'],
      expenseCategories: const [],
      incomeCategories: const [],
      projects: const [],
    );

    await expectLater(
      controller.save(entity: 'accounts', name: 'Bank'),
      throwsA(isA<StateError>()),
    );

    expect(controller.accounts, ['Cash']);
  });

  test('duplicate add is rejected before persistence', () async {
    var persistCount = 0;

    final controller = MasterDataController(
      persist:
          ({
            required String entity,
            required String name,
            String? previousName,
            String? categoryType,
          }) async {
            persistCount++;
          },
    );

    addTearDown(controller.dispose);

    controller.replaceAll(
      accounts: const ['Cash'],
      expenseCategories: const [],
      incomeCategories: const [],
      projects: const [],
    );

    await expectLater(
      controller.save(entity: 'accounts', name: '  CASH  '),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('already exists'),
        ),
      ),
    );

    expect(persistCount, 0);
    expect(controller.accounts, ['Cash']);
  });

  test('rename to an existing name is rejected', () async {
    var persistCount = 0;

    final controller = MasterDataController(
      persist:
          ({
            required String entity,
            required String name,
            String? previousName,
            String? categoryType,
          }) async {
            persistCount++;
          },
    );

    addTearDown(controller.dispose);

    controller.replaceAll(
      accounts: const ['Cash', 'Bank'],
      expenseCategories: const [],
      incomeCategories: const [],
      projects: const [],
    );

    await expectLater(
      controller.save(entity: 'accounts', previousName: 'Cash', name: 'bank'),
      throwsA(isA<StateError>()),
    );

    expect(persistCount, 0);
    expect(controller.accounts, ['Cash', 'Bank']);
  });

  test('unchanged rename skips persistence', () async {
    var persistCount = 0;
    var notificationCount = 0;

    final controller = MasterDataController(
      persist:
          ({
            required String entity,
            required String name,
            String? previousName,
            String? categoryType,
          }) async {
            persistCount++;
          },
    );

    addTearDown(controller.dispose);

    controller.replaceAll(
      accounts: const ['Cash'],
      expenseCategories: const [],
      incomeCategories: const [],
      projects: const [],
    );

    controller.addListener(() {
      notificationCount++;
    });

    // Ignore the replaceAll notification above.
    notificationCount = 0;

    await controller.save(
      entity: 'accounts',
      previousName: 'Cash',
      name: ' Cash ',
    );

    expect(persistCount, 0);
    expect(notificationCount, 0);
    expect(controller.accounts, ['Cash']);
  });
}
