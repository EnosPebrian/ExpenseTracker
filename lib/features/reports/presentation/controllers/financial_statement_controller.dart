import 'package:flutter/foundation.dart';

import '../../../../features/backup/data/portable_file_service.dart';
import '../../../budgets/domain/entities/monthly_category_budget.dart';
import '../../../master_data/domain/entities/account.dart';
import '../../../master_data/domain/entities/financial_book.dart';
import '../../../transactions/domain/entities/internal_transfer_link.dart';
import '../../../transactions/domain/entities/transaction.dart';
import '../../data/financial_statement_pdf_renderer.dart';
import '../../domain/financial_statement.dart';
import '../../domain/financial_statement_generator.dart';

class FinancialStatementController extends ChangeNotifier {
  FinancialStatementController({
    required this.book,
    required List<Account> accounts,
    required List<Transaction> transactions,
    required List<InternalTransferLink> transferLinks,
    required List<MonthlyCategoryBudget> budgets,
    required Map<String, String> categoryNamesById,
    this.localDataWarning = false,
    this.generator = const FinancialStatementGenerator(),
    this.renderer = const FinancialStatementPdfRenderer(),
    this.fileService = const PortableFileService(),
    DateTime? initialPeriod,
  }) : accounts = List.unmodifiable(accounts),
       transactions = List.unmodifiable(transactions),
       transferLinks = List.unmodifiable(transferLinks),
       budgets = List.unmodifiable(budgets),
       categoryNamesById = Map.unmodifiable(categoryNamesById),
       selectedPeriod = initialPeriod ?? DateTime.now() {
    selectedAccountId = this.accounts
        .where((item) => item.deletedAt == null)
        .firstOrNull
        ?.id;
  }

  final FinancialBook book;
  final List<Account> accounts;
  final List<Transaction> transactions;
  final List<InternalTransferLink> transferLinks;
  final List<MonthlyCategoryBudget> budgets;
  final Map<String, String> categoryNamesById;
  final bool localDataWarning;
  final FinancialStatementGenerator generator;
  final FinancialStatementPdfRenderer renderer;
  final PortableFileService fileService;

  FinancialStatementType type = FinancialStatementType.monthly;
  FinancialStatementScope scope = FinancialStatementScope.household;
  DateTime selectedPeriod;
  String? selectedAccountId;
  FinancialStatement? statement;
  PortableSaveResult? lastSave;
  String? error;
  bool generating = false;
  bool exporting = false;

  List<Account> get selectableAccounts => accounts
      .where((account) => account.deletedAt == null)
      .toList(growable: false);

  List<int> get availableYears {
    final years = <int>{DateTime.now().year, selectedPeriod.year};
    years.addAll(transactions.map((transaction) => transaction.date.year));
    final sorted = years.toList()..sort((left, right) => right.compareTo(left));
    return sorted;
  }

  void setType(FinancialStatementType value) {
    type = value;
    _invalidate();
  }

  void setScope(FinancialStatementScope value) {
    scope = value;
    _invalidate();
  }

  void setMonth(int value) {
    selectedPeriod = DateTime(selectedPeriod.year, value);
    _invalidate();
  }

  void setYear(int value) {
    selectedPeriod = DateTime(value, selectedPeriod.month);
    _invalidate();
  }

  void setAccount(String? value) {
    selectedAccountId = value;
    _invalidate();
  }

  void generate() {
    generating = true;
    error = null;
    notifyListeners();
    try {
      statement = generator.generate(
        type: type,
        scope: scope,
        selectedPeriod: selectedPeriod,
        book: book,
        accounts: accounts,
        transactions: transactions,
        transferLinks: transferLinks,
        budgets: budgets,
        categoryNamesById: categoryNamesById,
        accountId: selectedAccountId,
        localDataWarning: localDataWarning,
      );
      lastSave = null;
    } catch (exception) {
      error = exception.toString();
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  Future<void> exportPdf() async {
    final current = statement;
    if (current == null || exporting) return;
    exporting = true;
    error = null;
    notifyListeners();
    try {
      final destination = await fileService.chooseDestination(
        PortableDestinationKind.statement,
      );
      if (destination == null) return;
      final bytes = await renderer.render(current);
      lastSave = await fileService.save(
        kind: PortableDestinationKind.statement,
        destination: destination,
        suggestedName: renderer.suggestedFileName(current),
        bytes: bytes,
        extension: 'pdf',
        dialogTitle: 'Save Pilgrim Tracker statement',
      );
    } catch (exception) {
      error = exception.toString();
    } finally {
      exporting = false;
      notifyListeners();
    }
  }

  void _invalidate() {
    statement = null;
    lastSave = null;
    error = null;
    notifyListeners();
  }
}
