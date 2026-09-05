import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../master_data/domain/entities/account.dart';
import '../../data/csv_transaction_source_parser.dart';
import '../../data/local_import_review_repository.dart';
import '../../domain/entities/import_review_draft.dart';
import '../../domain/entities/import_review_session.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/transaction_import_rule.dart';
import '../../domain/entities/internal_transfer_link.dart';
import '../../domain/import/transaction_import_models.dart';
import '../../domain/import/transaction_import_identity.dart';
import '../../domain/import/transaction_import_planner.dart';
import '../../domain/services/transaction_import_rule_engine.dart';
import '../../domain/services/transaction_duplicate_detector.dart';
import '../../domain/services/internal_transfer_matcher.dart';
import '../../domain/usecases/internal_transfer_usecases.dart';
import '../../domain/usecases/transaction_usecases.dart';

class TransactionImportController extends ChangeNotifier {
  TransactionImportController({
    required this.pickFile,
    required this.importBatch,
    required this.existingTransactions,
    required this.accounts,
    required this.expenseCategories,
    required this.incomeCategories,
    required this.activeBookId,
    required this.activeMemberId,
    this.refreshBeforeAnalysis,
    this.afterImport,
    this.importRules,
    this.ruleCategories,
    this.saveImportRule,
    this.internalTransfers,
    this.existingTransferLinks,
    this.importReviewRepository,
    this.hasUnresolvedSyncConflict,
    this.parser = const CsvTransactionSourceParser(),
    this.planner = const TransactionImportPlanner(),
  });

  final Future<SelectedCsvFile?> Function() pickFile;
  final ImportTransactionsBatch importBatch;
  final Future<List<Transaction>> Function() existingTransactions;
  final List<Account> accounts;
  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final String activeBookId;
  final String? activeMemberId;
  final Future<bool> Function()? refreshBeforeAnalysis;
  final Future<void> Function()? afterImport;
  final Future<List<TransactionImportRule>> Function()? importRules;
  final Future<Map<String, ImportRuleCategory>> Function()? ruleCategories;
  final Future<TransactionImportRule> Function(TransactionImportRule)?
  saveImportRule;
  final InternalTransferService? internalTransfers;
  final Future<List<InternalTransferLink>> Function()? existingTransferLinks;
  final LocalImportReviewRepository? importReviewRepository;
  final Future<bool> Function()? hasUnresolvedSyncConflict;
  final CsvTransactionSourceParser parser;
  final TransactionImportPlanner planner;

  bool busy = false;
  String? error;
  SelectedCsvFile? selectedFile;
  CsvParsedSource? source;
  TransactionImportMapping? mapping;
  Account? destinationAccount;
  TransactionImportPreview? preview;
  TransactionImportResult? result;
  final Set<String> selectedDraftIds = {};
  final Map<String, InternalTransferMatch> transferMatches = {};
  final Map<String, String> confirmedTransferCounterparts = {};
  String reviewQuery = '';
  TransactionImportClassification? reviewFilter;
  List<Transaction> _existingAtAnalysis = const [];
  List<TransactionImportRule> _rulesAtAnalysis = const [];
  Map<String, ImportRuleCategory> _ruleCategoriesAtAnalysis = const {};
  ImportReviewBundle? reviewBundle;
  final Map<String, Set<String>> _editedFields = {};
  final Map<String, String> _persistedCategoryIds = {};
  Timer? _saveDebounce;
  bool saved = false;
  ImportReviewSourceType reviewSourceType = ImportReviewSourceType.csv;
  String? reviewTitle;
  Map<String, Object?> reviewSummary = const {};

  Map<String, ImportRuleCategory> get availableRuleCategories =>
      Map.unmodifiable(_ruleCategoriesAtAnalysis);

  String? ruleName(String? id) {
    if (id == null) return null;
    for (final rule in _rulesAtAnalysis) {
      if (rule.id == id) return rule.name;
    }
    return null;
  }

  String ruleMatchSummary(String id) {
    for (final rule in _rulesAtAnalysis) {
      if (rule.id != id) continue;
      final category = _ruleCategoriesAtAnalysis[rule.categoryId];
      return '${rule.name} → ${category?.name ?? 'Category unavailable'}';
    }
    return 'Unavailable rule';
  }

  Future<void> createImportRule(TransactionImportRule rule) async {
    final save = saveImportRule;
    if (save == null) {
      throw StateError('Import-rule persistence is unavailable.');
    }
    final saved = await save(rule);
    _rulesAtAnalysis = [
      ..._rulesAtAnalysis.where((item) => item.id != saved.id),
      saved,
    ];
    notifyListeners();
  }

