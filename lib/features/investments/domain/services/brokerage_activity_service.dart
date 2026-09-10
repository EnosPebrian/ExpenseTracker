import '../../../assets/domain/entities/asset_definition.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../../../transactions/domain/usecases/internal_transfer_usecases.dart';
import '../../../transactions/domain/usecases/transaction_usecases.dart';

enum BrokerageFundingDirection { deposit, withdrawal }

class BrokerageActivityService {
  BrokerageActivityService({
    required this.createTransaction,
    required this.internalTransfers,
  });

  final CreateTransaction createTransaction;
  final InternalTransferService internalTransfers;

  Future<Transaction> recordTrade({
    required String bookId,
    required String? enteredByMemberId,
    required Account brokerageAccount,
    required AssetDefinition instrument,
    required AssetAction action,
    required DateTime date,
    required int grossAmount,
    required double quantity,
    required int unitPrice,
    int feeAmount = 0,
    String? note,
    String? reference,
    String deviceId = 'local-device',
  }) async {
    if (action == AssetAction.split) {
      throw TransactionValidationException(
        'Use the split operation for a stock split.',
      );
    }
    _validateAccountAndInstrument(
      bookId: bookId,
      account: brokerageAccount,
      instrument: instrument,
    );
    final treatment = feeAmount == 0
        ? AssetFeeTreatment.none
        : action == AssetAction.buy
        ? AssetFeeTreatment.capitalizeIntoCostBasis
        : AssetFeeTreatment.deductFromSaleProceeds;
    return createTransaction(
      Transaction(
        bookId: bookId,
        enteredByMemberId: enteredByMemberId,
        title:
            '${action == AssetAction.buy ? 'Buy' : 'Sell'} ${instrument.displayName}',
        category: 'Investment',
        account: action == AssetAction.buy
            ? '${brokerageAccount.name} -> ${instrument.displayName}'
            : '${instrument.displayName} -> ${brokerageAccount.name}',
        date: date,
        amount: grossAmount,
        type: TransactionType.assetConversion,
        quantity: quantity,
        unit: instrument.normalizedUnit,
        unitPrice: unitPrice,
        assetDefinitionId: instrument.id,
        assetName: instrument.displayName,
        assetSymbol: instrument.normalizedSymbol,
        assetAction: action,
        brokerageAccountId: brokerageAccount.id,
        brokerageActivityType: action == AssetAction.buy
            ? BrokerageActivityType.buy
            : BrokerageActivityType.sell,
        feeAmount: feeAmount,
        feeTreatment: treatment,
        note: note,
        reference: reference,
        deviceId: deviceId,
      ),
    );
  }

  Future<Transaction> recordCashActivity({
    required String bookId,
    required String? enteredByMemberId,
    required Account brokerageAccount,
    required BrokerageActivityType activityType,
    required DateTime date,
    required int amount,
    AssetDefinition? instrument,
    String? note,
    String? reference,
    String deviceId = 'local-device',
  }) async {
    if (activityType != BrokerageActivityType.dividend &&
        activityType != BrokerageActivityType.fee &&
        activityType != BrokerageActivityType.tax) {
      throw TransactionValidationException(
        'Choose dividend, fee, or tax for an investment cash activity.',
      );
    }
    _validateBrokerageAccount(bookId, brokerageAccount);
    if (instrument != null) {
      _validateAccountAndInstrument(
        bookId: bookId,
        account: brokerageAccount,
        instrument: instrument,
      );
    }
    return createTransaction(
      Transaction(
        bookId: bookId,
        enteredByMemberId: enteredByMemberId,
        title: _cashTitle(activityType, instrument),
        category: 'Investment',
        account: brokerageAccount.name,
        date: date,
        amount: amount,
        type: TransactionType.investment,
        assetDefinitionId: instrument?.id,
        assetName: instrument?.displayName,
        assetSymbol: instrument?.normalizedSymbol,
        brokerageAccountId: brokerageAccount.id,
        brokerageActivityType: activityType,
        note: note,
        reference: reference,
        deviceId: deviceId,
      ),
    );
  }

