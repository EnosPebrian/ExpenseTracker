import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/presentation/controllers/master_data_controller.dart';

void main() {
  test('legacy account records receive safe structured defaults', () {
    final account = Account.fromRecord({
      'id': 'legacy-account',
      'name': 'Cash',
      'account_type': 'asset',
      'created_at': 1,
      'updated_at': 2,
      'version': 1,
      'device_id': 'legacy-device',
      'sync_status': 'local_only',
    });

    expect(account.id, 'legacy-account');
    expect(account.currencyCode, 'IDR');
    expect(account.openingBalance, 0);
    expect(account.openingBalanceDate, isNull);
    expect(account.hasOpeningBalance, isFalse);
  });

  test('positive, negative, and zero opening balances can be configured', () {
    final date = DateTime(2026, 7, 26);

    for (final amount in [1200, -500, 0]) {
      final account = Account(
        name: 'Account $amount',
        openingBalance: amount,
        openingBalanceDate: date,
      );
      expect(account.openingBalance, amount);
      expect(account.hasOpeningBalance, isTrue);
    }
  });

  test('unset opening balance is distinct from configured zero', () {
    final unset = Account(name: 'Unset');
    final zero = Account(
      name: 'Zero',
      openingBalance: 0,
      openingBalanceDate: DateTime(2026, 7, 26),
    );

    expect(unset.hasOpeningBalance, isFalse);
    expect(zero.hasOpeningBalance, isTrue);
  });

  test('mapping and copyWith preserve identity and metadata on rename', () {
    final created = DateTime(2025, 1, 2);
    final openingDate = DateTime(2026, 1, 1);
    final original = Account(
      id: 'stable-id',
      bookId: 'book-1',
      name: 'Old name',
      accountType: AccountType.liability,
      currencyCode: 'usd',
      openingBalance: -2500,
      openingBalanceDate: openingDate,
      createdAt: created,
      updatedAt: created,
      version: 4,
      deviceId: 'device-1',
      syncStatus: 'pending',
    );

    final restored = Account.fromRecord(original.toRecord());
    final renamed = restored.copyWith(name: 'New name');

    expect(restored.accountType, AccountType.liability);
    expect(restored.currencyCode, 'USD');
    expect(renamed.id, original.id);
    expect(renamed.bookId, original.bookId);
    expect(renamed.openingBalance, -2500);
    expect(renamed.openingBalanceDate, openingDate);
    expect(renamed.createdAt, created);
    expect(renamed.version, 4);
    expect(renamed.deviceId, 'device-1');
  });

  test('account type mapping supports stored values and legacy fallback', () {
    for (final type in AccountType.values) {
      expect(AccountType.fromStoredValue(type.storedValue), type);
    }
    expect(AccountType.fromStoredValue('unknown'), AccountType.asset);
  });

  test(
    'controller creates, edits, and removes structured opening balance',
    () async {
      final persisted = <Account>[];
      final controller = MasterDataController(
        persist:
            ({
              required String entity,
              required String name,
              String? previousName,
              String? categoryType,
            }) async {},
        persistAccount: (account) async => persisted.add(account),
      );
      addTearDown(controller.dispose);
      controller.replaceAll(
        accounts: const [],
        accountRecords: const [],
        expenseCategories: const [],
        incomeCategories: const [],
        projects: const [],
      );
      final created = Account(
        name: 'Cash',
        openingBalance: 0,
        openingBalanceDate: DateTime(2026, 7, 1),
      );
      await controller.saveAccount(created);
      await controller.saveAccount(
        controller.accountRecords.single.copyWith(
          name: 'Wallet',
          openingBalance: 500,
        ),
      );
      await controller.saveAccount(
        controller.accountRecords.single.copyWith(
          openingBalance: 0,
          openingBalanceDate: null,
        ),
      );

      expect(controller.accounts, ['Wallet']);
      expect(controller.accountRecords.single.id, created.id);
      expect(controller.accountRecords.single.openingBalance, 0);
      expect(controller.accountRecords.single.openingBalanceDate, isNull);
      expect(persisted, hasLength(3));
    },
  );

  test(
    'controller rejects duplicate active account names case-insensitively',
    () async {
      var writes = 0;
      final controller = MasterDataController(
        persist:
            ({
              required String entity,
              required String name,
              String? previousName,
              String? categoryType,
            }) async {},
        persistAccount: (_) async => writes++,
      );
      addTearDown(controller.dispose);
      final cash = Account(id: 'cash', name: 'Cash');
      final bank = Account(id: 'bank', name: 'Bank');
      controller.replaceAll(
        accounts: [cash.name, bank.name],
        accountRecords: [cash, bank],
        expenseCategories: const [],
        incomeCategories: const [],
        projects: const [],
      );

      await expectLater(
        controller.saveAccount(bank.copyWith(name: ' cash ')),
        throwsStateError,
      );
      expect(writes, 0);
      expect(controller.accounts, ['Cash', 'Bank']);
    },
  );
}
