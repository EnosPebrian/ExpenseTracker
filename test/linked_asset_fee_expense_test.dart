import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/analytics/domain/financial_summary.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_trade_fee_accounting.dart';
import 'package:pilgrim_tracker/features/assets/domain/services/asset_portfolio_calculator.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction_relation_type.dart';
import 'package:pilgrim_tracker/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pilgrim_tracker/features/transactions/domain/usecases/transaction_usecases.dart';

class _AtomicRepository implements TransactionRepository {
  final records = <Transaction>[];
  bool failAtomicWrite = false;

  @override
  Future<List<Transaction>> getAll() async =>
      records.where((transaction) => transaction.deletedAt == null).toList();

  @override
  Future<Transaction?> getAssetFeeExpense(
    String parentTransactionId, {
    bool includeDeleted = true,
  }) async {
    for (final transaction in records) {
      if (transaction.relatedTransactionId == parentTransactionId &&
          transaction.relationType == TransactionRelationType.assetFeeExpense &&
          (includeDeleted || transaction.deletedAt == null)) {
        return transaction;
      }
    }
    return null;
  }

  @override
  Future<void> save(Transaction transaction) async => _upsert(transaction);

  @override
  Future<void> softDelete(Transaction transaction) async =>
      _upsert(transaction);

  @override
  Future<void> saveAssetFeeChange({
    required Transaction parent,
    Transaction? linkedExpense,
    Transaction? obsoleteLinkedExpense,
  }) async {
    final snapshot = List<Transaction>.of(records);
    try {
      _upsert(parent);
      if (failAtomicWrite) throw StateError('atomic write failed');
      if (linkedExpense != null) _upsert(linkedExpense);
      if (obsoleteLinkedExpense != null &&
          obsoleteLinkedExpense.id != linkedExpense?.id) {
        _upsert(obsoleteLinkedExpense);
      }
    } catch (_) {
      records
        ..clear()
        ..addAll(snapshot);
      rethrow;
    }
  }

  void _upsert(Transaction transaction) {
    records.removeWhere((item) => item.id == transaction.id);
    records.add(transaction);
  }
}

Transaction _parent({
  String id = 'parent-usd',
  AssetAction action = AssetAction.buy,
  int feeAmount = 100000,
  AssetFeeTreatment treatment = AssetFeeTreatment.recordAsSeparateExpense,
  String? projectId = 'life',
  DateTime? date,
  String? account,
}) {
  return Transaction(
    id: id,
    projectId: projectId,
    title: action == AssetAction.buy ? 'USD acquisition' : 'USD sale',
    category: 'Asset conversion',
    account:
        account ??
        (action == AssetAction.buy
            ? 'Cash Enos -> US Dollar Cash'
            : 'US Dollar Cash -> BNI Enos'),
    date: date ?? DateTime(2026, 7, 24, 10),
    amount: action == AssetAction.buy ? 16200000 : 6640000,
    type: TransactionType.assetConversion,
    quantity: action == AssetAction.buy ? 1000 : 400,
    unit: 'usd',
    unitPrice: action == AssetAction.buy ? 16200 : 16600,
    assetDefinitionId: 'asset-usd',
    assetName: 'US Dollar Cash',
    assetSymbol: 'USD',
    assetAction: action,
    feeAmount: feeAmount,
    feeTreatment: treatment,
  );
}

