import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/services/transaction_grid_policy.dart';

/// Virtualized rows with a fixed header. All writes are delegated to the controller.
class TransactionGrid extends StatefulWidget {
  const TransactionGrid({
    super.key,
    required this.rows,
    required this.policy,
    required this.onSave,
    this.onOpen,
    this.onConflict,
    this.syncStates = const {},
    this.loading = false,
    this.error,
  });
  final List<Transaction> rows;
  final TransactionGridPolicy policy;
  final Future<void> Function(Transaction) onSave;
  final ValueChanged<Transaction>? onOpen;
  final VoidCallback? onConflict;
  final Map<String, String> syncStates;
  final bool loading;
  final String? error;

  @override
  State<TransactionGrid> createState() => _TransactionGridState();
}

class _TransactionGridState extends State<TransactionGrid> {
  static const fields = TransactionGridField.values;
  static const labels = [
    'Date',
    'Description',
    'Type',
    'Amount (storage units)',
    'Category',
    'Account',
    'Project',
    'Asset / Instrument',
    'Reference',
    'Note',
    'Sync state',
  ];
  final widths = <double>[
    130,
    230,
    130,
    180,
    170,
    160,
    160,
    160,
    170,
    240,
    120,
  ];
  final vertical = ScrollController();
  final horizontal = ScrollController();
  final focus = FocusNode();
  final editor = TextEditingController();
  String? selected;
  int column = 0;
  int sortColumn = 0;
  bool ascending = false;
  bool editing = false;
  bool saving = false;
  String? editError;
  Transaction? original;
  List<Transaction> sorted = [];
  Map<String, String> projectNames = {};

  @override
  void initState() {
    super.initState();
    _sort();
  }

  @override
  void didUpdateWidget(TransactionGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sort();
  }

  @override
  void dispose() {
    vertical.dispose();
    horizontal.dispose();
    focus.dispose();
    editor.dispose();
    super.dispose();
  }

  void _sort() {
    projectNames = {
      for (final e in widget.policy.projects.entries) e.value: e.key,
    };
    sorted = List.of(widget.rows);
    sorted.sort((a, b) {
      final order = sortColumn == 3
          ? a.amount.compareTo(b.amount)
          : sortColumn == 0
          ? a.date.compareTo(b.date)
          : _value(
              a,
              sortColumn,
            ).toLowerCase().compareTo(_value(b, sortColumn).toLowerCase());
      return (ascending ? 1 : -1) * (order == 0 ? a.id.compareTo(b.id) : order);
    });
  }

  String _state(Transaction row) =>
      widget.syncStates[row.id] ??
      (row.syncStatus == 'synced'
          ? 'Synced'
          : row.syncStatus == 'local_only'
          ? 'Local only'
          : 'Pending');
  String _value(Transaction row, int col) => switch (fields[col]) {
    TransactionGridField.date => row.date.toIso8601String().split('T').first,
    TransactionGridField.description => row.title,
    TransactionGridField.type => row.type.name,
    TransactionGridField.amount => row.amount.toString(),
    TransactionGridField.category => row.category,
    TransactionGridField.account => row.account,
    TransactionGridField.project => projectNames[row.projectId] ?? '',
    TransactionGridField.asset => row.assetSymbol ?? row.assetName ?? '',
    TransactionGridField.reference => row.reference ?? '',
    TransactionGridField.note => row.note ?? '',
    TransactionGridField.sync => _state(row),
  };

  void _select(Transaction row, int col) {
    if (editing || saving) return;
    setState(() {
      selected = row.id;
      column = col;
      editError = null;
    });
    focus.requestFocus();
  }

  void _edit(Transaction row, int col) {
    if (saving || editing) return;
    if (fields[col] == TransactionGridField.sync && _state(row) == 'Conflict') {
      widget.onConflict?.call();
      return;
    }
    if (!widget.policy.canEdit(row)) {
      widget.onOpen?.call(row);
      return;
    }
    if (!fields[col].editable) return;
    setState(() {
      selected = row.id;
      column = col;
      original = row;
      editing = true;
      editError = null;
      editor.text = _value(row, col);
      editor.selection = TextSelection(
        baseOffset: 0,
        extentOffset: editor.text.length,
      );
    });
  }