  Future<Transaction> recordSplit({
    required String bookId,
    required String? enteredByMemberId,
    required Account brokerageAccount,
    required AssetDefinition instrument,
    required DateTime date,
    required int numerator,
    required int denominator,
    String? note,
    String? reference,
    String deviceId = 'local-device',
  }) async {
    _validateAccountAndInstrument(
      bookId: bookId,
      account: brokerageAccount,
      instrument: instrument,
    );
    return createTransaction(
      Transaction(
        bookId: bookId,
        enteredByMemberId: enteredByMemberId,
        title: '${instrument.displayName} split $numerator:$denominator',
        category: 'Investment',
        account: brokerageAccount.name,
        date: date,
        amount: 0,
        type: TransactionType.assetConversion,
        unit: instrument.normalizedUnit,
        assetDefinitionId: instrument.id,
        assetName: instrument.displayName,
        assetSymbol: instrument.normalizedSymbol,
        assetAction: AssetAction.split,
        brokerageAccountId: brokerageAccount.id,
        brokerageActivityType: BrokerageActivityType.split,
        splitNumerator: numerator,
        splitDenominator: denominator,
        note: note,
        reference: reference,
        deviceId: deviceId,
      ),
    );
  }

  Future<CanonicalInternalTransfer> recordFunding({
    required String bookId,
    required String? enteredByMemberId,
    required Account brokerageAccount,
    required Account counterpartyAccount,
    required BrokerageFundingDirection direction,
    required DateTime date,
    required int amount,
    String? note,
    String? reference,
    String deviceId = 'local-device',
  }) async {
    _validateBrokerageAccount(bookId, brokerageAccount);
    if (counterpartyAccount.bookId != bookId ||
        counterpartyAccount.deletedAt != null ||
        counterpartyAccount.id == brokerageAccount.id) {
      throw TransactionValidationException(
        'Choose another active account in this household.',
      );
    }
    if (counterpartyAccount.currencyCode != brokerageAccount.currencyCode) {
      throw TransactionValidationException(
        'Funding accounts must use the same currency.',
      );
    }
    final deposit = direction == BrokerageFundingDirection.deposit;
    return internalTransfers.create(
      bookId: bookId,
      enteredByMemberId: enteredByMemberId,
      title: deposit ? 'Brokerage deposit' : 'Brokerage withdrawal',
      sourceAccountId: deposit ? counterpartyAccount.id : brokerageAccount.id,
      destinationAccountId: deposit
          ? brokerageAccount.id
          : counterpartyAccount.id,
      date: date,
      amount: amount,
      note: note,
      reference: reference,
      brokerageAccountId: brokerageAccount.id,
      brokerageActivityType: deposit
          ? BrokerageActivityType.deposit
          : BrokerageActivityType.withdrawal,
      deviceId: deviceId,
    );
  }

  static void _validateAccountAndInstrument({
    required String bookId,
    required Account account,
    required AssetDefinition instrument,
  }) {
    _validateBrokerageAccount(bookId, account);
    if (instrument.bookId != bookId || instrument.isDeleted) {
      throw TransactionValidationException(
        'Choose an active instrument in this household.',
      );
    }
    if (instrument.normalizedCurrencyCode != account.currencyCode) {
      throw TransactionValidationException(
        'Instrument and brokerage account currencies must match.',
      );
    }
  }

  static void _validateBrokerageAccount(String bookId, Account account) {
    if (account.bookId != bookId ||
        account.deletedAt != null ||
        account.accountType != AccountType.brokerage) {
      throw TransactionValidationException(
        'Choose an active brokerage account in this household.',
      );
    }
  }

  static String _cashTitle(
    BrokerageActivityType type,
    AssetDefinition? instrument,
  ) {
    final suffix = instrument == null ? '' : ' · ${instrument.displayName}';
    return '${type.label}$suffix';
  }
}
