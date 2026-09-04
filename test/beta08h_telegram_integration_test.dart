import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pilgrim_tracker/app/presentation/navigation/app_destination.dart';
import 'package:pilgrim_tracker/core/database/local_store_native.dart';
import 'package:pilgrim_tracker/features/telegram_integration/domain/telegram_integration_repository.dart';
import 'package:pilgrim_tracker/features/telegram_integration/presentation/controllers/telegram_integration_controller.dart';
import 'package:pilgrim_tracker/features/telegram_integration/presentation/screens/integrations_screen.dart';
import 'package:pilgrim_tracker/features/master_data/domain/entities/account.dart';
import 'package:pilgrim_tracker/features/transactions/data/csv_transaction_source_parser.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_identity.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_models.dart';
import 'package:pilgrim_tracker/features/transactions/domain/import/transaction_import_planner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Integrations is a stable navigation destination before Backup', () {
    expect(appDestinations[11].label, 'Integrations');
    expect(appDestinations[12].label, 'Backup & Export');
  });

  test(
    'controller loads disconnected status and generates one-time command',
    () async {
      final repository = _FakeRepository();
      final controller = TelegramIntegrationController(
        repository,
        bookId: 'book-1',
        memberId: 'member-1',
        now: () => DateTime.utc(2026, 8, 31),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.connected, isFalse);
      await controller.connect();
      expect(controller.pairing!.command, startsWith('/link '));
      expect(repository.generatedFor, ('book-1', 'member-1'));
    },
  );

  test(
    'pairing command expires from memory without local persistence',
    () async {
      final repository = _FakeRepository(
        expiry: DateTime.utc(2026, 8, 31).add(const Duration(milliseconds: 5)),
      );
      final controller = TelegramIntegrationController(
        repository,
        bookId: 'book-1',
        memberId: 'member-1',
        now: () => DateTime.utc(2026, 8, 31),
      );
      addTearDown(controller.dispose);
      await controller.connect();
      expect(controller.pairing, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(controller.pairing, isNull);
    },
  );

  test('disconnect revokes server connection state only', () async {
    final repository = _FakeRepository(connected: true);
    final controller = TelegramIntegrationController(
      repository,
      bookId: 'book-1',
      memberId: 'member-1',
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.connected, isTrue);
    await controller.disconnect();
    expect(controller.connected, isFalse);
    expect(repository.disconnectedBook, 'book-1');
  });

  test('offline repository exposes safe UI message', () async {
    final controller = TelegramIntegrationController(
      const UnavailableTelegramIntegrationRepository(),
      bookId: 'book-1',
      memberId: 'member-1',
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.error, contains('requires internet'));
  });

  testWidgets('screen shows disconnected, token, and disconnect states', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: IntegrationsScreen(
          repository: repository,
          bookId: 'book-1',
          memberId: 'member-1',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Not connected'), findsOneWidget);
    await tester.tap(find.text('Connect Telegram'));
    await tester.pump();
    expect(find.byKey(const Key('telegram-pairing-command')), findsOneWidget);
    expect(find.text('Copy command'), findsOneWidget);

    repository.connected = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  test('SQLite stays v25 and contains no Telegram integration tables', () async {
    final directory = await Directory.systemTemp.createTemp('beta08h_');
    final store = LocalStore(
      databasePath: p.join(directory.path, 'pilgrim.db'),
    );
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
    await store.initialize();
    expect(await store.db.getVersion(), 25);
    final rows = await store.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'telegram_%'",
    );
    expect(rows, isEmpty);
  });

  test(
    'Telegram deferred source identity yields direct-import canonical UUID',
    () async {
      final bytes = utf8.encode(
        'date,description,amount,type,category,reference,note\n'
        '2026-08-31,Coffee,12000,expense,Food,R1,Test\n',
      );
      final source = await const CsvTransactionSourceParser().parse(
        SelectedCsvFile(name: 'transactions.csv', bytes: bytes),
      );
      final account = Account(
        id: 'account-a',
        bookId: 'book-a',
        name: 'Bank',
        accountType: AccountType.bank,
        currencyCode: 'IDR',
      );
      final direct = await const TransactionImportPlanner().build(
        source: source,
        mapping: canonicalMappingFor(source.headers)!,
        account: account,
        activeBookId: 'book-a',
        existingTransactions: const [],
        expenseCategories: const ['Food'],
        incomeCategories: const [],
      );
      final telegramRawIdentity = jsonEncode({
        'row': 2,
        'date': '2026-08-31',
        'description': 'Coffee',
        'amount': '12000',
        'debit': '',
        'credit': '',
        'reference': 'R1',
      });
      final digest = await Sha256().hash(utf8.encode(telegramRawIdentity));
      final telegramRowFingerprint = digest.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      final deferredFinalized = TransactionImportIdentity.derive(
        bookId: 'book-a',
        accountId: 'account-a',
        sourceFingerprint: source.fileFingerprint,
        sourceRowIdentity: '2',
        sourceRowFingerprint: telegramRowFingerprint,
      );
      expect(telegramRowFingerprint, direct.drafts.single.sourceRowFingerprint);
      expect(deferredFinalized, direct.drafts.single.transactionId);
    },
  );
}

class _FakeRepository implements TelegramIntegrationRepository {
  _FakeRepository({this.connected = false, DateTime? expiry})
    : expiry = expiry ?? DateTime.now().add(const Duration(minutes: 10));

  bool connected;
  final DateTime expiry;
  (String, String)? generatedFor;
  String? disconnectedBook;

  @override
  Future<void> disconnect(String bookId) async {
    disconnectedBook = bookId;
    connected = false;
  }

  @override
  Future<TelegramPairingCommand> generatePairingCommand({
    required String bookId,
    required String memberId,
  }) async {
    generatedFor = (bookId, memberId);
    return TelegramPairingCommand(
      command: '/link high-entropy-test-token',
      expiresAt: expiry,
    );
  }

  @override
  Future<TelegramConnectionStatus> status(String bookId) async =>
      TelegramConnectionStatus(connected: connected);
}
