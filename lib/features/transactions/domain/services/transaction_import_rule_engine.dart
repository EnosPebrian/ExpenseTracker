import '../entities/transaction.dart';
import '../entities/transaction_import_rule.dart';

class ImportRuleCategory {
  const ImportRuleCategory({
    required this.id,
    required this.bookId,
    required this.name,
    required this.type,
    this.available = true,
  });

  final String id;
  final String bookId;
  final String name;
  final TransactionType type;
  final bool available;
}

class TransactionImportRuleInput {
  const TransactionImportRuleInput({
    required this.bookId,
    required this.type,
    required this.accountId,
    required this.description,
    this.reference = '',
    this.merchantHint = '',
  });

  final String bookId;
  final TransactionType type;
  final String accountId;
  final String description;
  final String reference;
  final String merchantHint;
}

class TransactionImportRuleMatch {
  const TransactionImportRuleMatch({
    required this.matchedRuleIds,
    this.winningRuleId,
    this.categoryId,
    this.categoryName,
    this.ambiguous = false,
    this.warnings = const [],
  });

  final List<String> matchedRuleIds;
  final String? winningRuleId;
  final String? categoryId;
  final String? categoryName;
  final bool ambiguous;
  final List<String> warnings;

  bool get hasSuggestion => categoryId != null && !ambiguous;
}

class TransactionImportRuleEngine {
  const TransactionImportRuleEngine();

  TransactionImportRuleMatch evaluate({
    required TransactionImportRuleInput input,
    required Iterable<TransactionImportRule> rules,
    required Map<String, ImportRuleCategory> categories,
    Set<String> activeAccountIds = const {},
  }) {
    final expectedType = input.type == TransactionType.expense
        ? TransactionImportRuleType.expense
        : TransactionImportRuleType.income;
    final normalizedDescription = normalizeImportRuleText(input.description);
    final normalizedReference = normalizeImportRuleText(input.reference);
    final normalizedMerchantHint = normalizeImportRuleText(input.merchantHint);
    final matches =
        rules.where((rule) {
          if (!rule.active ||
              rule.bookId != input.bookId ||
              rule.transactionType != expectedType) {
            return false;
          }
          if (rule.accountId != null &&
              (rule.accountId != input.accountId ||
                  !activeAccountIds.contains(rule.accountId))) {
            return false;
          }
          return _matches(
            rule,
            normalizedDescription: normalizedDescription,
            normalizedReference: normalizedReference,
            normalizedMerchantHint: normalizedMerchantHint,
          );
        }).toList()..sort((a, b) {
          final byPriority = b.priority.compareTo(a.priority);
          return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
        });
    if (matches.isEmpty) {
      return const TransactionImportRuleMatch(matchedRuleIds: []);
    }
    final topPriority = matches.first.priority;
    final top = matches.where((rule) => rule.priority == topPriority).toList();
    final categoryIds = top.map((rule) => rule.categoryId).toSet();
    if (categoryIds.length > 1) {
      return TransactionImportRuleMatch(
        matchedRuleIds: matches.map((rule) => rule.id).toList(),
        ambiguous: true,
        warnings: const [
          'Multiple highest-priority rules suggest different categories.',
        ],
      );
    }
    final winner = top.first;
    final category = categories[winner.categoryId];
    if (category == null ||
        category.bookId != input.bookId ||
        category.type != input.type ||
        !category.available) {
      return TransactionImportRuleMatch(
        matchedRuleIds: matches.map((rule) => rule.id).toList(),
        winningRuleId: winner.id,
        warnings: const ['The matching rule category is unavailable.'],
      );
    }
    return TransactionImportRuleMatch(
      matchedRuleIds: matches.map((rule) => rule.id).toList(),
      winningRuleId: winner.id,
      categoryId: category.id,
      categoryName: category.name,
    );
  }

  static bool _matches(
    TransactionImportRule rule, {
    required String normalizedDescription,
    required String normalizedReference,
    required String normalizedMerchantHint,
  }) {
    final candidates = switch (rule.matchField) {
      TransactionImportRuleMatchField.description => [normalizedDescription],
      TransactionImportRuleMatchField.reference => [normalizedReference],
      TransactionImportRuleMatchField.merchantHint => [normalizedMerchantHint],
      TransactionImportRuleMatchField.descriptionOrReference => [
        normalizedDescription,
        normalizedReference,
      ],
    };
    return candidates.any(
      (candidate) => switch (rule.operator) {
        TransactionImportRuleOperator.contains => candidate.contains(
          rule.patternKey,
        ),
        TransactionImportRuleOperator.equals => candidate == rule.patternKey,
        TransactionImportRuleOperator.startsWith => candidate.startsWith(
          rule.patternKey,
        ),
      },
    );
  }
}