  Future<void> _save({int move = 0}) async {
    if (!editing || saving || original == null) return;
    setState(() {
      saving = true;
      editError = null;
    });
    try {
      final latest = widget.rows.where((r) => r.id == original!.id).firstOrNull;
      if (latest == null ||
          latest.version != original!.version ||
          latest.updatedAt != original!.updatedAt) {
        throw StateError(
          'Record changed while editing. Cancel and reopen the cell.',
        );
      }
      final next = widget.policy.prepare(latest, fields[column], editor.text);
      await widget.onSave(next);
      if (!mounted) return;
      setState(() {
        editing = false;
        original = null;
      });
      focus.requestFocus();
      if (move != 0) _move(0, move, editableOnly: true);
    } catch (e) {
      if (mounted) setState(() => editError = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _move(int dy, int dx, {bool editableOnly = false}) {
    if (sorted.isEmpty) return;
    var row = sorted.indexWhere((r) => r.id == selected);
    if (row < 0) row = 0;
    var col = column + dx;
    if (editableOnly) {
      while (col >= 0 && col < fields.length && !fields[col].editable) {
        col += dx;
      }
    }
    if (col >= fields.length) {
      row++;
      col = 0;
    }
    if (col < 0) {
      row--;
      col = 9;
    }
    row = (row + dy).clamp(0, sorted.length - 1);
    col = col.clamp(0, fields.length - 1);
    setState(() {
      selected = sorted[row].id;
      column = col;
    });
    if (vertical.hasClients) {
      final top = row * 44.0;
      if (top < vertical.offset ||
          top + 44 > vertical.offset + vertical.position.viewportDimension) {
        vertical.jumpTo(top.clamp(0, vertical.position.maxScrollExtent));
      }
    }
    if (horizontal.hasClients) {
      final left = widths.take(col).fold<double>(0, (a, b) => a + b);
      if (left < horizontal.offset ||
          left + widths[col] >
              horizontal.offset + horizontal.position.viewportDimension) {
        horizontal.jumpTo(left.clamp(0, horizontal.position.maxScrollExtent));
      }
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || saving) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && editing) {
      setState(() {
        editing = false;
        editError = null;
        original = null;
      });
      focus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      final direction = HardwareKeyboard.instance.isShiftPressed ? -1 : 1;
      if (editing) {
        _save(move: direction);
      } else {
        _move(0, direction, editableOnly: true);
      }
      return KeyEventResult.handled;
    }
    if (editing) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.enter) {
      final row = sorted.where((r) => r.id == selected).firstOrNull;
      if (row != null) _edit(row, column);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, 0);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, 0);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _move(0, -1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _move(0, 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    onKeyEvent: _key,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${sorted.length} transactions · Enter/double-click to edit · Escape cancels · Amounts use account storage units',
        ),
        if (widget.loading || saving) const LinearProgressIndicator(),
        if (editError ?? widget.error case final String error)
          Text(
            error,
            key: const Key('grid-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Expanded(
          child: sorted.isEmpty
              ? const Center(child: Text('No transactions in this date range'))
              : Scrollbar(
                  controller: horizontal,
                  thumbVisibility: true,
                  notificationPredicate: (n) =>
                      n.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: widths.fold<double>(0, (a, b) => a + b),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                for (var c = 0; c < fields.length; c++)
                                  SizedBox(
                                    width: widths[c],
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: editing
                                                ? null
                                                : () => setState(() {
                                                    ascending = sortColumn == c
                                                        ? !ascending
                                                        : true;
                                                    sortColumn = c;
                                                    _sort();
                                                  }),
                                            child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Text(
                                                '${labels[c]}${sortColumn == c ? (ascending ? ' ↑' : ' ↓') : ''}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        MouseRegion(
                                          cursor:
                                              SystemMouseCursors.resizeColumn,
                                          child: GestureDetector(
                                            onHorizontalDragUpdate: (d) =>
                                                setState(
                                                  () => widths[c] =
                                                      (widths[c] + d.delta.dx)
                                                          .clamp(90, 600),
                                                ),
                                            child: const SizedBox(
                                              width: 8,
                                              height: 44,
                                              child: VerticalDivider(),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              controller: vertical,
                              itemExtent: 44,
                              itemCount: sorted.length,
                              itemBuilder: (context, index) {
                                final row = sorted[index];
                                return Row(
                                  key: ValueKey('grid-row-${row.id}'),
                                  children: [
                                    for (var c = 0; c < fields.length; c++)
                                      SizedBox(
                                        width: widths[c],
                                        height: 44,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color:
                                                selected == row.id &&
                                                    column == c
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primaryContainer
                                                : (index.isEven
                                                      ? Theme.of(
                                                          context,
                                                        ).colorScheme.surface
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .surfaceContainerLow),
                                            border: Border.all(
                                              color:
                                                  selected == row.id &&
                                                      column == c
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : Theme.of(
                                                      context,
                                                    ).dividerColor,
                                              width: .5,
                                            ),
                                          ),
                                          child:
                                              editing &&
                                                  selected == row.id &&
                                                  column == c
                                              ? TextField(
                                                  key: const Key('grid-editor'),
                                                  controller: editor,
                                                  autofocus: true,
                                                  enabled: !saving,
                                                  onSubmitted: (_) => _save(),
                                                  decoration:
                                                      const InputDecoration(
                                                        isDense: true,
                                                        contentPadding:
                                                            EdgeInsets.all(8),
                                                      ),
                                                )
                                              : GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () {
                                                    _select(row, c);
                                                    if (fields[c] ==
                                                            TransactionGridField
                                                                .sync &&
                                                        _state(row) ==
                                                            'Conflict') {
                                                      widget.onConflict?.call();
                                                    }
                                                  },
                                                  onDoubleTap: () =>
                                                      _edit(row, c),
                                                  child: Tooltip(
                                                    message: _value(row, c),
                                                    child: Align(
                                                      alignment: c == 3
                                                          ? Alignment
                                                                .centerRight
                                                          : Alignment
                                                                .centerLeft,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                            ),
                                                        child: Text(
                                                          _value(row, c),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                  ],
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
      ],
    ),
  );
}
