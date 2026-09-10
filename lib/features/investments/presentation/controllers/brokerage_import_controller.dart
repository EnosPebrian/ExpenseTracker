import 'package:flutter/foundation.dart';

import '../../../assets/domain/entities/asset_definition.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/data/csv_transaction_source_parser.dart';
import '../../../transactions/domain/entities/internal_transfer_link.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/entities/transaction_brokerage_metadata.dart';
import '../../../transactions/domain/import/transaction_import_models.dart';
import '../../domain/import/brokerage_import_commit_service.dart';
import '../../domain/import/brokerage_import_models.dart';
import '../../domain/import/brokerage_import_planner.dart';

class BrokerageImportController extends ChangeNotifier {
  BrokerageImportController({
    required this.pickFile,
    required this.commitService,
    required this.accounts,
    required this.instruments,
    required this.transactions,
    required this.transferLinks,
    required this.onImported,
    this.parser = const CsvTransactionSourceParser(),
    this.planner = const BrokerageImportPlanner(),
  });

  final Future<SelectedCsvFile?> Function() pickFile;
  final BrokerageImportCommitService commitService;
  final List<Account> Function() accounts;
  final List<AssetDefinition> Function() instruments;
  final List<Transaction> Function() transactions;
  final List<InternalTransferLink> Function() transferLinks;
  final Future<void> Function() onImported;
  final CsvTransactionSourceParser parser;
  final BrokerageImportPlanner planner;

  CsvParsedSource? source;
  BrokerageStatementMapping? mapping;
  BrokerageImportPreview? preview;
  BrokerageImportResult? result;
  String? brokerageAccountId;
  String? counterpartyAccountId;
  bool busy = false;
  String? error;

  Future<void> selectCsv() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final selected = await pickFile();
      if (selected == null) return;
      source = await parser.parse(selected);
      mapping =
          canonicalBrokerageMappingFor(source!.headers) ??
          _initialMapping(source!);
      preview = null;
      result = null;
    } catch (exception) {
      error = exception.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void setAccounts({required String brokerageId, String? counterpartyId}) {
    brokerageAccountId = brokerageId;
    counterpartyAccountId = counterpartyId;
    preview = null;
    result = null;
    notifyListeners();
  }

  void setMapping(BrokerageStatementMapping value) {
    mapping = value;
    preview = null;
    result = null;
    notifyListeners();
  }

  Future<void> analyze({
    required String bookId,
    bool remoteFresh = true,
  }) async {
    final currentSource = source;
    final currentMapping = mapping;
    if (currentSource == null || currentMapping == null) {
      error = 'Choose and map a brokerage CSV first.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      preview = await planner.build(
        source: currentSource,
        mapping: currentMapping,
        brokerageAccount: _brokerageAccount(),
        activeBookId: bookId,
        instruments: instruments(),
        existingTransactions: transactions(),
        existingTransferLinks: transferLinks(),
        counterpartyAccount: _counterpartyAccount(),
        remoteFreshnessVerified: remoteFresh,
      );
    } catch (exception) {
      error = exception.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void resolveActivity(
    int rowNumber,
    BrokerageActivityType activity, {
    required String bookId,
  }) => _replace(
    rowNumber,
    (draft) => planner.resolveActivity(
      draft: draft,
      activityType: activity,
      activeBookId: bookId,
      brokerageAccount: _brokerageAccount(),
      counterpartyAccount: _counterpartyAccount(),
      instruments: instruments(),
      existingTransactions: transactions(),
      existingTransferLinks: transferLinks(),
    ),
  );

  void mapInstrument(
    int rowNumber,
    AssetDefinition instrument, {
    required String bookId,
  }) => _replace(
    rowNumber,
    (draft) => planner.mapInstrument(
      draft: draft,
      instrument: instrument,
      activeBookId: bookId,
      brokerageAccount: _brokerageAccount(),
      counterpartyAccount: _counterpartyAccount(),
      instruments: instruments(),
      existingTransactions: transactions(),
      existingTransferLinks: transferLinks(),
    ),
  );

  void createInstrument(int rowNumber, {required String bookId}) => _replace(
    rowNumber,
    (draft) => planner.createInstrument(
      draft: draft,
      activeBookId: bookId,
      brokerageAccount: _brokerageAccount(),
      counterpartyAccount: _counterpartyAccount(),
      instruments: instruments(),
      existingTransactions: transactions(),
      existingTransferLinks: transferLinks(),
    ),
  );

  void setIncluded(int rowNumber, bool included) => _replace(
    rowNumber,
    (draft) =>
        draft.canChangeInclusion ? draft.copyWith(included: included) : draft,
  );

  Future<void> commit({
    required String bookId,
    required String? memberId,
  }) async {
    final current = preview;
    if (current == null) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      result = await commitService.commit(
        preview: current,
        bookId: bookId,
        memberId: memberId,
        brokerageAccount: _brokerageAccount(),
        counterpartyAccount: _counterpartyAccount(),
        existingInstruments: instruments(),
        existingTransactions: transactions(),
      );
      await onImported();
    } catch (exception) {
      error = exception.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _replace(
    int rowNumber,
    BrokerageImportDraft Function(BrokerageImportDraft draft) update,
  ) {
    final current = preview;
    if (current == null) return;
    preview = BrokerageImportPreview(
      source: current.source,
      drafts: [
        for (final draft in current.drafts)
          if (draft.sourceRowNumber == rowNumber) update(draft) else draft,
      ],
      remoteFreshnessVerified: current.remoteFreshnessVerified,
    );
    result = null;
    error = null;
    notifyListeners();
  }

  Account _brokerageAccount() => accounts().firstWhere(
    (account) => account.id == brokerageAccountId,
    orElse: () => throw StateError('Choose a brokerage account.'),
  );

  Account? _counterpartyAccount() {
    final id = counterpartyAccountId;
    if (id == null) return null;
    for (final account in accounts()) {
      if (account.id == id) return account;
    }
    return null;
  }

  static BrokerageStatementMapping _initialMapping(CsvParsedSource source) {
    if (source.headers.length < 4) {
      throw const TransactionImportException(
        'A brokerage CSV needs at least four columns.',
      );
    }
    return const BrokerageStatementMapping(
      dateColumn: 0,
      activityColumn: 1,
      instrumentColumn: 2,
      grossAmountColumn: 3,
    );
  }
}
