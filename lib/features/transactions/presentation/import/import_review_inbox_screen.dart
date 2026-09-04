import 'package:flutter/material.dart';

import '../../data/local_import_review_repository.dart';
import '../../domain/entities/import_review_session.dart';

class ImportReviewInboxScreen extends StatefulWidget {
  const ImportReviewInboxScreen({
    super.key,
    required this.repository,
    required this.bookId,
    required this.onReview,
    this.initialSessions,
  });

  final LocalImportReviewRepository repository;
  final String bookId;
  final Future<void> Function(String sessionId) onReview;
  final List<ImportReviewSession>? initialSessions;

  static Future<void> show(
    BuildContext context, {
    required LocalImportReviewRepository repository,
    required String bookId,
    required Future<void> Function(String sessionId) onReview,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ImportReviewInboxScreen(
        repository: repository,
        bookId: bookId,
        onReview: onReview,
      ),
    ),
  );

  @override
  State<ImportReviewInboxScreen> createState() =>
      _ImportReviewInboxScreenState();
}

class _ImportReviewInboxScreenState extends State<ImportReviewInboxScreen> {
  bool loading = true;
  bool completed = false;
  String? error;
  List<ImportReviewSession> sessions = const [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSessions;
    if (initial == null) {
      _load();
    } else {
      sessions = List.unmodifiable(initial);
      loading = false;
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final all = await widget.repository.sessions(bookId: widget.bookId);
      if (!mounted) return;
      setState(() {
        sessions = all;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Import Inbox could not be loaded.';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = sessions.where((session) {
      if (completed) {
        return session.state == ImportReviewSessionState.completed;
      }
      return session.state == ImportReviewSessionState.pendingReview ||
          session.state == ImportReviewSessionState.readyToCommit;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Import Inbox')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Pending imports',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Resume normalized CSV, receipt, invoice, and bank-statement drafts. '
              'Original source files are not stored.',
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(
                    'Pending (${sessions.where((item) => !item.terminal).length})',
                  ),
                ),
                const ButtonSegment(value: true, label: Text('Completed')),
              ],
              selected: {completed},
              onSelectionChanged: (value) => setState(() {
                completed = value.single;
              }),
            ),
            const SizedBox(height: 16),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (visible.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    completed
                        ? 'No completed imports.'
                        : 'No pending imports.\n\nCSV files, receipts, and bank statements '
                              'that you save for later will appear here.',
                  ),
                ),
              )
            else
              for (final session in visible) _card(session),
          ],
        ),
      ),
    );
  }

  Widget _card(ImportReviewSession session) {
    final rowCount = session.summary['row_count'];
    final includedCount = session.summary['included_count'];
    final attentionCount = session.summary['warning_count'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon(session.sourceType)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(_label(session.sourceType)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Rename',
                  onPressed: session.terminal ? null : () => _rename(session),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${rowCount is num ? '${rowCount.toInt()} drafts · ' : ''}'
              '${includedCount is num ? '${includedCount.toInt()} included · ' : ''}'
              'Updated ${_date(session.updatedAt)}',
            ),
            if (attentionCount is num && attentionCount.toInt() > 0)
              Text('${attentionCount.toInt()} need attention'),
            if (session.createdByMemberId != null)
              const Text('Household member attribution retained'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (!session.terminal)
                  FilledButton(
                    onPressed: () async {
                      await widget.onReview(session.id);
                      await _load();
                    },
                    child: const Text('Review'),
                  ),
                if (session.state == ImportReviewSessionState.pendingReview)
                  TextButton(
                    onPressed: () => _discard(session),
                    child: const Text('Discard'),
                  ),
                if (session.state == ImportReviewSessionState.completed)
                  Text(
                    'Completed ${_date(session.completedAt ?? session.updatedAt)}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(ImportReviewSession session) async {
    final controller = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename import'),
        content: TextField(
          controller: controller,
          maxLength: 160,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    final bundle = await widget.repository.load(session.id);
    if (bundle == null) return;
    await widget.repository.save(
      ImportReviewBundle(
        session: session.copyWith(
          title: title,
          updatedAt: DateTime.now(),
          version: session.version + 1,
          syncStatus: 'pending',
        ),
        drafts: bundle.drafts,
      ),
    );
    await _load();
  }

  Future<void> _discard(ImportReviewSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this pending import?'),
        content: const Text(
          'Its normalized drafts will be removed. No financial transactions '
          'will be created or changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.discard(session.id);
    await _load();
  }

  static String _label(ImportReviewSourceType type) => switch (type) {
    ImportReviewSourceType.csv => 'CSV',
    ImportReviewSourceType.receipt => 'Receipt',
    ImportReviewSourceType.invoice => 'Invoice',
    ImportReviewSourceType.bankStatement => 'Bank statement',
  };

  static IconData _icon(ImportReviewSourceType type) => switch (type) {
    ImportReviewSourceType.csv => Icons.table_view,
    ImportReviewSourceType.receipt ||
    ImportReviewSourceType.invoice => Icons.receipt_long,
    ImportReviewSourceType.bankStatement => Icons.account_balance,
  };

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}
