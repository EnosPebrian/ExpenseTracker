import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/data/csv_transaction_source_parser.dart';
import 'package:pilgrim_tracker/features/transactions/domain/entities/transaction.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/csv_value_parsers.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_planner.dart';

void main() {
  const parser = CsvTransactionSourceParser();

  group('BETA-08B CSV source parsing', () {
    Future<CsvParsedSource> parse(String text, {String name = 'data.csv'}) =>
        parser.parse(SelectedCsvFile(name: name, bytes: utf8.encode(text)));

    test('canonical comma CSV preserves row numbers', () async {
      final source = await parse(
        'date,description,amount,type\n2026-08-01,Food,250000,expense\n',
      );
      expect(source.delimiter, ',');
      expect(source.headers, ['date', 'description', 'amount', 'type']);
      expect(source.rows.single.rowNumber, 2);
    });

    test('semicolon and CRLF are supported', () async {
      final source = await parse(
        'date;description;amount;type\r\n2026-08-01;Food;1.000;expense\r\n',
      );
      expect(source.delimiter, ';');
      expect(source.rows.single.values[1], 'Food');
    });

    test('UTF-8 BOM is removed', () async {
      final source = await parse(
        '\uFEFFdate,description,amount,type\n2026-08-01,Food,1,expense',
      );
      expect(source.headers.first, 'date');
    });

    test('quoted delimiter and escaped quote are decoded', () async {
      final source = await parse(
        'date,description,amount,type\n2026-08-01,"Shop, ""A""",1,expense',
      );
      expect(source.rows.single.values[1], 'Shop, "A"');
    });

    test('blank lines are ignored', () async {
      final source = await parse(
        'date,description,amount,type\n\n2026-08-01,Food,1,expense\n\n',
      );
      expect(source.rows, hasLength(1));
    });

    test('first row data mode creates neutral column names', () async {
      final file = SelectedCsvFile(
        name: 'data.csv',
        bytes: utf8.encode('2026-08-01,Food,1\n2026-08-02,Fuel,2'),
      );
      final source = await parser.parse(
        file,
        headerMode: CsvHeaderMode.firstRowData,
      );
      expect(source.rows, hasLength(2));
      expect(source.headers.first, 'Column 1');
    });

    test(
      'empty, bad extension, malformed quote and invalid UTF-8 reject',
      () async {
        await expectLater(
          parser.parse(const SelectedCsvFile(name: 'x.csv', bytes: [])),
          throwsA(isA<TransactionImportException>()),
        );
        await expectLater(
          parser.parse(
            SelectedCsvFile(name: 'x.txt', bytes: utf8.encode('a,b')),
          ),
          throwsA(isA<TransactionImportException>()),
        );
        await expectLater(
          parse('a,b\n"unclosed,b'),
          throwsA(isA<TransactionImportException>()),
        );
        await expectLater(
          parser.parse(const SelectedCsvFile(name: 'x.csv', bytes: [0xff])),
          throwsA(isA<TransactionImportException>()),
        );
      },
    );

    test('file and row limits reject without truncation', () async {
      await expectLater(
        parser.parse(
          SelectedCsvFile(
            name: 'large.csv',
            bytes: List.filled(csvImportMaxBytes + 1, 65),
          ),
        ),
        throwsA(isA<TransactionImportException>()),
      );
      final rows = List.generate(
        csvImportMaxRows + 1,
        (i) => '2026-08-01,x,1,expense',
      ).join('\n');
      await expectLater(
        parse('date,description,amount,type\n$rows'),
        throwsA(isA<TransactionImportException>()),
      );
    });
  });

  group('BETA-08B exact money parsing', () {
    const money = CsvMoneyParser();
    int value(
      String source, {
      String currency = 'IDR',
      CsvSeparator decimal = CsvSeparator.none,
      CsvSeparator thousands = CsvSeparator.none,
      bool symbols = false,
    }) => money.parse(
      source,
      currencyCode: currency,
      decimalSeparator: decimal,
      thousandsSeparator: thousands,
      stripCurrencySymbols: symbols,
    );

    test(
      'plain integer remains exact',
      () => expect(value('1250000'), 1250000),
    );
    test(
      'comma grouping is exact',
      () => expect(value('1,250,000', thousands: CsvSeparator.comma), 1250000),
    );
    test(
      'period grouping is exact',
      () => expect(value('1.250.000', thousands: CsvSeparator.period), 1250000),
    );
    test(
      'US decimal is exact minor units',
      () => expect(
        value(
          '1,250.50',
          currency: 'USD',
          decimal: CsvSeparator.period,
          thousands: CsvSeparator.comma,
        ),
        125050,
      ),
    );
    test(
      'European decimal is exact minor units',
      () => expect(
        value(
          '1.250,50',
          currency: 'EUR',
          decimal: CsvSeparator.comma,
          thousands: CsvSeparator.period,
        ),
        125050,
      ),
    );
    test(
      'ambiguous separator is rejected',
      () => expect(
        () => value('1.234'),
        throwsA(isA<TransactionImportException>()),
      ),
    );
    test(
      'configured symbols may be stripped',
      () => expect(
        value('Rp 25,000', thousands: CsvSeparator.comma, symbols: true),
        25000,
      ),
    );
    test('zero and impossible precision reject', () {
      expect(() => value('0'), throwsA(isA<TransactionImportException>()));
      expect(
        () => value('1.234', currency: 'USD', decimal: CsvSeparator.period),
        throwsA(isA<TransactionImportException>()),
      );
    });
  });

  group('BETA-08B local date parsing', () {
    const dates = CsvTransactionDateParser();
    test('supported numeric formats preserve local day', () {
      expect(
        dates.parse('2026-08-19', CsvDateFormat.automatic),
        DateTime(2026, 8, 19),
      );
      expect(
        dates.parse('19/08/2026', CsvDateFormat.ddMmYyyySlash),
        DateTime(2026, 8, 19),
      );
      expect(
        dates.parse('08/19/2026', CsvDateFormat.mmDdYyyySlash),
        DateTime(2026, 8, 19),
      );
      expect(
        dates.parse('19-08-2026', CsvDateFormat.ddMmYyyyDash),
        DateTime(2026, 8, 19),
      );
      expect(
        dates.parse('2026/08/19', CsvDateFormat.yyyyMmDdSlash),
        DateTime(2026, 8, 19),
      );
    });
    test('named months and leap days work', () {
      expect(
        dates.parse('29 Feb 2028', CsvDateFormat.ddMmmYyyy),
        DateTime(2028, 2, 29),
      );
      expect(
        dates.parse('31 August 2026', CsvDateFormat.ddMmmmYyyy),
        DateTime(2026, 8, 31),
      );
    });
    test('ambiguous automatic and invalid date reject', () {
      expect(
        () => dates.parse('08/09/2026', CsvDateFormat.automatic),
        throwsA(isA<TransactionImportException>()),
      );
      expect(
        () => dates.parse('31/02/2026', CsvDateFormat.ddMmYyyySlash),
        throwsA(isA<TransactionImportException>()),
      );
    });
  });

  group('BETA-08B planning and identity', () {
    final account = Account(
      id: 'account-a',
      bookId: 'book-a',
      name: 'Bank',
      accountType: AccountType.bank,
    );
    final sourceBytes = utf8.encode(
      'date,description,amount,type,category\n2026-08-01,Food,250000,expense,Groceries',
    );

    Future<TransactionImportPreview> plan({
      List<Transaction> existing = const [],
      Account? destination,
    }) async {
      final source = await parser.parse(
        SelectedCsvFile(name: 'x.csv', bytes: sourceBytes),
      );
      return const TransactionImportPlanner().build(
        source: source,
        mapping: canonicalMappingFor(source.headers)!,
        account: destination ?? account,
        activeBookId: 'book-a',
        existingTransactions: existing,
        expenseCategories: const ['Groceries'],
        incomeCategories: const ['Salary'],
      );
    }

    test(
      'canonical mapping and exact category produce a ready draft',
      () async {
        final preview = await plan();
        expect(preview.readyCount, 1);
        expect(preview.drafts.single.category, 'Groceries');
        expect(preview.expenseTotal, 250000);
      },
    );

    test(
      'same source identity is deterministic and draft edits preserve it',
      () async {
        final first = (await plan()).drafts.single;
        final second = (await plan()).drafts.single;
        expect(first.transactionId, second.transactionId);
        expect(
          first.copyWith(description: 'Edited').transactionId,
          first.transactionId,
        );
        expect(
          RegExp(r'^[0-9a-f-]{36}$').hasMatch(first.transactionId),
          isTrue,
        );
      },
    );

    test('different account changes stable identity', () async {
      final first = (await plan()).drafts.single;
      final other = Account(id: 'account-b', bookId: 'book-a', name: 'Other');
      final second = (await plan(destination: other)).drafts.single;
      expect(second.transactionId, isNot(first.transactionId));
    });

    test('same exact file import is already imported and excluded', () async {
      final initial = (await plan()).drafts.single;
      final existing = Transaction(
        id: initial.transactionId,
        bookId: 'book-a',
        title: initial.description,
        category: initial.category,
        account: account.name,
        date: initial.date,
        amount: initial.amount,
        type: initial.type,
      );
      final repeated = (await plan(existing: [existing])).drafts.single;
      expect(
        repeated.classification,
        TransactionImportClassification.alreadyImported,
      );
      expect(repeated.included, isFalse);
    });

    test(
      'different ID with matching semantics is a semantic duplicate',
      () async {
        final existing = Transaction(
          id: 'other-id',
          bookId: 'book-a',
          title: ' food ',
          category: 'Groceries',
          account: account.name,
          date: DateTime(2026, 8, 1),
          amount: 250000,
          type: TransactionType.expense,
        );
        final draft = (await plan(existing: [existing])).drafts.single;
        expect(
          draft.classification,
          TransactionImportClassification.semanticDuplicate,
        );
        expect(draft.included, isFalse);
      },
    );

    test('matching tombstone is warned and excluded', () async {
      final existing = Transaction(
        id: 'deleted-id',
        bookId: 'book-a',
        title: 'Food',
        category: 'Groceries',
        account: account.name,
        date: DateTime(2026, 8, 1),
        amount: 250000,
        type: TransactionType.expense,
        deletedAt: DateTime(2026, 8, 2),
      );
      final draft = (await plan(existing: [existing])).drafts.single;
      expect(
        draft.classification,
        TransactionImportClassification.possiblePreviouslyDeleted,
      );
      expect(draft.included, isFalse);
    });
  });
}
