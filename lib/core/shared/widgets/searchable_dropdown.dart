import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _muted = Color(0xFF92929F);
const _violet = Color(0xFF6D57DF);

final Map<String, int> _searchableDropdownUsage = {};

int _fuzzyScore(String source, String query) {
  if (query.isEmpty) return 0;
  final text = source.toLowerCase(), needle = query.toLowerCase();
  if (text == needle) return 0;
  if (text.startsWith(needle)) return 1;
  final direct = text.indexOf(needle);
  if (direct >= 0) return 2 + direct;
  var position = 0, gaps = 0;
  for (final character in needle.characters) {
    final found = text.indexOf(character, position);
    if (found < 0) return -1;
    gaps += found - position;
    position = found + 1;
  }
  return 100 + gaps;
}

List<T> _matches<T>({
  required List<T> items,
  required String query,
  required String Function(T) idOf,
  required String Function(T) labelOf,
  String Function(T)? searchTextOf,
}) {
  final ranked = <(T, int)>[];
  for (final item in items) {
    final searchable = searchTextOf?.call(item) ?? labelOf(item);
    final score = _fuzzyScore(searchable, query.trim());
    if (score >= 0) ranked.add((item, score));
  }
  ranked.sort((a, b) {
    if (query.trim().isNotEmpty && a.$2 != b.$2) {
      return a.$2.compareTo(b.$2);
    }
    return (_searchableDropdownUsage[idOf(b.$1)] ?? 0).compareTo(
      _searchableDropdownUsage[idOf(a.$1)] ?? 0,
    );
  });
  return ranked.map((entry) => entry.$1).toList();
}

Future<T?> showSearchablePicker<T>(
  BuildContext context, {
  required String label,
  required List<T> items,
  required T selectedValue,
  required String Function(T) idOf,
  required String Function(T) labelOf,
  String Function(T)? searchTextOf,
}) async {
  final search = TextEditingController();
  var matches = _matches(
    items: items,
    query: '',
    idOf: idOf,
    labelOf: labelOf,
    searchTextOf: searchTextOf,
  );
  var highlighted = 0;
  final chosen = await showDialog<T>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialog) => Dialog(
        alignment: Alignment.center,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 480,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.escape) {
                      final navigator = Navigator.of(dialogContext);
                      Future.microtask(navigator.pop);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                        matches.isNotEmpty) {
                      setDialog(
                        () => highlighted = (highlighted + 1) % matches.length,
                      );
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                        matches.isNotEmpty) {
                      setDialog(
                        () => highlighted =
                            (highlighted - 1 + matches.length) % matches.length,
                      );
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.enter &&
                        matches.isNotEmpty) {
                      final selected = matches[highlighted];
                      final navigator = Navigator.of(dialogContext);
                      Future.microtask(() => navigator.pop(selected));
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: search,
                    autofocus: true,
                    onChanged: (value) => setDialog(() {
                      matches = _matches(
                        items: items,
                        query: value,
                        idOf: idOf,
                        labelOf: labelOf,
                        searchTextOf: searchTextOf,
                      );
                      highlighted = 0;
                    }),
                    decoration: const InputDecoration(
                      hintText: 'Type to search...',
                      prefixIcon: Icon(Icons.search, size: 19),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 230),
                  child: matches.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No matching items',
                              style: TextStyle(color: _muted),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            final item = matches[index];
                            final active = index == highlighted;
                            final selected = idOf(item) == idOf(selectedValue);
                            return InkWell(
                              onTap: () => Navigator.pop(dialogContext, item),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0xFFF1EEFF)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        labelOf(item),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      const Icon(
                                        Icons.check,
                                        color: _violet,
                                        size: 16,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (chosen != null) {
    _searchableDropdownUsage.update(
      idOf(chosen),
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  return chosen;
}

class SearchableDropdown<T> extends StatelessWidget {
  const SearchableDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.selectedValue,
    required this.idOf,
    required this.labelOf,
    required this.onChanged,
    this.searchTextOf,
  });

  final String label;
  final List<T> items;
  final T selectedValue;
  final String Function(T) idOf;
  final String Function(T) labelOf;
  final String Function(T)? searchTextOf;
  final ValueChanged<T> onChanged;

  Future<void> _open(BuildContext context) async {
    final chosen = await showSearchablePicker(
      context,
      label: label,
      items: items,
      selectedValue: selectedValue,
      idOf: idOf,
      labelOf: labelOf,
      searchTextOf: searchTextOf,
    );
    if (chosen != null) onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(9),
    onTap: () => _open(context),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.arrow_drop_down),
      ),
      child: Text(labelOf(selectedValue), style: const TextStyle(fontSize: 11)),
    ),
  );
}

class SearchableSelect extends StatelessWidget {
  const SearchableSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label, value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SearchableDropdown<String>(
    label: label,
    items: options,
    selectedValue: value,
    idOf: (item) => item,
    labelOf: (item) => item,
    searchTextOf: (item) => item,
    onChanged: onChanged,
  );
}
