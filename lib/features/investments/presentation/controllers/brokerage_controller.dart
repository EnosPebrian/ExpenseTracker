import 'package:flutter/foundation.dart';

import '../../../assets/domain/entities/asset_definition.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../../domain/services/brokerage_activity_service.dart';

class BrokerageActivityRequest {
  const BrokerageActivityRequest({
    required this.activityType,
    required this.brokerageAccountId,
    required this.date,
    this.instrumentId,
    this.counterpartyAccountId,
    this.amount = 0,
    this.quantity,
    this.unitPrice,
    this.feeAmount = 0,
    this.splitNumerator,
    this.splitDenominator,
    this.note,
    this.reference,
  });

  final BrokerageActivityType activityType;
  final String brokerageAccountId;
  final DateTime date;
  final String? instrumentId;
  final String? counterpartyAccountId;
  final int amount;
  final double? quantity;
  final int? unitPrice;
  final int feeAmount;
  final int? splitNumerator;
  final int? splitDenominator;
  final String? note;
  final String? reference;
}

class BrokerageController extends ChangeNotifier {
  BrokerageController({
    required this.service,
    required this.accounts,
    required this.instruments,
    required this.onRecorded,
  });

  final BrokerageActivityService service;
  final List<Account> Function() accounts;
  final List<AssetDefinition> Function() instruments;
  final Future<void> Function() onRecorded;

  bool saving = false;
  String? error;

  Future<void> record({
    required String bookId,
    required String? memberId,
    required BrokerageActivityRequest request,
  }) async {
    if (saving) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final brokerage = _account(request.brokerageAccountId);
      switch (request.activityType) {
        case BrokerageActivityType.buy:
        case BrokerageActivityType.sell:
          await service.recordTrade(
            bookId: bookId,
            enteredByMemberId: memberId,
            brokerageAccount: brokerage,
            instrument: _instrument(request.instrumentId),
            action: request.activityType == BrokerageActivityType.buy
                ? AssetAction.buy
                : AssetAction.sell,
            date: request.date,
            grossAmount: request.amount,
            quantity: request.quantity ?? 0,
            unitPrice: request.unitPrice ?? 0,
            feeAmount: request.feeAmount,
            note: request.note,
            reference: request.reference,
          );
        case BrokerageActivityType.dividend:
        case BrokerageActivityType.fee:
        case BrokerageActivityType.tax:
          await service.recordCashActivity(
            bookId: bookId,
            enteredByMemberId: memberId,
            brokerageAccount: brokerage,
            activityType: request.activityType,
            date: request.date,
            amount: request.amount,
            instrument: request.instrumentId == null
                ? null
                : _instrument(request.instrumentId),
            note: request.note,
            reference: request.reference,
          );
        case BrokerageActivityType.deposit:
        case BrokerageActivityType.withdrawal:
          await service.recordFunding(
            bookId: bookId,
            enteredByMemberId: memberId,
            brokerageAccount: brokerage,
            counterpartyAccount: _account(request.counterpartyAccountId),
            direction: request.activityType == BrokerageActivityType.deposit
                ? BrokerageFundingDirection.deposit
                : BrokerageFundingDirection.withdrawal,
            date: request.date,
            amount: request.amount,
            note: request.note,
            reference: request.reference,
          );
        case BrokerageActivityType.split:
          await service.recordSplit(
            bookId: bookId,
            enteredByMemberId: memberId,
            brokerageAccount: brokerage,
            instrument: _instrument(request.instrumentId),
            date: request.date,
            numerator: request.splitNumerator ?? 0,
            denominator: request.splitDenominator ?? 0,
            note: request.note,
            reference: request.reference,
          );
      }
      await onRecorded();
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Account _account(String? id) {
    for (final account in accounts()) {
      if (account.id == id) return account;
    }
    throw StateError('The selected account is no longer available.');
  }

  AssetDefinition _instrument(String? id) {
    for (final instrument in instruments()) {
      if (instrument.id == id) return instrument;
    }
    throw StateError('The selected instrument is no longer available.');
  }
}
