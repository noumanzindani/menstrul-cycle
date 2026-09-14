import 'package:drift/drift.dart';

import '../db/database.dart';
import '../services/media_paths.dart';

/// Saved photo-analysis conversations, local-only.
///
/// Every read is scoped by uid, for the same reason `MediaRepository` scopes
/// its own: signing out does not wipe the device, so without the filter one
/// account's conversation about a body photo could render under another
/// account.
///
/// This class never talks to Firestore or Cloud Storage — sessions and their
/// messages are deliberately not synced. It also never reaches into Cloud
/// Storage or Gemini itself; it is a pure store over two drift tables.
class AnalysisSessionRepository {
  AnalysisSessionRepository(this._db);
  final AppDatabase _db;

  /// One account's sessions, newest first.
  ///
  /// Drift's default `DateTime` column storage truncates to whole seconds,
  /// so two sessions created back-to-back in the same second tie on
  /// `createdAt`. The `rowid` tiebreak — SQLite's implicit, strictly
  /// increasing insertion counter on every ordinary table — resolves that
  /// tie toward "most recently created first" instead of leaving it to
  /// undefined SQL sort order (see `MediaRepository.allFor`'s `id` tiebreak
  /// for the sibling case; a random opaque id can't play that role here
  /// because it carries no relation to insertion order).
  Future<List<AnalysisSession>> allFor(String uid) =>
      (_db.select(_db.analysisSessions)
            ..where((t) => t.uid.equals(uid))
            ..orderBy([
              (t) =>
                  OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
              (t) => OrderingTerm(
                  expression: const CustomExpression<int>('rowid'),
                  mode: OrderingMode.desc),
            ]))
          .get();

  /// The existing conversation about [mediaId] under [uid], if there is one.
  ///
  /// Lets tapping Describe on a photo RESUME the existing conversation
  /// instead of silently starting a second one about the same picture.
  Future<AnalysisSession?> forMedia({
    required String uid,
    required String mediaId,
  }) =>
      (_db.select(_db.analysisSessions)
            ..where((t) => t.uid.equals(uid) & t.mediaId.equals(mediaId))
            ..limit(1))
          .getSingleOrNull();

  /// Starts a new conversation about [mediaId] and returns the stored row.
  Future<AnalysisSession> create({
    required String uid,
    required String mediaId,
    required int consentVersion,
  }) =>
      _db.into(_db.analysisSessions).insertReturning(
            AnalysisSessionsCompanion.insert(
              // Same 128-bit opaque generator the media ids use — random, not
              // content-derived, so it carries no information of its own.
              id: newMediaId(),
              uid: uid,
              mediaId: mediaId,
              consentVersion: consentVersion,
            ),
          );

  /// One session's turns, oldest first — how a transcript is replayed.
  ///
  /// Same tiebreak reasoning as [allFor]: two turns appended within the same
  /// stored second must not resolve to a coin flip. Insertion order is what
  /// actually happened, so it is what the tiebreak reproduces.
  Future<List<AnalysisMessage>> messagesFor(String sessionId) =>
      (_db.select(_db.analysisMessages)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAt),
              (t) => OrderingTerm(
                  expression: const CustomExpression<int>('rowid')),
            ]))
          .get();

  /// Appends one turn to an existing session.
  ///
  /// The image itself is never stored here — it is attached to the request
  /// at build time, once, and this table only ever holds text.
  Future<void> append({
    required String sessionId,
    required String role,
    required String text,
  }) =>
      _db.into(_db.analysisMessages).insert(
            AnalysisMessagesCompanion.insert(
              id: newMediaId(),
              sessionId: sessionId,
              role: role,
              messageText: text,
            ),
          );

  /// Removes the conversation about [mediaId], and every turn in it.
  ///
  /// Called when the photo itself is deleted: a conversation about a picture
  /// that no longer exists is an orphan holding commentary about that
  /// picture, which is exactly what this guards against.
  Future<void> deleteForMedia(String mediaId) async {
    final sessions = await (_db.select(_db.analysisSessions)
          ..where((t) => t.mediaId.equals(mediaId)))
        .get();
    if (sessions.isEmpty) return;

    final ids = sessions.map((s) => s.id).toList();
    await (_db.delete(_db.analysisMessages)
          ..where((t) => t.sessionId.isIn(ids)))
        .go();
    await (_db.delete(_db.analysisSessions)..where((t) => t.id.isIn(ids)))
        .go();
  }

  /// Drops every session (and its messages) not belonging to [uid]; pass
  /// null to drop them all.
  ///
  /// Runs on an account change and on sign-out, mirroring
  /// `MediaRepository.deleteExcept` — the uid filter on every read already
  /// makes another account's rows invisible, this is what stops the
  /// conversation text from sitting on disk regardless.
  Future<void> deleteExcept(String? uid) async {
    final doomed = await (_db.select(_db.analysisSessions)
          ..where((t) =>
              uid == null ? const Constant(true) : t.uid.equals(uid).not()))
        .get();
    if (doomed.isEmpty) return;

    final ids = doomed.map((s) => s.id).toList();
    await (_db.delete(_db.analysisMessages)
          ..where((t) => t.sessionId.isIn(ids)))
        .go();
    await (_db.delete(_db.analysisSessions)..where((t) => t.id.isIn(ids)))
        .go();
  }
}
