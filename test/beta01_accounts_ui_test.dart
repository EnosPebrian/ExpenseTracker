import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/local_profile.dart';
import 'package:pilgrim_tracker/features/master_data/presentation/screens/accounts_page.dart';
import 'package:pilgrim_tracker/features/master_data/presentation/screens/local_profile_setup_page.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';

Widget _accountsPage({
  required List<Account> accounts,
  List<Transaction> transactions = const [],
  Future<void> Function(Account)? onSave,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AccountsPage(
        accountRecords: accounts,
        transactions: transactions,
        defaultCurrencyCode: 'IDR',
        onSave: onSave ?? (_) async {},
      ),
    ),
  );
}

void main() {
  testWidgets(
    'account list displays real calculated balance and opening summary',
    (tester) async {
      final account = Account(
        id: 'cash',
        name: 'Actual Cash',
        openingBalance: 1000,
        openingBalanceDate: DateTime(2026, 7, 1),
      );
      final income = Transaction(
        title: 'Income',
        category: 'Salary',
        account: 'Actual Cash',
        date: DateTime(2026, 7, 2),
        amount: 500,
        type: TransactionType.income,
      );
      await tester.pumpWidget(
        _accountsPage(accounts: [account], transactions: [income]),
      );

      expect(find.text('Actual Cash'), findsOneWidget);
      expect(find.text('IDR 1.500'), findsOneWidget);
      expect(find.textContaining('Starts at IDR 1.000'), findsOneWidget);
      expect(find.text('Bank BCA / 9042'), findsNothing);
    },
  );

  testWidgets('create account accepts configured zero and profile currency', (
    tester,
  ) async {
    Account? saved;
    await tester.pumpWidget(
      _accountsPage(
        accounts: const [],
        onSave: (account) async => saved = account,
      ),
    );
    await tester.tap(find.byKey(const Key('create-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'New Cash',
    );
    await tester.tap(find.byKey(const Key('opening-balance-toggle')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('opening-balance-field')), '0');
    await tester.tap(find.byKey(const Key('save-account-button')));
    await tester.pumpAndSettle();

    expect(saved?.name, 'New Cash');
    expect(saved?.currencyCode, 'IDR');
    expect(saved?.openingBalance, 0);
    expect(saved?.openingBalanceDate, isNotNull);
  });

  testWidgets('starting balance starts empty and groups digits while typing', (
    tester,
  ) async {
    Account? saved;
    await tester.pumpWidget(
      _accountsPage(
        accounts: const [],
        onSave: (account) async => saved = account,
      ),
    );
    await tester.tap(find.byKey(const Key('create-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Grouped Cash',
    );
    await tester.tap(find.byKey(const Key('opening-balance-toggle')));
    await tester.pump();

    final balanceField = find.byKey(const Key('opening-balance-field'));
    expect(tester.widget<TextField>(balanceField).controller?.text, isEmpty);

    await tester.enterText(balanceField, '1000000');
    expect(
      tester.widget<TextField>(balanceField).controller?.text,
      '1.000.000',
    );

    await tester.tap(find.byKey(const Key('save-account-button')));
    await tester.pumpAndSettle();
    expect(saved?.openingBalance, 1000000);
  });

  testWidgets('edit can remove opening balance', (tester) async {
    Account? saved;
    final account = Account(
      id: 'bank',
      name: 'Bank',
      openingBalance: -200,
      openingBalanceDate: DateTime(2026, 7, 1),
    );
    await tester.pumpWidget(
      _accountsPage(
        accounts: [account],
        onSave: (value) async => saved = value,
      ),
    );
    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('opening-balance-toggle')));
    await tester.pump();
    expect(
      find.text('Saving will remove the starting balance.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('save-account-button')));
    await tester.pumpAndSettle();

    expect(saved?.openingBalance, 0);
    expect(saved?.openingBalanceDate, isNull);
  });

  testWidgets('validation error retains entered account values', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      _accountsPage(
        accounts: const [],
        onSave: (_) async {
          attempts++;
          throw StateError('duplicate');
        },
      ),
    );
    await tester.tap(find.byKey(const Key('create-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-name-field')),
      'Remember me',
    );
    await tester.tap(find.byKey(const Key('opening-balance-toggle')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('opening-balance-field')),
      '-50',
    );
    await tester.tap(find.byKey(const Key('save-account-button')));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.textContaining('duplicate'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('account-name-field')))
          .controller
          ?.text,
      'Remember me',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('opening-balance-field')))
          .controller
          ?.text,
      '-50',
    );
  });

  testWidgets('warns about transactions before the selected opening date', (
    tester,
  ) async {
    final account = Account(id: 'cash-warning', name: 'Cash Warning');
    final oldTransaction = Transaction(
      title: 'Old entry',
      category: 'Other',
      account: account.name,
      date: DateTime(2020, 1, 1),
      amount: 1,
      type: TransactionType.income,
    );
    await tester.pumpWidget(
      _accountsPage(accounts: [account], transactions: [oldTransaction]),
    );
    await tester.tap(find.text(account.name));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('opening-balance-toggle')));
    await tester.pump();

    expect(find.byKey(const Key('older-transactions-warning')), findsOneWidget);
  });

  testWidgets('narrow account layout uses one grid column', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _accountsPage(
        accounts: [
          Account(name: 'Cash'),
          Account(name: 'Bank'),
        ],
      ),
    );
    final grid = tester.widget<GridView>(
      find.byKey(const Key('accounts-grid')),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 1);
  });

  testWidgets('local profile setup collects display name and currency', (
    tester,
  ) async {
    LocalProfile? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalProfileSetupPage(onSave: (profile) async => saved = profile),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('profile-display-name-field')),
      'Enos',
    );
    await tester.enterText(
      find.byKey(const Key('profile-currency-field')),
      'usd',
    );
    await tester.tap(find.byKey(const Key('save-local-profile-button')));
    await tester.pump();

    expect(saved?.displayName, 'Enos');
    expect(saved?.defaultCurrencyCode, 'USD');
    expect(find.textContaining('not secure authentication'), findsOneWidget);
  });
}
