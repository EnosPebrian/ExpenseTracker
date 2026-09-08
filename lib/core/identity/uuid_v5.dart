import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:uuid/uuid.dart';

/// Canonical RFC 9562 UUIDv5 generation for UUID namespaces.
///
/// The uuid package's v5 entry point rejects syntactically valid PostgreSQL
/// UUID values whose existing version/variant bits are non-RFC. PostgreSQL's
/// uuid_generate_v5 accepts those values as namespaces, so this adapter uses
/// the package's format-only parser while retaining the standard UUIDv5
/// algorithm and output formatting.
class CanonicalUuidV5 {
  const CanonicalUuidV5._();

  static String generate(String namespace, String name) {
    final namespaceBytes = Uuid.parseHex128(namespace);
    final hash = crypto.sha1.convert([
      ...namespaceBytes,
      ...utf8.encode(name),
    ]).bytes;
    hash[6] = (hash[6] & 0x0f) | 0x50;
    hash[8] = (hash[8] & 0x3f) | 0x80;
    return Uuid.unparse(hash.sublist(0, 16));
  }
}