  List<TransactionImportDraft> get visibleDrafts {
    final drafts = preview?.drafts ?? const <TransactionImportDraft>[];
    final query = reviewQuery.trim().toLowerCase();
    return drafts.where((draft) {
      if (reviewFilter != null && draft.classification != reviewFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return '${draft.sourceRowNumber} ${draft.description} ${draft.category} '
              '${draft.reference} ${draft.note}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  Future<void> selectCsv({
    CsvHeaderMode headerMode = CsvHeaderMode.firstRowHeaders,
  }) async {
    await _run(() async {
      final file = await pickFile();
      if (file == null) return;
      selectedFile = file;
      source = await parser.parse(file, headerMode: headerMode);
      mapping = _initialMapping(source!);
      preview = null;
      result = null;
    });
  }

  Future<void> changeHeaderMode(CsvHeaderMode mode) async {
    final file = selectedFile;
    if (file == null) return;
    await _run(() async {
      source = await parser.parse(file, headerMode: mode);
      mapping = _initialMapping(source!);
      preview = null;
    });
  }

  void loadPreparedSource(CsvParsedSource value) {
    selectedFile = null;
    source = value;
    mapping = canonicalMappingFor(value.headers);
    preview = null;
    result = null;
    error = null;
    notifyListeners();
  }

  void selectAccount(Account? account) {
    destinationAccount = account;
    preview = null;
    notifyListeners();
  }

  void setMapping(TransactionImportMapping value) {
    mapping = value;
    preview = null;
    notifyListeners();
  }

  Future<void> analyze() async {
    final currentSource = source;
    final currentMapping = mapping;
    final account = destinationAccount;
    if (currentSource == null || currentMapping == null || account == null) {
      error = account == null
          ? 'Select destination account before importing.'
          : 'Select a source and complete the mapping.';
      notifyListeners();
      return;
    }
    if (reviewBundle case final bundle?) {
      await loadSavedReview(
        ImportReviewBundle(
          session: bundle.session.copyWith(destinationAccountId: account.id),
          drafts: bundle.drafts,
        ),
      );
      return;
    }
    await _run(() async {
      final freshness = await refreshBeforeAnalysis?.call() ?? true;
      _existingAtAnalysis = await existingTransactions();
      _rulesAtAnalysis = await importRules?.call() ?? const [];
      _ruleCategoriesAtAnalysis = await ruleCategories?.call() ?? const {};
      preview = await planner.build(
        source: currentSource,
        mapping: currentMapping,
        account: account,
        activeBookId: activeBookId,
        existingTransactions: _existingAtAnalysis,
        expenseCategories: expenseCategories,
        incomeCategories: incomeCategories,
        importRules: _rulesAtAnalysis,
        ruleCategories: _ruleCategoriesAtAnalysis,
        activeAccountIds: accounts
            .where((item) => item.deletedAt == null)
            .map((item) => item.id)
            .toSet(),
        remoteFreshnessVerified: freshness,
      );
      await _analyzeTransferMatches();
      selectedDraftIds.clear();
    });
  }

  void toggleIncluded(String id, bool included) {
    if (!included) {
      transferMatches.remove(id);
      confirmedTransferCounterparts.remove(id);
    }
    _replaceDraft(id, (draft) {
      if (!draft.canChangeInclusion) return draft;
      return draft.copyWith(included: included);
    });
    _editedFields.putIfAbsent(id, () => {}).add('included');
    _scheduleAutoSave();
  }

  InternalTransferMatch? transferMatchFor(String draftId) =>
      transferMatches[draftId];

  bool isTransferConfirmed(String draftId) =>
      confirmedTransferCounterparts.containsKey(draftId);

  void keepAsTransaction(String draftId) {
    confirmedTransferCounterparts.remove(draftId);
    transferMatches.remove(draftId);
    notifyListeners();
  }

  bool confirmTransfer(String draftId, {String? counterpartId}) {
    final match = transferMatches[draftId];
    if (match == null) return false;
    final selectedId = counterpartId ?? match.counterpart?.id;
    if (selectedId == null ||
        !match.options.any((item) => item.counterpart.id == selectedId) ||
        confirmedTransferCounterparts.values.contains(selectedId)) {
      return false;
    }
    confirmedTransferCounterparts[draftId] = selectedId;
    notifyListeners();
    return true;
  }

  void includeAllSafeNew() => _replaceAllDrafts(
    (draft) => draft.classification == TransactionImportClassification.newRecord
        ? draft.copyWith(included: true)
        : draft,
  );

  void excludeAll() =>
      _replaceAllDrafts((draft) => draft.copyWith(included: false));

  void excludeAllDuplicates() => _replaceAllDrafts((draft) {
    final duplicate =
        draft.classification ==
            TransactionImportClassification.semanticDuplicate ||
        draft.classification ==
            TransactionImportClassification.possibleDuplicate;
    return duplicate ? draft.copyWith(included: false) : draft;
  });

  void setReviewQuery(String value) {
    reviewQuery = value;
    notifyListeners();
  }

  void setReviewFilter(TransactionImportClassification? value) {
    reviewFilter = value;
    notifyListeners();
  }

  void toggleSelected(String id, bool selected) {
    selected ? selectedDraftIds.add(id) : selectedDraftIds.remove(id);
    notifyListeners();
  }

  void editDraft(
    String id, {
    DateTime? date,
    String? description,
    int? amount,
    TransactionType? type,
    String? category,
    String? reference,
    String? note,
    bool persist = true,
  }) {
    transferMatches.remove(id);
    confirmedTransferCounterparts.remove(id);
    _replaceDraft(id, (draft) {
      final editedDate = date ?? draft.date;
      final editedDescription = (description ?? draft.description).trim();
      final editedAmount = amount ?? draft.amount;
      final editedType = type ?? draft.type;
      var editedCategory = category ?? draft.category;
      var categorySource = category == null
          ? draft.categorySource
          : category.trim().isEmpty
          ? TransactionImportCategorySource.unresolved
          : TransactionImportCategorySource.manual;
      final issues = <TransactionImportIssue>[];
      if (editedDescription.isEmpty) {
        issues.add(
          const TransactionImportIssue(
            'Description is required.',
            blocking: true,
          ),
        );
      }
      if (editedAmount <= 0) {
        issues.add(
          const TransactionImportIssue(
            'Amount must be greater than zero.',
            blocking: true,
          ),
        );
      }
      final compatibleCategories = editedType == TransactionType.income
          ? incomeCategories
          : expenseCategories;
      if (editedCategory.isNotEmpty &&
          !compatibleCategories.contains(editedCategory)) {
        final protectedPersistedCategory =
            category == null &&
            (categorySource == TransactionImportCategorySource.manual ||
                categorySource == TransactionImportCategorySource.source);
        if (protectedPersistedCategory) {
          issues.add(
            const TransactionImportIssue(
              'Category unavailable. Select a current category before importing.',
              blocking: true,
            ),
          );
        } else {
          editedCategory = '';
          categorySource = TransactionImportCategorySource.unresolved;
          issues.add(
            const TransactionImportIssue(
              'Category was cleared because it does not match the transaction type.',
            ),
          );
        }
      }
      var matchedRuleIds = draft.matchedRuleIds;
      var winningRuleId = draft.winningRuleId;
      var ruleAmbiguous = draft.ruleAmbiguous;
      if ((category == null || category.trim().isEmpty) &&
          (categorySource == TransactionImportCategorySource.unresolved ||
              categorySource == TransactionImportCategorySource.rule) &&
          !issues.any((issue) => issue.blocking)) {
        final match = const TransactionImportRuleEngine().evaluate(
          input: TransactionImportRuleInput(
            bookId: activeBookId,
            type: editedType,
            accountId: destinationAccount?.id ?? '',
            description: editedDescription,
            reference: reference ?? draft.reference,
            merchantHint: draft.merchantHint,
          ),
          rules: _rulesAtAnalysis,
          categories: _ruleCategoriesAtAnalysis,
          activeAccountIds: accounts
              .where((item) => item.deletedAt == null)
              .map((item) => item.id)
              .toSet(),
        );
        matchedRuleIds = match.matchedRuleIds;
        winningRuleId = match.winningRuleId;
        ruleAmbiguous = match.ambiguous;
        if (match.hasSuggestion) {
          editedCategory = match.categoryName!;
          categorySource = TransactionImportCategorySource.rule;
        } else if (categorySource == TransactionImportCategorySource.rule) {
          editedCategory = '';
          categorySource = TransactionImportCategorySource.unresolved;
        }
        issues.addAll(match.warnings.map(TransactionImportIssue.new));
      }

      var classification = issues.any((issue) => issue.blocking)
          ? TransactionImportClassification.invalid
          : TransactionImportClassification.newRecord;
      String? matchedId;
      if (classification != TransactionImportClassification.invalid) {
        final candidate = Transaction(
          id: draft.transactionId,
          bookId: activeBookId,
          title: editedDescription,
          category: editedCategory,
          account: destinationAccount?.name ?? '',
          date: editedDate,
          amount: editedAmount,
          type: editedType,
        ).toRecord();
        final match = planner.duplicateDetector.classify(
          candidate,
          _existingAtAnalysis.map((transaction) => transaction.toRecord()),
        );
        matchedId = match.existingId;
        classification = switch (match.classification) {
          TransactionCandidateClassification.exactIdentity =>
            TransactionImportClassification.alreadyImported,
          TransactionCandidateClassification.semanticDuplicate =>
            TransactionImportClassification.semanticDuplicate,
          TransactionCandidateClassification.possibleDuplicate =>
            TransactionImportClassification.possibleDuplicate,
          TransactionCandidateClassification.newRecord =>
            TransactionImportClassification.newRecord,
        };
      }
      final wasNew =
          draft.classification == TransactionImportClassification.newRecord;
      final included = switch (classification) {
        TransactionImportClassification.newRecord =>
          wasNew ? draft.included : true,
        _ => false,
      };
      return TransactionImportDraft(
        sourceRowNumber: draft.sourceRowNumber,
        sourceRowIdentity: draft.sourceRowIdentity,
        sourceRowFingerprint: draft.sourceRowFingerprint,
        transactionId: draft.transactionId,
        date: editedDate,
        description: editedDescription,
        amount: editedAmount,
        type: editedType,
        category: editedCategory,
        reference: reference ?? draft.reference,
        note: note ?? draft.note,
        classification: classification,
        included: included,
        issues: issues,
        matchedTransactionId: matchedId,
        categorySource: categorySource,
        matchedRuleIds: matchedRuleIds,
        winningRuleId: winningRuleId,
        ruleAmbiguous: ruleAmbiguous,
        merchantHint: draft.merchantHint,
      );
    });
    final fields = _editedFields.putIfAbsent(id, () => {});
    if (date != null) fields.add('date');
    if (description != null) fields.add('description');
    if (amount != null) fields.add('amount');
    if (type != null) fields.add('type');
    if (category != null) fields.add('category');
    if (reference != null) fields.add('reference');
    if (note != null) fields.add('note');
    if (category != null) _persistedCategoryIds.remove(id);
    if (persist) _scheduleAutoSave();
  }

  bool bulkAssignCategory(String category) {
    final current = preview;
    if (current == null || selectedDraftIds.isEmpty) return false;
    final selected = current.drafts
        .where((draft) => selectedDraftIds.contains(draft.transactionId))
        .toList();
    final types = selected.map((draft) => draft.type).toSet();
    if (types.length != 1) return false;
    final compatible = types.single == TransactionType.income
        ? incomeCategories
        : expenseCategories;
    if (!compatible.any((value) => value == category)) return false;
    for (final draft in selected) {
      _replaceDraft(
        draft.transactionId,
        (item) => item.copyWith(
          category: category,
          categorySource: TransactionImportCategorySource.manual,
        ),
        notify: false,
      );
      _editedFields.putIfAbsent(draft.transactionId, () => {}).add('category');
    }
    _scheduleAutoSave();
    notifyListeners();
    return true;
  }

  Future<void> commit() async {
    final current = preview;
    final account = destinationAccount;
    if (current == null || account == null) {
      error = 'Select destination account before importing.';
      notifyListeners();
      return;
    }
    await _run(() async {
      if (await hasUnresolvedSyncConflict?.call() ?? false) {
        throw const TransactionImportException(
          'Resolve pending shared-data conflicts before committing this import.',
        );
      }
      if (reviewBundle case final bundle?) {
        final refreshed = await importReviewRepository?.load(bundle.session.id);
        if (refreshed == null ||
            refreshed.session.version != bundle.session.version) {
          throw const TransactionImportException(
            'This pending import changed on another device. Refresh and review it again.',
          );
        }
        await _saveForLaterCore();
        final latest = reviewBundle!;
        final committedIds = current.drafts
            .where((draft) => draft.canImport)
            .map((draft) => draft.transactionId)
            .toSet();
        final finalizedDrafts = latest.drafts.where(
          (draft) => committedIds.contains(draft.deterministicTransactionId),
        );
        if (finalizedDrafts.length != committedIds.length ||
            finalizedDrafts.any(
              (draft) =>
                  draft.deterministicTransactionId == null ||
                  draft.deterministicTransactionAccountId != account.id,
            )) {
          throw const TransactionImportException(
            'Select destination account before importing.',
          );
        }
        reviewBundle = ImportReviewBundle(
          session: latest.session.transition(
            ImportReviewSessionState.readyToCommit,
          ),
          drafts: latest.drafts,
        );
        await _persistCurrentReview();
      }
      final drafts = current.drafts.where((draft) => draft.canImport).toList();
      final transactions = drafts
          .map(
            (draft) => Transaction(
              id: draft.transactionId,
              bookId: activeBookId,
              enteredByMemberId: activeMemberId,
              title: draft.description,
              category: draft.category,
              categoryId: _persistedCategoryIds[draft.transactionId],
              account: account.name,
              date: draft.date,
              amount: draft.amount,
              type: draft.type,
            ),
          )
          .toList();
      final byId = {for (final item in transactions) item.id: item};
      final convertedIds = <String>[];
      final convertedDisplayIds = <String>[];
      final usedIds = <String>{};
      final transferService = internalTransfers;
      for (final entry in confirmedTransferCounterparts.entries) {
        final draft = byId[entry.key];
        final match = transferMatches[entry.key];
        final option = match?.options
            .where((item) => item.counterpart.id == entry.value)
            .firstOrNull;
        if (draft == null || option == null || transferService == null) {
          throw const TransactionImportException(
            'This transfer candidate changed. Review again.',
          );
        }
        if (!usedIds.add(draft.id) || !usedIds.add(option.counterpart.id)) {
          throw const TransactionImportException(
            'A transaction can belong to only one confirmed transfer.',
          );
        }
        final converted = await transferService.convertDraftExisting(
          draft: draft,
          existingTransactionId: option.counterpart.id,
          expectedExistingVersion: option.counterpart.version,
          draftAccountId: destinationAccount!.id,
          existingAccountId: option.counterpart.accountId,
        );
        convertedIds.add(draft.id);
        convertedDisplayIds.add(converted.outgoing.id);
      }
      final ordinary = transactions
          .where((item) => !convertedIds.contains(item.id))
          .toList();
      final saved = await importBatch(ordinary);
      await afterImport?.call();
      result = TransactionImportResult(
        importedIds: [...saved.map((item) => item.id), ...convertedIds],
        viewTransactionIds: [
          ...saved.map((item) => item.id),
          ...convertedDisplayIds,
        ],
        convertedInternalTransfers: convertedIds.length,
        alreadyImported: current.count(
          TransactionImportClassification.alreadyImported,
        ),
        skippedDuplicates: current.drafts
            .where(
              (draft) =>
                  !draft.included &&
                  (draft.classification ==
                          TransactionImportClassification.semanticDuplicate ||
                      draft.classification ==
                          TransactionImportClassification.possibleDuplicate ||
                      draft.classification ==
                          TransactionImportClassification
                              .possiblePreviouslyDeleted),
            )
            .length,
        excluded: current.excludedCount,
        incomeTotal: ordinary
            .where((item) => item.type == TransactionType.income)
            .fold(0, (sum, item) => sum + item.amount),
        expenseTotal: ordinary
            .where((item) => item.type == TransactionType.expense)
            .fold(0, (sum, item) => sum + item.amount),
        completedAt: DateTime.now(),
      );
      if (reviewBundle case final bundle?) {
        reviewBundle = ImportReviewBundle(
          session: bundle.session.transition(
            ImportReviewSessionState.completed,
            at: result!.completedAt,
          ),
          drafts: bundle.drafts,
        );
        await _persistCurrentReview();
      }
    });
  }

  Future<ImportReviewSession?> saveForLater({
    ImportReviewSourceType? sourceType,
    String? title,
    Map<String, Object?> summary = const {},
  }) async {
    if (preview == null || source == null || importReviewRepository == null) {
      error = 'Analyze the import before saving it for later.';
      notifyListeners();
      return null;
    }
    await _run(
      () => _saveForLaterCore(
        sourceType: sourceType ?? reviewSourceType,
        title: title ?? reviewTitle,
        summary: summary.isEmpty ? reviewSummary : summary,
      ),
    );
    return reviewBundle?.session;
  }

  Future<void> _saveForLaterCore({
    ImportReviewSourceType sourceType = ImportReviewSourceType.csv,
    String? title,
    Map<String, Object?> summary = const {},
  }) async {
    final current = preview!;
    final currentSource = source!;
    final existingDrafts = {
      for (final draft in reviewBundle?.drafts ?? const <ImportReviewDraft>[])
        '${draft.sourceIndex}|${draft.sourceRowIdentity}': draft,
    };
    final now = DateTime.now();
    final previousSession = reviewBundle?.session;
    final persistedSummary = <String, Object?>{
      ...summary,
      'row_count': current.drafts.length,
      'included_count': current.drafts.where((draft) => draft.included).length,
      'warning_count': current.drafts
          .where(
            (draft) =>
                draft.issues.isNotEmpty ||
                draft.classification !=
                    TransactionImportClassification.newRecord,
          )
          .length,
      'transfer_candidate_count': transferMatches.length,
    };
    final session =
        previousSession ??
        ImportReviewSession(
          bookId: activeBookId,
          sourceType: sourceType,
          title: title ?? currentSource.fileName,
          sourceFingerprint: currentSource.fileFingerprint,
          destinationAccountId: destinationAccount?.id,
          createdByMemberId: activeMemberId,
          summary: persistedSummary,
        );
    String? categoryId(TransactionImportDraft draft) {
      final persistedId = _persistedCategoryIds[draft.transactionId];
      if (persistedId != null &&
          !(_editedFields[draft.transactionId]?.contains('category') ??
              false)) {
        return persistedId;
      }
      final matches = _ruleCategoriesAtAnalysis.values.where(
        (category) =>
            category.available &&
            category.name == draft.category &&
            category.type == draft.type,
      );
      return matches.isEmpty ? null : matches.first.id;
    }

    final drafts = current.drafts.map((draft) {
      final existing =
          existingDrafts['${draft.sourceRowNumber}|${draft.sourceRowFingerprint}'];
      final preserveExcludedUnresolved =
          existing != null &&
          !draft.included &&
          existing.deterministicTransactionId == null;
      return ImportReviewDraft(
        id: existing?.id,
        sessionId: session.id,
        bookId: activeBookId,
        sourceRowIdentity: draft.sourceRowFingerprint,
        sourceRowKey:
            draft.sourceRowIdentity ?? draft.sourceRowNumber.toString(),
        deterministicTransactionId: preserveExcludedUnresolved
            ? null
            : draft.transactionId,
        deterministicTransactionAccountId: preserveExcludedUnresolved
            ? null
            : destinationAccount?.id,
        sourceIndex: draft.sourceRowNumber,
        transactionDate: draft.date,
        description: draft.description,
        amountMinor: draft.amount,
        currencyCode: destinationAccount?.currencyCode ?? 'IDR',
        transactionType: draft.type,
        categoryName: draft.category,
        categoryId: categoryId(draft),
        categoryProvenance: draft.categorySource,
        referenceText: draft.reference,
        noteText: draft.note,
        merchantHint: draft.merchantHint,
        included: draft.included,
        userEditedFields:
            _editedFields[draft.transactionId] ??
            existing?.userEditedFields ??
            const {},
        warnings: draft.issues.map((issue) => issue.message).toList(),
        createdAt: existing?.createdAt,
        updatedAt: now,
        version: existing == null ? 1 : existing.version + 1,
        deviceId: existing?.deviceId ?? 'local-device',
        syncStatus: existing == null ? 'local_only' : 'pending',
      );
    }).toList();
    final updatedSession = previousSession == null
        ? session
        : session.copyWith(
            title: title,
            destinationAccountId: destinationAccount?.id,
            summary: {...session.summary, ...persistedSummary},
            updatedAt: now,
            version: session.version + 1,
            syncStatus: 'pending',
          );
    reviewBundle = ImportReviewBundle(session: updatedSession, drafts: drafts);
    _persistedCategoryIds
      ..clear()
      ..addEntries(
        drafts
            .where(
              (draft) =>
                  draft.categoryId != null &&
                  draft.deterministicTransactionId != null,
            )
            .map(
              (draft) => MapEntry(
                draft.deterministicTransactionId!,
                draft.categoryId!,
              ),
            ),
      );
    await importReviewRepository!.save(reviewBundle!);
    saved = true;
  }

  Future<void> loadSavedReview(ImportReviewBundle bundle) async {
    final account = accounts
        .where((item) => item.id == bundle.session.destinationAccountId)
        .firstOrNull;
    destinationAccount = account;
    reviewBundle = bundle;
    _editedFields
      ..clear()
      ..addEntries(
        bundle.drafts
            .where((draft) => draft.deterministicTransactionId != null)
            .map(
              (draft) => MapEntry(
                draft.deterministicTransactionId!,
                Set<String>.of(draft.userEditedFields),
              ),
            ),
      );
    _persistedCategoryIds
      ..clear()
      ..addEntries(
        bundle.drafts
            .where(
              (draft) =>
                  draft.categoryId != null &&
                  draft.deterministicTransactionId != null,
            )
            .map(
              (draft) => MapEntry(
                draft.deterministicTransactionId!,
                draft.categoryId!,
              ),
            ),
      );
    source = CsvParsedSource(
      fileName: bundle.session.title,
      fileFingerprint: bundle.session.sourceFingerprint,
      delimiter: ',',
      headers: const [
        'Date',
        'Description',
        'Amount',
        'Type',
        'Category',
        'Reference',
        'Note',
      ],
      rows: bundle.drafts
          .where((draft) => draft.deletedAt == null)
          .map(
            (draft) => CsvSourceRow(
              rowNumber: draft.sourceIndex,
              identityKey: draft.sourceRowKey ?? draft.sourceIndex.toString(),
              merchantHint: draft.merchantHint,
              values: [
                draft.transactionDate.toIso8601String(),
                draft.description,
                draft.amountMinor.toString(),
                draft.transactionType.name,
                draft.categoryName,
                draft.referenceText,
                draft.noteText,
              ],
            ),
          )
          .toList(),
      headerMode: CsvHeaderMode.firstRowHeaders,
    );
    mapping = canonicalMappingFor(source!.headers);
    if (account == null) {
      preview = null;
      error = null;
      saved = true;
      notifyListeners();
      return;
    }
    await _run(() async {
      final freshness = await refreshBeforeAnalysis?.call() ?? true;
      _existingAtAnalysis = await existingTransactions();
      _rulesAtAnalysis = await importRules?.call() ?? const [];
      _ruleCategoriesAtAnalysis = await ruleCategories?.call() ?? const {};
      final finalizedIds = <String, String>{};
      for (final draft in bundle.drafts.where(
        (item) => item.deletedAt == null,
      )) {
        final existingId = draft.deterministicTransactionId;
        final existingAccount = draft.deterministicTransactionAccountId;
        if (existingId != null &&
            (existingAccount == null || existingAccount == account.id)) {
          finalizedIds[draft.id] = existingId;
          continue;
        }
        final sourceRowKey = draft.sourceRowKey;
        if (sourceRowKey == null) {
          throw const TransactionImportException(
            'This legacy pending import cannot change accounts because its original source-row key is unavailable.',
          );
        }
        finalizedIds[draft.id] = TransactionImportIdentity.derive(
          bookId: activeBookId,
          accountId: account.id,
          sourceFingerprint: bundle.session.sourceFingerprint,
          sourceRowIdentity: sourceRowKey,
          sourceRowFingerprint: draft.sourceRowIdentity,
        );
      }
      preview = TransactionImportPreview(
        source: source!,
        remoteFreshnessVerified: freshness,
        drafts: bundle.drafts
            .where((draft) => draft.deletedAt == null)
            .map(
              (draft) => TransactionImportDraft(
                sourceRowNumber: draft.sourceIndex,
                sourceRowIdentity:
                    draft.sourceRowKey ?? draft.sourceIndex.toString(),
                sourceRowFingerprint: draft.sourceRowIdentity,
                transactionId: finalizedIds[draft.id]!,
                date: draft.transactionDate,
                description: draft.description,
                amount: draft.amountMinor,
                type: draft.transactionType,
                category: draft.categoryName,
                reference: draft.referenceText,
                note: draft.noteText,
                classification: TransactionImportClassification.newRecord,
                included: draft.included,
                issues: const [],
                categorySource: draft.categoryProvenance,
                merchantHint: draft.merchantHint,
              ),
            )
            .toList(),
      );
      for (final draft in List<TransactionImportDraft>.of(preview!.drafts)) {
        editDraft(draft.transactionId, persist: false);
        _markUnavailablePersistedCategory(draft.transactionId);
        _markIdentityConflict(draft.transactionId);
      }
      await _analyzeTransferMatches();
      final selectedIds = bundle.drafts
          .where(
            (draft) =>
                draft.deletedAt == null &&
                draft.included &&
                finalizedIds[draft.id] != null,
          )
          .map((draft) => finalizedIds[draft.id]!)
          .toSet();
      final selected = preview!.drafts.where(
        (draft) => selectedIds.contains(draft.transactionId),
      );
      reviewBundle = bundle;
      saved = true;
      if (selected.isNotEmpty &&
          selected.every(
            (draft) =>
                draft.classification ==
                TransactionImportClassification.alreadyImported,
          )) {
        reviewBundle = ImportReviewBundle(
          session: bundle.session.transition(
            ImportReviewSessionState.readyToCommit,
          ),
          drafts: bundle.drafts,
        );
        await _persistCurrentReview();
        reviewBundle = ImportReviewBundle(
          session: reviewBundle!.session.transition(
            ImportReviewSessionState.completed,
          ),
          drafts: bundle.drafts,
        );
        await _persistCurrentReview();
      }
    });
  }

  void _markIdentityConflict(String transactionId) {
    final current = preview;
    if (current == null) return;
    final index = current.drafts.indexWhere(
      (draft) => draft.transactionId == transactionId,
    );
    if (index < 0) return;
    final draft = current.drafts[index];
    final matches = _existingAtAnalysis.where(
      (transaction) => transaction.id == transactionId,
    );
    if (matches.isEmpty) return;
    final existing = matches.single;
    final same =
        existing.title == draft.description &&
        existing.category == draft.category &&
        existing.account == destinationAccount?.name &&
        existing.date == draft.date &&
        existing.amount == draft.amount &&
        existing.type == draft.type;
    if (same) return;
    final drafts = List<TransactionImportDraft>.of(current.drafts);
    drafts[index] = draft.copyWith(
      classification: TransactionImportClassification.invalid,
      included: false,
      issues: const [
        TransactionImportIssue(
          'This stable transaction ID already exists with different financial values.',
          blocking: true,
        ),
      ],
    );
    preview = TransactionImportPreview(
      source: current.source,
      drafts: drafts,
      remoteFreshnessVerified: current.remoteFreshnessVerified,
    );
  }

  void _markUnavailablePersistedCategory(String transactionId) {
    final categoryId = _persistedCategoryIds[transactionId];
    final current = preview;
    if (categoryId == null || current == null) return;
    final index = current.drafts.indexWhere(
      (draft) => draft.transactionId == transactionId,
    );
    if (index < 0) return;
    final draft = current.drafts[index];
    final category = _ruleCategoriesAtAnalysis[categoryId];
    if (category != null &&
        category.available &&
        category.bookId == activeBookId &&
        category.type == draft.type &&
        category.name == draft.category) {
      return;
    }
    final drafts = List<TransactionImportDraft>.of(current.drafts);
    drafts[index] = draft.copyWith(
      classification: TransactionImportClassification.invalid,
      included: false,
      issues: [
        ...draft.issues.where(
          (issue) => !issue.message.startsWith('Category unavailable.'),
        ),
        const TransactionImportIssue(
          'Category unavailable. Select a current category before importing.',
          blocking: true,
        ),
      ],
    );
    preview = TransactionImportPreview(
      source: current.source,
      drafts: drafts,
      remoteFreshnessVerified: current.remoteFreshnessVerified,
    );
  }

  Future<void> discardSavedReview() async {
    final bundle = reviewBundle;
    if (bundle == null) return;
    await importReviewRepository?.discard(bundle.session.id);
    reviewBundle = ImportReviewBundle(
      session: bundle.session.transition(ImportReviewSessionState.discarded),
      drafts: bundle.drafts,
    );
    notifyListeners();
  }

  void _scheduleAutoSave() {
    if (reviewBundle == null) return;
    saved = false;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 650), () {
      saveForLater();
    });
  }

