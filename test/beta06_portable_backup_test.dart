import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/backup/data/portable_backup_codec.dart';
import 'package:pilgrim_tracker/features/backup/domain/backup_models.dart';

import 'support/beta06_fixture.dart';

void main() {
  final codec = PortableBackupCodec(databaseSchemaVersion: 20);

  test('encrypted backup round-trips complete scoped financial data', () async {
    final created = await codec.encode(
      snapshot: beta06Snapshot(),
      password: 'strong-password',
      exportedAt: DateTime.utc(2026, 7, 29),
    );
    final decoded = await codec.decode(created.bytes, 'strong-password');

    expect(decoded.manifest.formatVersion, 1);
    expect(decoded.manifest.databaseSchemaVersion, 20);
    expect(decoded.manifest.entityCounts['transactions'], 2);
    expect(decoded.manifest.financialSummary['income'], 2500000);
    expect(decoded.manifest.financialSummary['expenses'], 500000);
    expect(decoded.snapshot['transactions'], hasLength(2));
    final encodedText = utf8.decode(created.bytes);
    expect(encodedText, isNot(contains('Salary')));
    expect(encodedText, isNot(contains('remote-user-secret')));
    expect(jsonEncode(decoded.snapshot), isNot(contains('auth_user_id')));
    expect(jsonEncode(decoded.snapshot), isNot(contains('device-secret')));
  });

  test('unique salt and nonce produce different encrypted files', () async {
    final first = await codec.encode(
      snapshot: beta06Snapshot(),
      password: 'strong-password',
    );
    final second = await codec.encode(
      snapshot: beta06Snapshot(),
      password: 'strong-password',
    );
    expect(first.bytes, isNot(orderedEquals(second.bytes)));
  });

  test('wrong password and corruption fail closed', () async {
    final created = await codec.encode(
      snapshot: beta06Snapshot(),
      password: 'strong-password',
    );
    await expectLater(
      codec.decode(created.bytes, 'wrong-password'),
      throwsA(isA<BackupPasswordOrCorruptionException>()),
    );
    final corrupted = Uint8List.fromList(created.bytes)
      ..[created.bytes.length - 5] ^= 1;
    await expectLater(
      codec.decode(corrupted, 'strong-password'),
      throwsA(isA<BackupPasswordOrCorruptionException>()),
    );
  });

  test('unsupported future backup format fails before decryption', () async {
    final futureEnvelope = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'container': 'pilgrim-tracker-backup',
          'containerVersion': 999,
        }),
      ),
    );

    await expectLater(
      codec.decode(futureEnvelope, 'strong-password'),
      throwsA(isA<UnsupportedBackupVersionException>()),
    );
  });
}
