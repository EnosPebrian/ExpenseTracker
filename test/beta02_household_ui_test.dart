import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/financial_book.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/household_member.dart';
import 'package:pilgrim_tracker/features/master_data/presentation/screens/accounts_page.dart';
import 'package:pilgrim_tracker/features/master_data/presentation/screens/household_settings_page.dart';

void main() {
  final enos = HouseholdMember(
    id: 'enos',
    bookId: 'book',
    displayName: 'Enos',
    role: HouseholdMemberRole.owner,
  );
  final grace = HouseholdMember(
    id: 'grace',
    bookId: 'book',
    displayName: 'Grace',
  );

  testWidgets(
    'household page identifies local members and switches active member',
    (tester) async {
      HouseholdMember? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HouseholdSettingsPage(
              book: FinancialBook(
                id: 'book',
                name: 'My Household',
                baseCurrencyCode: 'IDR',
              ),
              members: [enos, grace],
              activeMemberId: enos.id,
              onRenameBook: (_) async {},
              onAddMember: (_) async {},
              onRenameMember: (_, _) async {},
              onSelectActiveMember: (member) async => selected = member,
            ),
          ),
        ),
      );

      expect(find.text('My Household'), findsOneWidget);
      expect(find.text('Base currency: IDR'), findsOneWidget);
      expect(
        find.textContaining('Multi-device sharing will be enabled'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('household-member-grace')));
      await tester.pump();
      expect(selected?.id, grace.id);
    },
  );

  testWidgets(
    'account editor selects a member owner without changing balance',
    (tester) async {
      Account? saved;
      final account = Account(
        id: 'cash',
        name: 'Cash',
        openingBalance: 500000,
        openingBalanceDate: DateTime(2026, 7, 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountsPage(
              accountRecords: [account],
              transactions: const [],
              defaultCurrencyCode: 'IDR',
              members: [enos, grace],
              onSave: (value) async => saved = value,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-owner-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grace').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-account-button')));
      await tester.pumpAndSettle();

      expect(saved?.id, account.id);
      expect(saved?.ownerMemberId, grace.id);
      expect(saved?.openingBalance, 500000);
    },
  );
}