  Future<void> _persistCurrentReview() async {
    final bundle = reviewBundle;
    if (bundle == null) return;
    await importReviewRepository?.save(bundle);
    saved = true;
  }

  void reset() {
    selectedFile = null;
    source = null;
    mapping = null;
    destinationAccount = null;
    preview = null;
    result = null;
    selectedDraftIds.clear();
    transferMatches.clear();
    confirmedTransferCounterparts.clear();
    reviewQuery = '';
    reviewFilter = null;
    error = null;
    reviewBundle = null;
    _editedFields.clear();
    _persistedCategoryIds.clear();
    saved = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _analyzeTransferMatches() async {
    transferMatches.clear();
    confirmedTransferCounterparts.clear();
    final current = preview;
    final account = destinationAccount;
    if (current == null || account == null) return;
    final links = await existingTransferLinks?.call() ?? const [];
    final paired = {
      for (final link in links.where((item) => item.isActive))
        ...link.transactionIds,
    };
    final accountByName = {
      for (final item in accounts.where((item) => item.deletedAt == null))
        item.name.trim().toLowerCase(): item,
    };
    final counterparts = <InternalTransferCandidate>[];
    for (final transaction in _existingAtAnalysis) {
      final existingAccount =
          accountByName[transaction.account.trim().toLowerCase()];
      if (existingAccount == null) continue;
      counterparts.add(
        InternalTransferCandidate(
          id: transaction.id,
          bookId: transaction.bookId ?? '',
          accountId: existingAccount.id,
          accountName: existingAccount.name,
          currencyCode: existingAccount.currencyCode,
          date: transaction.date,
          type: transaction.type,
          amount: transaction.amount,
          description: transaction.title,
          source: InternalTransferCandidateSource.existing,
          version: transaction.version,
          deleted: transaction.deletedAt != null,
          alreadyPaired: paired.contains(transaction.id),
        ),
      );
    }
    final sources = current.drafts
        .where(
          (draft) =>
              draft.classification ==
                  TransactionImportClassification.newRecord &&
              draft.included,
        )
        .map(
          (draft) => InternalTransferCandidate(
            id: draft.transactionId,
            bookId: activeBookId,
            accountId: account.id,
            accountName: account.name,
            currencyCode: account.currencyCode,
            date: draft.date,
            type: draft.type,
            amount: draft.amount,
            description: draft.description,
            reference: draft.reference,
            source: InternalTransferCandidateSource.draft,
          ),
        );
    final matches = const InternalTransferMatcher().matchAll(
      sources: sources,
      counterparts: counterparts,
    );
    transferMatches.addAll(
      matches..removeWhere(
        (_, match) =>
            match.classification ==
                InternalTransferMatchClassification.notEligible ||
            match.classification ==
                InternalTransferMatchClassification.alreadyTransfer,
      ),
    );
  }

  TransactionImportMapping _initialMapping(CsvParsedSource parsed) {
    final canonical = canonicalMappingFor(parsed.headers);
    if (canonical != null) return canonical;
    return TransactionImportMapping(
      dateColumn: 0,
      descriptionColumn: parsed.headers.length > 1 ? 1 : 0,
      amountColumn: parsed.headers.length > 2 ? 2 : null,
      amountStrategy: CsvAmountStrategy.signedAmount,
    );
  }

  void _replaceDraft(
    String id,
    TransactionImportDraft Function(TransactionImportDraft) transform, {
    bool notify = true,
  }) {
    final current = preview;
    if (current == null) return;
    final drafts = [...current.drafts];
    final index = drafts.indexWhere((draft) => draft.transactionId == id);
    if (index < 0) return;
    drafts[index] = transform(drafts[index]);
    preview = TransactionImportPreview(
      source: current.source,
      drafts: drafts,
      remoteFreshnessVerified: current.remoteFreshnessVerified,
    );
    if (notify) notifyListeners();
  }

  void _replaceAllDrafts(
    TransactionImportDraft Function(TransactionImportDraft) transform,
  ) {
    final current = preview;
    if (current == null) return;
    preview = TransactionImportPreview(
      source: current.source,
      drafts: current.drafts.map(transform).toList(),
      remoteFreshnessVerified: current.remoteFreshnessVerified,
    );
    for (final draft in preview!.drafts) {
      _editedFields.putIfAbsent(draft.transactionId, () => {}).add('included');
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on TransactionImportException catch (exception) {
      error = exception.message;
    } catch (exception) {
      error = 'Transaction import could not be completed: $exception';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
