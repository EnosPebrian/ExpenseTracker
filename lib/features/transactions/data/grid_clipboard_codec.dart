/// Strict tabular clipboard codec. Text stays text, never evaluated as formulas.
class GridClipboardCodec {
  static String encode(List<List<String>> rows) => rows
      .map(
        (row) => row
            .map((value) {
              var safe = value;
              if (RegExp(r'^\s*[=+@-]').hasMatch(safe)) safe = "'$safe";
              return safe.contains(RegExp('[\t\r\n"]'))
                  ? '"${safe.replaceAll('"', '""')}"'
                  : safe;
            })
            .join('\t'),
      )
      .join('\n');

  static List<List<String>> decode(String text) {
    if (text.length > 1000000) {
      throw const FormatException('Clipboard exceeds 1 MB.');
    }
    if (text.isEmpty) throw const FormatException('Clipboard is empty.');
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    var closed = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '\t' || ch == '\n' || ch == '\r') {
        row.add(field.toString());
        field = StringBuffer();
        closed = false;
        if (ch != '\t') {
          rows.add(row);
          row = [];
          if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        }
      } else if (ch == '"' && field.isEmpty && !closed) {
        quoted = true;
      } else {
        if (closed || ch == '"') {
          throw const FormatException('Malformed clipboard quoting.');
        }
        field.write(ch);
      }
    }
    if (quoted) throw const FormatException('Unclosed clipboard quote.');
    if (field.isNotEmpty ||
        row.isNotEmpty ||
        closed ||
        !RegExp(r'[\r\n]$').hasMatch(text)) {
      row.add(field.toString());
      rows.add(row);
    }
    if (rows.isEmpty ||
        rows.length > 5000 ||
        rows.any((r) => r.length != rows.first.length)) {
      throw const FormatException(
        'Paste a rectangular table of at most 5,000 rows.',
      );
    }
    return rows;
  }
}
