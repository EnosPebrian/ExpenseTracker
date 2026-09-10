import '../../../assets/domain/entities/asset_definition.dart';
import '../../../assets/domain/services/asset_definition_integrity_policy.dart';
import '../../../assets/domain/services/asset_trade_validator.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../transactions/domain/entities/internal_transfer_link.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../../transactions/domain/services/transaction_duplicate_detector.dart';
import '../../../transactions/domain/usecases/transaction_usecases.dart';
import 'brokerage_import_identity.dart';
import 'brokerage_import_models.dart';
import 'brokerage_import_posting.dart';

class BrokerageImportCommitService {
  const BrokerageImportCommitService({
    required this.repository,
    this.definitionIntegrity = const AssetDefinitionIntegrityPolicy(),
    this.tradeValidator = const AssetTradeValidator(),
    this.duplicateDetector = const TransactionDuplicateDetector(),
  });

  final InvestmentImportAtomicRepository repository;
  final AssetDefinitionIntegrityPolicy definitionIntegrity;
  final AssetTradeValidator tradeValidator;
  final TransactionDuplicateDetector duplicateDetector;

  Future<BrokerageImportResult> commit({
    required BrokerageImportPreview preview,
    required String bookId,
    required String? memberId,
    required Account brokerageAccount,
    required Account? counterpartyAccount,
    required Iterable<AssetDefinition> existingInstruments,
    required Iterable<Transaction> existingTransactions,
  }) async {
    if (brokerageAccount.bookId != bookId ||
        brokerageAccount.deletedAt != null ||
        brokerageAccount.accountType != AccountType.brokerage) {
      throw StateError('Choose an active brokerage account in this household.');
    }
    final included =
        preview.drafts.where((draft) => draft.included).toList(growable: false)
          ..sort((left, right) {
            final byDate = left.date.compareTo(right.date);
            return byDate != 0
                ? byDate
                : left.sourceRowNumber.compareTo(right.sourceRowNumber);
          });
    if (included.isEmpty) {
      throw StateError('Select at least one new statement activity.');
    }
    if (included.any((draft) => !draft.canCommit)) {
      throw StateError('Resolve every included statement row before import.');
    }
    for (final draft in included) {
      final expectedEventId = BrokerageImportIdentity.event(
        bookId: bookId,
        brokerageAccountId: brokerageAccount.id,
        sourceFingerprint: preview.source.fileFingerprint,
        sourceRowIdentity: draft.sourceRowIdentity,
        sourceRowFingerprint: draft.sourceRowFingerprint,
      );
      if (draft.eventId != expectedEventId) {
        throw StateError(
          'The brokerage account changed. Analyze the statement again.',
        );
      }
    }
    final existingDefinitions = existingInstruments.toList(growable: false);
    final creationsById = <String, AssetDefinition>{};
    for (final draft in included) {
      if (draft.instrumentResolution != BrokerageInstrumentResolution.create) {
        continue;
      }
      final definition = draft.plannedInstrument;
      if (definition == null || definition.id != draft.instrumentId) {
        throw StateError('The planned instrument is incomplete.');
      }
      creationsById[definition.id] = definition;
    }
    final creations = creationsById.values.toList(growable: false);
    final definitionsForCommit = [...existingDefinitions, ...creations];
    for (final definition in creations) {
      final validation = definitionIntegrity.validate(
        candidate: definition,
        existingDefinitions: [
          ...existingDefinitions,
          ...creations.where((item) => item.id != definition.id),
        ],
      );
      if (!validation.isValid) {
        throw StateError(
          validation.firstIssue?.message ??
              'The planned instrument is no longer valid.',
        );
      }
    }

    final transactions = <Transaction>[];
    final transferLinks = <InternalTransferLink>[];
    final seenTransactionIds = <String>{};
    final seenLinkIds = <String>{};
    final existing = existingTransactions.toList(growable: false);
    final sequence = existing.toList(growable: true);
    for (final draft in included) {
      final instrument = draft.instrumentId == null
          ? null
          : definitionsForCommit.cast<AssetDefinition?>().firstWhere(
              (candidate) => candidate?.id == draft.instrumentId,
              orElse: () => null,
            );
      final posting = BrokerageImportPosting.materialize(
        draft: draft,
        bookId: bookId,
        memberId: memberId,
        brokerageAccount: brokerageAccount,
        counterpartyAccount: counterpartyAccount,
        instrument: instrument,
      );
      final primary = posting.transactions.firstWhere(
        (transaction) => transaction.brokerageAccountId != null,
        orElse: () => posting.transactions.first,
      );
      final currentDuplicate = duplicateDetector.classify(
        primary.toRecord(),
        existing.map((transaction) => transaction.toRecord()),
      );
      if (currentDuplicate.classification ==
              TransactionCandidateClassification.exactIdentity ||
          (draft.classification == BrokerageImportClassification.newRecord &&
              currentDuplicate.classification !=
                  TransactionCandidateClassification.newRecord) ||
          (draft.matchedTransactionId != null &&
              currentDuplicate.existingId != draft.matchedTransactionId)) {
        throw StateError('Local data changed. Review the statement again.');
      }
      for (final transaction in posting.transactions) {
        if (!seenTransactionIds.add(transaction.id)) {
          throw StateError('The import contains duplicate stable identities.');
        }
        validateTransaction(transaction);
        if (transaction.type == TransactionType.assetConversion) {
          final validation = tradeValidator.validateCandidate(
            existingTransactions: sequence,
            candidate: transaction,
            definition: instrument,
            replacedTransactionId: null,
          );
          if (!validation.isValid) {
            throw TransactionValidationException(
              validation.message ?? 'The asset sequence is invalid.',
            );
          }
        }
        transactions.add(transaction);
        sequence.add(transaction);
      }
      final link = posting.transferLink;
      if (link != null) {
        if (!seenLinkIds.add(link.id)) {
          throw StateError(
            'The import contains duplicate transfer identities.',
          );
        }
        transferLinks.add(link);
      }
    }

    await repository.saveInvestmentImportAtomic(
      transactions: transactions,
      assetDefinitionCreations: creations,
      transferLinks: transferLinks,
    );
    return BrokerageImportResult(
      importedEventIds: included.map((draft) => draft.eventId).toList(),
      transactionsCreated: transactions.length,
      instrumentsCreated: creations.length,
      alreadyImported: preview.count(
        BrokerageImportClassification.alreadyImported,
      ),
      excluded: preview.drafts.length - included.length,
      completedAt: DateTime.now(),
    );
  }
}
