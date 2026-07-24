import '../entities/transaction.dart';
import '../entities/transaction_relation_type.dart';
import '../repositories/transaction_repository.dart';

const assetFeeExpenseCategory = 'Asset Fees';

class SaveAssetConversionWithFee {
  SaveAssetConversionWithFee(this.repository);

  final TransactionRepository repository;

  Future<void> save(Transaction parent) async {
    final existing = await repository.getAssetFeeExpense(parent.id);
    final usesSeparateExpense =
        parent.feeAmount > 0 &&
        parent.feeTreatment == AssetFeeTreatment.recordAsSeparateExpense;

    Transaction? linkedExpense;
    Transaction? obsoleteLinkedExpense;

    if (usesSeparateExpense) {
      linkedExpense = _linkedExpense(parent, existing);
    } else if (existing != null && existing.deletedAt == null) {
      obsoleteLinkedExpense = _softDeleted(existing);
    }

    await repository.saveAssetFeeChange(
      parent: parent,
      linkedExpense: linkedExpense,
      obsoleteLinkedExpense: obsoleteLinkedExpense,
    );
  }

  Future<void> delete(Transaction deletedParent) async {
    final existing = await repository.getAssetFeeExpense(deletedParent.id);
    await repository.saveAssetFeeChange(
      parent: deletedParent,
      obsoleteLinkedExpense: existing == null || existing.deletedAt != null
          ? null
          : _softDeleted(existing),
    );
  }

  Transaction _linkedExpense(Transaction parent, Transaction? existing) {
    final now = DateTime.now();
    final title = _title(parent);
    final account = _settlementAccount(parent);

    if (existing == null) {
      return Transaction(
        projectId: parent.projectId,
        title: title,
        category: assetFeeExpenseCategory,
        account: account,
        date: parent.date,
        amount: parent.feeAmount,
        type: TransactionType.expense,
        relatedTransactionId: parent.id,
        relationType: TransactionRelationType.assetFeeExpense,
        deviceId: parent.deviceId,
        syncStatus: 'pending',
      );
    }

    return existing.copyWith(
      projectId: parent.projectId,
      title: title,
      category: assetFeeExpenseCategory,
      account: account,
      date: parent.date,
      amount: parent.feeAmount,
      type: TransactionType.expense,
      quantity: null,
      unit: null,
      unitPrice: null,
      assetDefinitionId: null,
      assetName: null,
      assetSymbol: null,
      assetAction: null,
      marketReferenceUnitPrice: null,
      marketReferenceCurrencyCode: null,
      marketReferenceUnit: null,
      marketReferenceSource: null,
      marketReferenceQuotedAt: null,
      feeAmount: 0,
      feeTreatment: AssetFeeTreatment.none,
      relatedTransactionId: parent.id,
      relationType: TransactionRelationType.assetFeeExpense,
      updatedAt: now,
      deletedAt: null,
      version: existing.version + 1,
      syncStatus: 'pending',
    );
  }

  Transaction _softDeleted(Transaction transaction) {
    final now = DateTime.now();
    return transaction.copyWith(
      deletedAt: now,
      updatedAt: now,
      version: transaction.version + 1,
      syncStatus: 'pending',
    );
  }

  String _settlementAccount(Transaction parent) {
    final accounts = parent.account
        .split('->')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (accounts.isEmpty) {
      return parent.account.trim();
    }

    return parent.assetAction == AssetAction.sell
        ? accounts.last
        : accounts.first;
  }

  String _title(Transaction parent) {
    final snapshot = parent.assetSymbol?.trim().isNotEmpty == true
        ? parent.assetSymbol!.trim()
        : parent.assetName?.trim().isNotEmpty == true
        ? parent.assetName!.trim()
        : 'asset';
    final action = parent.assetAction == AssetAction.sell ? 'Sell' : 'Buy';
    return 'Fee - $action $snapshot';
  }
}
