import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_definition.dart';
import 'package:pilgrim_tracker/features/assets/domain/entities/asset_kind.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/services/account_balance_calculator.dart';
import 'package:pilgrim_tracker/features/tithe/domain/tithe_policy.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/controllers/transaction_controller.dart';
import 'package:pilgrim_tracker/features/transactions/presentation/quick_add/quick_add_controller.dart';

void main() {
  test(
    'normal, Quick Add, and asset transactions use active context',
    () async {
      final repository = _Repository();
      final controller = _controller(repository);
      controller.setActiveContext(bookId: 'household', memberId: 'enos');
      addTearDown(controller.dispose);

      await controller.createTransaction(_expense(id: 'normal'));
      final quickAdd = QuickAddController(
        transactions: controller,
        config: QuickAddConfig(
          accounts: const ['Cash'],
          expenseCategories: const ['Food'],
          incomeCategories: const ['Salary'],
          projects: const ['Life'],
          assetDefinitions: [_gold],
        ),
      );
      addTearDown(quickAdd.dispose);
      quickAdd.setAmountText('25.000');
      expect(await quickAdd.save(), isTrue);

      await controller.createTransaction(
        Transaction(
          id: 'asset',
          title: 'Gold acquisition',
          category: 'Asset conversion',
          account: 'Cash -> Gold',
          date: DateTime(2026, 7, 2),
          amount: 1000000,
          type: TransactionType.assetConversion,
          assetDefinitionId: _gold.id,
          assetName: _gold.displayName,
          assetAction: AssetAction.buy,
          quantity: 1,
          unit: _gold.unit,
          unitPrice: 1000000,
        ),
      );

      expect(repository.saved, hasLength(3));
      for (final transaction in repository.saved) {
        expect(transaction.bookId, 'household');
        expect(transaction.enteredByMemberId, 'enos');
      }
    },
  );

  test(
    'duplicate uses current active member and historical null stays valid',
    () async {
      final repository = _Repository();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      final original = _expense(
        id: 'original',
      ).copyWith(bookId: 'household', enteredByMemberId: 'enos');
      controller.setActiveContext(bookId: 'household', memberId: 'grace');
      final duplicate = await controller.duplicateTransaction(original);

      expect(duplicate?.bookId, 'household');
      expect(duplicate?.enteredByMemberId, 'grace');
      expect(_expense(id: 'legacy').enteredByMemberId, isNull);
    },
  );

  test('attribution does not change summaries or account balances', () {
    final legacy = [
      _expense(id: 'expense'),
      Transaction(
        id: 'income',
        title: 'Salary',
        category: 'Salary',
        account: 'Cash',
        date: DateTime(2026, 7, 3),
        amount: 500000,
        type: TransactionType.income,
      ),
    ];
    final attributed = legacy
        .map(
          (transaction) => transaction.copyWith(
            bookId: 'household',
            enteredByMemberId: 'grace',
          ),
        )
        .toList();
    final legacySummary = FinancialSummary.calculate(
      transactions: legacy,
      referenceDate: DateTime(2026, 7, 10),
      tithePolicy: TithePolicy.defaultPolicy,
    );
    final attributedSummary = FinancialSummary.calculate(
      transactions: attributed,
      referenceDate: DateTime(2026, 7, 10),
      tithePolicy: TithePolicy.defaultPolicy,
    );
    expect(attributedSummary.monthlyIncome, legacySummary.monthlyIncome);
    expect(attributedSummary.monthlyExpenses, legacySummary.monthlyExpenses);
    expect(attributedSummary.pendingTithe, legacySummary.pendingTithe);
    final account = Account(name: 'Cash');
    expect(
      AccountBalanceCalculator.calculate(
        account: account,
        transactions: attributed,
      ),
      AccountBalanceCalculator.calculate(
        account: account,
        transactions: legacy,
      ),
    );
  });
}

final _gold = AssetDefinition(
  id: 'gold',
  displayName: 'Gold',
  kind: AssetKind.gold,
  symbol: null,
  providerCode: null,
  providerSymbol: null,
  exchangeCode: null,
  currencyCode: 'IDR',
  unit: 'gram',
  lotSize: 1,
  onlinePricingEnabled: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  deletedAt: null,
  version: 1,
  deviceId: 'test',
  syncStatus: 'local_only',
);

Transaction _expense({required String id}) => Transaction(
  id: id,
  title: 'Groceries',
  category: 'Food',
  account: 'Cash',
  date: DateTime(2026, 7, 2),
  amount: 100000,
  type: TransactionType.expense,
);

TransactionController _controller(_Repository repository) {
  AssetDefinition? resolve(String id) => id == _gold.id ? _gold : null;
  return TransactionController(
    create: CreateTransaction(repository, assetDefinitionResolver: resolve),
    update: UpdateTransaction(repository, assetDefinitionResolver: resolve),
    delete: DeleteTransaction(repository),
    get: GetTransactions(repository),
    duplicate: DuplicateTransaction(
      repository,
      assetDefinitionResolver: resolve,
    ),
  );
}

class _Repository implements TransactionRepository {
  final saved = <Transaction>[];

  @override
  Future<List<Transaction>> getAll({bool includeDeleted = false}) async =>
      saved.where((item) => includeDeleted || item.deletedAt == null).toList();

  @override
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async => null;

  @override
  Future<void> save(Transaction transaction) async {
    saved.removeWhere((item) => item.id == transaction.id);
    saved.add(transaction);
  }

  @override
  Future<void> softDelete(Transaction transaction) => save(transaction);

  @override
  Future<void> saveAssetFeeChange({
    required Transaction parent,
    Transaction? linkedExpense,
    Transaction? obsoleteLinkedExpense,
  }) async {
    await save(parent);
    if (linkedExpense != null) await save(linkedExpense);
    if (obsoleteLinkedExpense != null) await save(obsoleteLinkedExpense);
  }
}