void main() {
  test(
    'separate fee creates exactly one linked ordinary expense atomically',
    () async {
      final repository = _AtomicRepository();
      final created = await CreateTransaction(repository)(_parent());
      final active = await repository.getAll();
      final child = await repository.getAssetFeeExpense(created.id);

      expect(active, hasLength(2));
      expect(child, isNotNull);
      expect(child!.type, TransactionType.expense);
      expect(child.amount, 100000);
      expect(child.account, 'Cash Enos');
      expect(child.projectId, 'life');
      expect(child.relatedTransactionId, created.id);
      expect(child.relationType, TransactionRelationType.assetFeeExpense);
      expect(child.marketReferenceUnitPrice, isNull);
      expect(child.marketReferenceCurrencyCode, isNull);
      expect(child.marketReferenceUnit, isNull);
      expect(child.marketReferenceSource, isNull);
      expect(child.marketReferenceQuotedAt, isNull);
      expect(child.feeAmount, 0);
      expect(child.assetDefinitionId, isNull);

      final failedRepository = _AtomicRepository()..failAtomicWrite = true;
      await expectLater(
        CreateTransaction(failedRepository)(_parent(id: 'failed-parent')),
        throwsStateError,
      );
      expect(failedRepository.records, isEmpty);
    },
  );

  test('edit updates the same child and aligns parent context', () async {
    final repository = _AtomicRepository();
    final created = await CreateTransaction(repository)(_parent());
    final originalChild = await repository.getAssetFeeExpense(created.id);
    final changedDate = DateTime(2026, 8, 2, 14, 30);

    await UpdateTransaction(repository)(
      created.copyWith(
        feeAmount: 125000,
        date: changedDate,
        account: 'BNI Enos -> US Dollar Cash',
        projectId: 'tebu-nai',
      ),
    );
    final updatedChild = await repository.getAssetFeeExpense(created.id);

    expect(updatedChild!.id, originalChild!.id);
    expect(updatedChild.createdAt, originalChild.createdAt);
    expect(updatedChild.version, originalChild.version + 1);
    expect(updatedChild.amount, 125000);
    expect(updatedChild.date, changedDate);
    expect(updatedChild.account, 'BNI Enos');
    expect(updatedChild.projectId, 'tebu-nai');
  });

  test(
    'switching treatment soft deletes and later restores the same child',
    () async {
      final repository = _AtomicRepository();
      final created = await CreateTransaction(repository)(_parent());
      final child = await repository.getAssetFeeExpense(created.id);

      final capitalized = await UpdateTransaction(repository)(
        created.copyWith(
          feeTreatment: AssetFeeTreatment.capitalizeIntoCostBasis,
        ),
      );
      final deletedChild = await repository.getAssetFeeExpense(created.id);
      expect(deletedChild!.id, child!.id);
      expect(deletedChild.deletedAt, isNotNull);
      expect(await repository.getAll(), hasLength(1));

      await UpdateTransaction(repository)(
        capitalized.copyWith(
          feeTreatment: AssetFeeTreatment.recordAsSeparateExpense,
        ),
      );
      final restored = await repository.getAssetFeeExpense(created.id);
      expect(restored!.id, child.id);
      expect(restored.deletedAt, isNull);
      expect(await repository.getAll(), hasLength(2));
    },
  );

  test(
    'duplicate and delete maintain independent linked child lifecycle',
    () async {
      final repository = _AtomicRepository();
      final created = await CreateTransaction(repository)(_parent());
      final originalChild = await repository.getAssetFeeExpense(created.id);
      final duplicate = await DuplicateTransaction(repository)(created);
      final duplicateChild = await repository.getAssetFeeExpense(duplicate.id);

      expect(duplicate.id, isNot(created.id));
      expect(duplicateChild!.id, isNot(originalChild!.id));
      expect(duplicateChild.relatedTransactionId, duplicate.id);

      await DeleteTransaction(repository)(duplicate);
      final deletedChild = await repository.getAssetFeeExpense(duplicate.id);
      expect(deletedChild!.deletedAt, isNotNull);
      expect((await repository.getAll()).map((item) => item.id), [
        created.id,
        originalChild.id,
      ]);
    },
  );

  test('managed child cannot be independently changed or removed', () async {
    final repository = _AtomicRepository();
    final parent = await CreateTransaction(repository)(_parent());
    final child = (await repository.getAssetFeeExpense(parent.id))!;

    await expectLater(
      UpdateTransaction(repository)(child.copyWith(amount: 1)),
      throwsA(
        isA<TransactionValidationException>().having(
          (error) => error.message,
          'message',
          managedAssetFeeExpenseMessage,
        ),
      ),
    );
    await expectLater(
      DuplicateTransaction(repository)(child),
      throwsA(isA<TransactionValidationException>()),
    );
    await expectLater(
      DeleteTransaction(repository)(child),
      throwsA(isA<TransactionValidationException>()),
    );
  });

  test(
    'separate fee affects reports once but not portfolio fee accounting',
    () async {
      final repository = _AtomicRepository();
      final parent = await CreateTransaction(repository)(_parent());
      final child = (await repository.getAssetFeeExpense(parent.id))!;
      final summary = FinancialSummary.calculate(
        referenceDate: DateTime(2026, 7, 24),
        transactions: [parent, child],
      );

      expect(summary.monthlyExpenses, 100000);
      expect(summary.spendingByCategory.single.category, 'Asset Fees');
      expect(summary.spendingByCategory.single.amount, 100000);
      expect(AssetTradeFeeAccounting.buyCostContribution(parent), 16200000);

      final sale = _parent(
        id: 'sale-usd',
        action: AssetAction.sell,
        feeAmount: 40000,
      );
      expect(AssetTradeFeeAccounting.netSaleProceeds(sale), 6640000);

      final portfolio = AssetPortfolioCalculator.calculate(
        transactions: [parent, sale],
      );
      final holding = portfolio.holdings.single;
      expect(holding.quantity, 600);
      expect(holding.costBasis, 9720000);
      expect(holding.realizedGain, 160000);
    },
  );
}
