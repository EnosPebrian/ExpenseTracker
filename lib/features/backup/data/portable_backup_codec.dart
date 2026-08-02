import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';

import '../domain/backup_models.dart';
import '../domain/household_backup_integrity.dart';

class PortableBackupCodec {
  PortableBackupCodec({required this.databaseSchemaVersion});

  static const _containerName = 'pilgrim-tracker-backup';
  static const _containerVersion = 1;
  static const _kdfIterations = 210000;

  final int databaseSchemaVersion;
  final _cipher = AesGcm.with256bits();
  final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _kdfIterations,
    bits: 256,
  );
  final _sha256 = Sha256();

  Future<CreatedBackup> encode({
    required Map<String, List<Map<String, Object?>>> snapshot,
    required String password,
    DateTime? exportedAt,
  }) async {
    if (password.isEmpty) {
      throw const BackupValidationException('A backup password is required.');
    }
    final clean = HouseholdBackupIntegrity.sanitize(snapshot);
    HouseholdBackupIntegrity.validate(clean);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final encryptionMetadata = <String, Object?>{
      'cipher': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _kdfIterations,
      'saltBytes': salt.length,
      'nonceBytes': nonce.length,
    };

    final contentFiles = <String, Uint8List>{};
    for (final key in portableBackupEntityKeys) {
      final jsonValue = key == 'household' ? clean[key]!.single : clean[key]!;
      contentFiles['$key.json'] = _jsonBytes(jsonValue);
    }
    final checksums = <String, String>{};
    for (final entry in contentFiles.entries) {
      checksums[entry.key] = await _hash(entry.value);
    }
    final contentChecksum = await _hash(_jsonBytes(checksums));
    final household = clean['household']!.single;
    final manifest = PortableBackupManifest(
      formatVersion: portableBackupFormatVersion,
      applicationVersion: portableBackupApplicationVersion,
      databaseSchemaVersion: databaseSchemaVersion,
      exportedAt: (exportedAt ?? DateTime.now()).toUtc(),
      bookId: household['id'] as String,
      bookName: household['name'] as String,
      baseCurrencyCode: household['base_currency_code'] as String,
      entityCounts: {
        for (final key in portableBackupEntityKeys) key: clean[key]!.length,
      },
      contentChecksum: contentChecksum,
      encryptionMetadata: encryptionMetadata,
      financialSummary: HouseholdBackupIntegrity.financialSummary(clean),
      deletedStateCounts: HouseholdBackupIntegrity.deletedStateCounts(clean),
    );

    final archive = Archive();
    final manifestBytes = _jsonBytes(manifest.toJson());
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    for (final entry in contentFiles.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final checksumBytes = _jsonBytes(checksums);
    archive.addFile(
      ArchiveFile('checksums.json', checksumBytes.length, checksumBytes),
    );
    final payload = ZipEncoder().encodeBytes(archive);
    final key = await _deriveKey(password, salt);
    final encrypted = await _cipher.encrypt(
      payload,
      secretKey: key,
      nonce: nonce,
    );
    final envelope = <String, Object?>{
      'container': _containerName,
      'containerVersion': _containerVersion,
      'kdf': {
        'name': 'PBKDF2-HMAC-SHA256',
        'iterations': _kdfIterations,
        'salt': base64Encode(salt),
      },
      'encryption': {
        'name': 'AES-256-GCM',
        'nonce': base64Encode(nonce),
        'mac': base64Encode(encrypted.mac.bytes),
      },
      'ciphertext': base64Encode(encrypted.cipherText),
    };
    return CreatedBackup(
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      manifest: manifest,
    );
  }

  Future<DecodedBackup> decode(Uint8List bytes, String password) async {
    try {
      final envelope = Map<String, Object?>.from(
        jsonDecode(utf8.decode(bytes)) as Map,
      );
      if (envelope['container'] != _containerName) {
        throw const FormatException('Unknown backup container.');
      }
      final containerVersion = (envelope['containerVersion'] as num).toInt();
      if (containerVersion > _containerVersion) {
        throw UnsupportedBackupVersionException(containerVersion);
      }
      final kdf = Map<String, Object?>.from(envelope['kdf']! as Map);
      final encryption = Map<String, Object?>.from(
        envelope['encryption']! as Map,
      );
      if (kdf['name'] != 'PBKDF2-HMAC-SHA256' ||
          encryption['name'] != 'AES-256-GCM' ||
          (kdf['iterations'] as num).toInt() != _kdfIterations) {
        throw const FormatException('Unsupported encryption metadata.');
      }
      final salt = base64Decode(kdf['salt'] as String);
      final nonce = base64Decode(encryption['nonce'] as String);
      final secretBox = SecretBox(
        base64Decode(envelope['ciphertext'] as String),
        nonce: nonce,
        mac: Mac(base64Decode(encryption['mac'] as String)),
      );
      final payload = await _cipher.decrypt(
        secretBox,
        secretKey: await _deriveKey(password, salt),
      );
      final archive = ZipDecoder().decodeBytes(payload, verify: true);
      final files = <String, Uint8List>{
        for (final file in archive.files.where((file) => file.isFile))
          file.name: file.readBytes() ?? Uint8List(0),
      };
      final manifest = PortableBackupManifest.fromJson(
        _jsonMap(files, 'manifest.json'),
      );
      if (manifest.formatVersion > portableBackupFormatVersion) {
        throw UnsupportedBackupVersionException(manifest.formatVersion);
      }
      if (manifest.formatVersion != portableBackupFormatVersion) {
        throw const FormatException('Unsupported older backup format.');
      }
      final checksums = _jsonMap(
        files,
        'checksums.json',
      ).map((key, value) => MapEntry(key, value as String));
      for (final entry in checksums.entries) {
        final content = files[entry.key];
        if (content == null || await _hash(content) != entry.value) {
          throw const FormatException('Backup checksum mismatch.');
        }
      }
      if (await _hash(_jsonBytes(checksums)) != manifest.contentChecksum) {
        throw const FormatException('Backup content checksum mismatch.');
      }

      final snapshot = <String, List<Map<String, Object?>>>{};
      for (final key in portableBackupEntityKeys) {
        final decoded = jsonDecode(
          utf8.decode(files['$key.json'] ?? (throw const FormatException())),
        );
        final values = key == 'household' ? [decoded] : decoded as List;
        snapshot[key] = values
            .map((value) => Map<String, Object?>.from(value as Map))
            .toList(growable: false);
      }
      HouseholdBackupIntegrity.validate(snapshot);
      for (final key in portableBackupEntityKeys) {
        if (manifest.entityCounts[key] != snapshot[key]!.length) {
          throw const FormatException('Manifest entity count mismatch.');
        }
      }
      if (_canonicalJson(HouseholdBackupIntegrity.financialSummary(snapshot)) !=
          _canonicalJson(manifest.financialSummary)) {
        throw const FormatException('Backup accounting summary mismatch.');
      }
      if (_canonicalJson(
            HouseholdBackupIntegrity.deletedStateCounts(snapshot),
          ) !=
          _canonicalJson(manifest.deletedStateCounts)) {
        throw const FormatException('Backup lifecycle summary mismatch.');
      }
      return DecodedBackup(manifest: manifest, snapshot: snapshot);
    } on UnsupportedBackupVersionException {
      rethrow;
    } on BackupValidationException {
      rethrow;
    } catch (_) {
      throw const BackupPasswordOrCorruptionException();
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) {
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  Future<String> _hash(List<int> bytes) async {
    final digest = await _sha256.hash(bytes);
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Map<String, Object?> _jsonMap(
    Map<String, Uint8List> files,
    String name,
  ) {
    final bytes = files[name];
    if (bytes == null) throw FormatException('Missing $name.');
    return Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  static Uint8List _jsonBytes(Object? value) =>
      Uint8List.fromList(utf8.encode(_canonicalJson(value)));

  static String _canonicalJson(Object? value) =>
      jsonEncode(_canonicalize(value));

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList(growable: false);
    return value;
  }
}
