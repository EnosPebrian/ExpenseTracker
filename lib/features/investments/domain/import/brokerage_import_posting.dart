import '../../../assets/domain/entities/asset_definition.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/internal_transfer_link.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../import/brokerage_import_identity.dart';
import '../import/brokerage_import_models.dart';

class BrokerageImportPostingPlan {
  const BrokerageImportPostingPlan({
    required this.transactions,
    this.transferLink,
  });

  final List<Transaction> transactions;
  final InternalTransferLink? transferLink;

  Set<String> get transactionIds =>
      transactions.map((transaction) => transaction.id).toSet();
}

class BrokerageImportPosting {
  const BrokerageImportPosting._();

  static BrokerageImportPostingPlan materialize({
    required BrokerageImportDraft draft,
    required String bookId,
    required String? memberId,
    required Account brokerageAccount,
    required Account? counterpartyAccount,
    required AssetDefinition? instrument,
    String deviceId = 'local-device',
  }) {
    final activity = draft.activityType;
    if (activity == null) {
      throw StateError('Resolve the brokerage activity before importing.');
    }
    final transactions = <Transaction>[];
    InternalTransferLink? link;
    if (activity == BrokerageActivityType.deposit ||
        activity == BrokerageActivityType.withdrawal) {
      if (counterpartyAccount == null) {
        throw StateError('Choose the other funding account before importing.');
      }
      final deposit = activity == BrokerageActivityType.deposit;
      final outgoingId = BrokerageImportIdentity.child(
        draft.eventId,
        'funding-outgoing',
      );
      final incomingId = BrokerageImportIdentity.child(
        draft.eventId,
        'funding-incoming',
      );
      final source = deposit ? counterpartyAccount : brokerageAccount;
      final destination = deposit ? brokerageAccount : counterpartyAccount;
      transactions.addAll([
        Transaction(
          id: outgoingId,
          bookId: bookId,
          enteredByMemberId: memberId,
          title: deposit ? 'Brokerage deposit' : 'Brokerage withdrawal',
          category: 'Transfer',
          account: source.name,
          date: draft.date,
          amount: draft.grossAmount,
          type: TransactionType.expense,
          note: draft.note,
          reference: draft.reference,
          brokerageAccountId: source.id == brokerageAccount.id
              ? brokerageAccount.id
              : null,
          brokerageActivityType: source.id == brokerageAccount.id
              ? activity
              : null,
          deviceId: deviceId,
          syncStatus: 'pending',
        ),
        Transaction(
          id: incomingId,
          bookId: bookId,
          enteredByMemberId: memberId,
          title: deposit ? 'Brokerage deposit' : 'Brokerage withdrawal',
          category: 'Transfer',
          account: destination.name,
          date: draft.date,
          amount: draft.grossAmount,
          type: TransactionType.income,
          note: draft.note,
          reference: draft.reference,
          brokerageAccountId: destination.id == brokerageAccount.id
              ? brokerageAccount.id
              : null,
          brokerageActivityType: destination.id == brokerageAccount.id
              ? activity
              : null,
          deviceId: deviceId,
          syncStatus: 'pending',
        ),
      ]);
      link = InternalTransferLink(
        id: BrokerageImportIdentity.child(draft.eventId, 'funding-link'),
        bookId: bookId,
        outgoingTransactionId: outgoingId,
        incomingTransactionId: incomingId,
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        currencyCode: brokerageAccount.currencyCode,
        amount: draft.grossAmount,
        deviceId: deviceId,
        syncStatus: 'pending',
      );
    } else if (activity == BrokerageActivityType.buy ||
        activity == BrokerageActivityType.sell) {
      final buy = activity == BrokerageActivityType.buy;
      transactions.add(
        Transaction(
          id: draft.eventId,
          bookId: bookId,
          enteredByMemberId: memberId,
          title: '${buy ? 'Buy' : 'Sell'} ${draft.sourceInstrument}',
          category: 'Investment',
          account: buy
              ? '${brokerageAccount.name} -> ${draft.sourceInstrument}'
              : '${draft.sourceInstrument} -> ${brokerageAccount.name}',
          date: draft.date,
          amount: draft.grossAmount,
          type: TransactionType.assetConversion,
          quantity: draft.quantity,
          unit: instrument?.normalizedUnit,
          unitPrice: draft.executionPrice,
          assetDefinitionId: draft.instrumentId,
          assetName: instrument?.displayName ?? draft.sourceInstrument,
          assetSymbol:
              instrument?.normalizedSymbol ??
              draft.sourceInstrument.trim().toUpperCase(),
          assetAction: buy ? AssetAction.buy : AssetAction.sell,
          brokerageAccountId: brokerageAccount.id,
          brokerageActivityType: activity,
          feeAmount: draft.feeAmount,
          feeTreatment: draft.feeAmount == 0
              ? AssetFeeTreatment.none
              : buy
              ? AssetFeeTreatment.capitalizeIntoCostBasis
              : AssetFeeTreatment.deductFromSaleProceeds,
          note: draft.note,
          reference: draft.reference,
          deviceId: deviceId,
          syncStatus: 'pending',
        ),
      );
    } else if (activity == BrokerageActivityType.split) {
      transactions.add(
        Transaction(
          id: draft.eventId,
          bookId: bookId,
          enteredByMemberId: memberId,
          title:
              '${draft.sourceInstrument} split ${draft.splitNumerator}:${draft.splitDenominator}',
          category: 'Investment',
          account: brokerageAccount.name,
          date: draft.date,
          amount: 0,
          type: TransactionType.assetConversion,
          unit: instrument?.normalizedUnit,
          assetDefinitionId: draft.instrumentId,
          assetName: instrument?.displayName ?? draft.sourceInstrument,
          assetSymbol:
              instrument?.normalizedSymbol ??
              draft.sourceInstrument.trim().toUpperCase(),
          assetAction: AssetAction.split,
          brokerageAccountId: brokerageAccount.id,
          brokerageActivityType: activity,
          splitNumerator: draft.splitNumerator,
          splitDenominator: draft.splitDenominator,
          note: draft.note,
          reference: draft.reference,
          deviceId: deviceId,
          syncStatus: 'pending',
        ),
      );
    } else {
      transactions.add(
        _investmentCostOrIncome(
          id: draft.eventId,
          draft: draft,
          activity: activity,
          bookId: bookId,
          memberId: memberId,
          brokerageAccount: brokerageAccount,
          deviceId: deviceId,
        ),
      );
    }

    if (activity != BrokerageActivityType.buy &&
        activity != BrokerageActivityType.sell &&
        activity != BrokerageActivityType.fee &&
        draft.feeAmount > 0) {
      transactions.add(
        _investmentCostOrIncome(
          id: BrokerageImportIdentity.child(draft.eventId, 'fee'),
          draft: draft,
          activity: BrokerageActivityType.fee,
          amount: draft.feeAmount,
          bookId: bookId,
          memberId: memberId,
          brokerageAccount: brokerageAccount,
          deviceId: deviceId,
        ),
      );
    }
    if (activity != BrokerageActivityType.tax && draft.taxAmount > 0) {
      transactions.add(
        _investmentCostOrIncome(
          id: BrokerageImportIdentity.child(draft.eventId, 'tax'),
          draft: draft,
          activity: BrokerageActivityType.tax,
          amount: draft.taxAmount,
          bookId: bookId,
          memberId: memberId,
          brokerageAccount: brokerageAccount,
          deviceId: deviceId,
        ),
      );
    }
    return BrokerageImportPostingPlan(
      transactions: List.unmodifiable(transactions),
      transferLink: link,
    );
  }

  static Transaction _investmentCostOrIncome({
    required String id,
    required BrokerageImportDraft draft,
    required BrokerageActivityType activity,
    required String bookId,
    required String? memberId,
    required Account brokerageAccount,
    required String deviceId,
    int? amount,
  }) => Transaction(
    id: id,
    bookId: bookId,
    enteredByMemberId: memberId,
    title:
        '${activity.label}${draft.sourceInstrument.trim().isEmpty ? '' : ' · ${draft.sourceInstrument}'}',
    category: 'Investment',
    account: brokerageAccount.name,
    date: draft.date,
    amount: amount ?? draft.grossAmount,
    type: TransactionType.investment,
    assetDefinitionId: draft.instrumentId,
    assetName: draft.plannedInstrument?.displayName,
    assetSymbol: draft.plannedInstrument?.normalizedSymbol,
    brokerageAccountId: brokerageAccount.id,
    brokerageActivityType: activity,
    note: draft.note,
    reference: draft.reference,
    deviceId: deviceId,
    syncStatus: 'pending',
  );
}
