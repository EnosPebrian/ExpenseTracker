import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/master_data/domain/services/account_balance_calculator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';

Transaction _transaction({
  required TransactionType type,
  required int amount,
  DateTime? date,
  AssetAction? action,
  int fee = 0,
  AssetFeeTreatment treatment = AssetFeeTreatment.none,
  TransactionRelationType relationType = TransactionRelationType.none,
  DateTime? deletedAt,
  String account = 'Cash',
}) {
  return Transaction(
    title: 'Entry',
    category: 'Other',
    account: account,
    date: date ?? DateTime(2026, 7, 26),
    amount: amount,
    type: type,
    assetAction: action,
    quantity: action == null ? null : 1,
    unit: action == null ? null : 'unit',
    unitPrice: action == null ? null : amount,
    assetName: action == null ? null : 'Asset',
    feeAmount: fee,
    feeTreatment: treatment,
    relationType: relationType,
    deletedAt: deletedAt,
  );
}

void main() {
  test('opening balance alone is the current balance', () {
    final account = Account(
      name: 'Cash',
      openingBalance: 500,
      openingBalanceDate: DateTime(2026, 7, 1),
    );
    expect(
      AccountBalanceCalculator.calculate(
        account: account,
        transactions: const [],
      ),
      500,
    );
  });

  test('income increases and expense decreases balance', () {
    final account = Account(name: 'Cash');
    final transactions = [
      _transaction(type: TransactionType.income, amount: 1000),
      _transaction(type: TransactionType.expense, amount: 300),
    ];
    expect(
      AccountBalanceCalculator.calculate(
        account: account,
        transactions: transactions,
      ),
      700,
    );
  });

  test(
    'pre-effective transactions are excluded and date itself is included',
    () {
      final account = Account(
        name: 'Cash',
        openingBalance: 100,
        openingBalanceDate: DateTime(2026, 7, 10),
      );
      final transactions = [
        _transaction(
          type: TransactionType.income,
          amount: 1000,
          date: DateTime(2026, 7, 9, 23),
        ),
        _transaction(
          type: TransactionType.expense,
          amount: 25,
          date: DateTime(2026, 7, 10, 8),
        ),
      ];
      expect(
        AccountBalanceCalculator.calculate(
          account: account,
          transactions: transactions,
        ),
        75,
      );
    },
  );

  test('soft-deleted transactions are ignored', () {
    final account = Account(name: 'Cash');
    expect(
      AccountBalanceCalculator.calculate(
        account: account,
        transactions: [
          _transaction(
            type: TransactionType.income,
            amount: 1000,
            deletedAt: DateTime(2026, 7, 27),
          ),
        ],
      ),
      0,
    );
  });

  test('asset buys and sells apply capitalized and deducted fees', () {
    final account = Account(name: 'Cash');
    final transactions = [
      _transaction(
        type: TransactionType.assetConversion,
        amount: 1000,
        action: AssetAction.buy,
        fee: 50,
        treatment: AssetFeeTreatment.capitalizeIntoCostBasis,
      ),
      _transaction(
        type: TransactionType.assetConversion,
        amount: 800,
        action: AssetAction.sell,
        fee: 25,
        treatment: AssetFeeTreatment.deductFromSaleProceeds,
      ),
    ];
    expect(
      AccountBalanceCalculator.calculate(
        account: account,
        transactions: transactions,
      ),
      -275,
    );
  });

  test(
    'asset conversion route applies cash effect to its financial account',
    () {
      final account = Account(name: 'BETA TEST Enos Bank');
      final purchase = Transaction(
        title: 'Gold acquisition',
        category: 'Asset Conversion',
        account: 'BETA TEST Enos Bank -> Gold Holdings',
        date: DateTime(2026, 7, 28),
        amount: 1000000,
        type: TransactionType.assetConversion,
        assetAction: AssetAction.buy,
      );

      expect(
        AccountBalanceCalculator.calculate(
          account: account,
          transactions: [purchase],
        ),
        -1000000,
      );
    },
  );

  test('separate linked fee is counted once through its expense record', () {
    final account = Account(name: 'Cash');
    final transactions = [
      _transaction(
        type: TransactionType.assetConversion,
        amount: 1000,
        action: AssetAction.buy,
        fee: 40,
        treatment: AssetFeeTreatment.recordAsSeparateExpense,
      ),
      _transaction(
        type: TransactionType.expense,
        amount: 40,
        relationType: TransactionRelationType.assetFeeExpense,
      ),
    ];
    expect(
      AccountBalanceCalculator.calculate(
        account: account,
        transactions: transactions,
      ),
      -1040,
    );
  });

  test(
    'configured zero and unset both include eligible transaction effects',
    () {
      final transaction = _transaction(
        type: TransactionType.income,
        amount: 10,
      );
      final unset = Account(name: 'Cash');
      final zero = Account(
        name: 'Cash',
        openingBalance: 0,
        openingBalanceDate: DateTime(2026, 7, 1),
      );
      expect(
        AccountBalanceCalculator.calculate(
          account: unset,
          transactions: [transaction],
        ),
        10,
      );
      expect(
        AccountBalanceCalculator.calculate(
          account: zero,
          transactions: [transaction],
        ),
        10,
      );
    },
  );

  test(
    'ambiguous legacy transfers and execution references have zero effect',
    () {
      final transfer = _transaction(
        type: TransactionType.transfer,
        amount: 500,
      );
      final conversion = _transaction(
        type: TransactionType.assetConversion,
        amount: 1000,
      );
      expect(AccountBalanceCalculator.cashEffect(transfer), 0);
      expect(AccountBalanceCalculator.cashEffect(conversion), 0);
    },
  );
}
