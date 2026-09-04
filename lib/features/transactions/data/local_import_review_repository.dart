import '../domain/entities/import_review_draft.dart';
import '../domain/entities/import_review_session.dart';

class ImportReviewBundle {
  const ImportReviewBundle({required this.session, required this.drafts});

  final ImportReviewSession session;
  final List<ImportReviewDraft> drafts;
}

class LocalImportReviewRepository {
  const LocalImportReviewRepository(this.store);

  // Native and web stores intentionally expose the same persistence surface,
  // but are separate conditional-export types.
  final dynamic store;

  Future<List<ImportReviewSession>> sessions({
    required String bookId,
    bool includeDeleted = false,
    ImportReviewSessionState? state,
  }) async {
    final rows = List<Map<String, Object?>>.from(
      await store.getImportReviewSessions(
        bookId: bookId,
        includeDeleted: includeDeleted,
        state: state?.name,
      ),
    );
    return rows.map(ImportReviewSession.fromRecord).toList();
  }

  Future<ImportReviewBundle?> load(String sessionId) async {
    final sessionRows = List<Map<String, Object?>>.from(
      await store.getImportReviewSessions(includeDeleted: true),
    );
    final matches = sessionRows.where((row) => row['id'] == sessionId);
    if (matches.isEmpty) return null;
    return ImportReviewBundle(
      session: ImportReviewSession.fromRecord(matches.single),
      drafts: List<Map<String, Object?>>.from(
        await store.getImportReviewDrafts(
          sessionId: sessionId,
          includeDeleted: true,
        ),
      ).map(ImportReviewDraft.fromRecord).toList(),
    );
  }

  Future<void> save(
    ImportReviewBundle bundle, {
    bool enqueueSync = true,
  }) async {
    await store.saveImportReviewSessionAtomic(
      session: bundle.session.toRecord(),
      drafts: bundle.drafts.map((draft) => draft.toRecord()).toList(),
      enqueueSync: enqueueSync,
    );
  }

  Future<void> discard(String sessionId, {bool enqueueSync = true}) async {
    await store.discardImportReviewSession(
      sessionId,
      DateTime.now().millisecondsSinceEpoch,
      enqueueSync: enqueueSync,
    );
  }
}
