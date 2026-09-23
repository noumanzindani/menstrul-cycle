import 'package:drift/drift.dart';

import '../db/database.dart';
import '../services/media_analysis.dart';
import '../services/media_paths.dart';

/// Saved assistant conversations.
///
/// Every read is scoped by uid, for the same reason `MediaRepository` scopes
/// its own: signing out does not wipe the device, so without the filter one
/// account's conversation about a body photo could render under another
/// account.
///
/// This class never talks to Firestore, Cloud Storage or Gemini itself; it is
/// a pure store over two drift tables. The rows DO sync, though — the old
/// "deliberately not synced" note here was stale since v12 — through
/// `SyncService`, which is why a user's delete is a tombstone ([tombstone])
/// rather than a hard delete: a vanished row cannot tell another device it is
/// gone. Every read skips tombstones.
class AnalysisSessionRepository {
  AnalysisSessionRepository(this._db);
  final AppDatabase _db;

  /// One account's sessions, most recently active first.
  ///
  /// Sorted by `updatedAt` (bumped by [append] on every turn), not
  /// `createdAt` — a saved-conversations list should surface the
  /// conversation the user most recently added to, not just the one they
  /// started most recently.
  ///
  /// Drift's default `DateTime` column storage truncates to whole seconds,
  /// so two sessions updated within the same second tie on `updatedAt`. The
  /// `rowid` tiebreak — SQLite's implicit, strictly increasing insertion
  /// counter on every ordinary table — resolves that tie deterministically
  /// instead of leaving it to undefined SQL sort order (see
  /// `MediaRepository.allFor`'s `id` tiebreak for the sibling case; a random
  /// opaque id can't play that role here because it carries no relation to
  /// insertion order).
  Future<List<AnalysisSession>> allFor(String uid) =>
      (_db.select(_db.analysisSessions)
            ..where((t) => t.uid.equals(uid) & t.deletedAt.isNull())
            ..orderBy([
              (t) =>
                  OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
              (t) => OrderingTerm(
                  expression: const CustomExpression<int>('rowid'),
                  mode: OrderingMode.desc),
            ]))
          .get();

  /// The session [id], tombstone or not.
  ///
  /// Unlike every other read here this one does NOT skip tombstones: its
  /// caller is an open chat about to save a reply, and a conversation deleted
  /// meanwhile (on this device or another) must be recognised as deleted
  /// rather than silently re-created under the same id.
  Future<AnalysisSession?> byId(String id) =>
      (_db.select(_db.analysisSessions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// The existing conversation about [mediaId] under [uid], if there is one.
  ///
  /// Lets tapping Describe on a photo RESUME the existing conversation
  /// instead of silently starting a second one about the same picture.
  ///
  /// Only matches the conversation that STARTED from [mediaId]; a chat that
  /// attached the photo in a later turn is not "its" conversation. An empty
  /// [mediaId] — the marker for a chat started in the tab — never matches.
  Future<AnalysisSession?> forMedia({
    required String uid,
    required String mediaId,
  }) async {
    if (mediaId.isEmpty) return null;
    return (_db.select(_db.analysisSessions)
          ..where((t) =>
              t.uid.equals(uid) &
              t.mediaId.equals(mediaId) &
              t.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// Starts a new conversation and returns the stored row.
  ///
  /// [mediaId] is the photo a Describe chat started from; leave it `''` for a
  /// chat started in the Assistant tab. [title] is the first thing the user
  /// typed, stored trimmed and cut to [kMaxSessionTitleLength] characters.
  ///
  /// [id] lets the caller name the conversation before its first reply
  /// exists — the assistant screen holds an id from the moment it opens, and
  /// the row created on the first reply must be that conversation. Omitted,
  /// a fresh one is generated.
  Future<AnalysisSession> create({
    required String uid,
    String mediaId = '',
    String? title,
    required int consentVersion,
    String? id,
  }) =>
      _db.into(_db.analysisSessions).insertReturning(
            AnalysisSessionsCompanion.insert(
              // Same 128-bit opaque generator the media ids use — random, not
              // content-derived, so it carries no information of its own.
              id: id ?? newMediaId(),
              uid: uid,
              mediaId: mediaId,
              consentVersion: consentVersion,
              title: Value(_titleFrom(title)),
            ),
          );

  /// Longest stored title, in characters.
  static const kMaxSessionTitleLength = 60;

  /// Cut by code point, not UTF-16 unit, so an emoji at the boundary is kept
  /// or dropped whole rather than split into a lone surrogate.
  static String? _titleFrom(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return String.fromCharCodes(trimmed.runes.take(kMaxSessionTitleLength));
  }

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
  /// [attachments] are stored as references only (see `encodeAttachments`) —
  /// the bytes are loaded and attached to the request at build time, and this
  /// table never holds them. [includeInModel] false stores a turn the chat
  /// shows but a replay or resume never sends, such as the declined-video
  /// pair.
  ///
  /// More than [kMaxAttachmentsPerMessage] attachments throws
  /// [ArgumentError] and stores nothing: the cloud backup would refuse the
  /// message, and the composer must never offer it.
  ///
  /// Also bumps the parent session's `updatedAt`, which is what makes that
  /// column mean "last activity" rather than duplicating `createdAt`
  /// forever — [allFor] sorts on it for exactly this reason.
  Future<void> append({
    required String sessionId,
    required String role,
    required String text,
    List<AttachmentRef> attachments = const [],
    bool includeInModel = true,
  }) async {
    if (attachments.length > kMaxAttachmentsPerMessage) {
      throw ArgumentError.value(
        attachments.length,
        'attachments',
        'at most $kMaxAttachmentsPerMessage per message',
      );
    }
    await _db.into(_db.analysisMessages).insert(
          AnalysisMessagesCompanion.insert(
            id: newMediaId(),
            sessionId: sessionId,
            role: role,
            messageText: text,
            attachmentsJson: Value(encodeAttachments(attachments)),
            includeInModel: Value(includeInModel),
          ),
        );
    await (_db.update(_db.analysisSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(AnalysisSessionsCompanion(updatedAt: Value(DateTime.now())));
  }

  /// Deletes the conversation [id]: in one transaction, marks the session
  /// row deleted, bumps its `updatedAt`, clears its title, and hard-deletes
  /// its messages.
  ///
  /// The session row stays behind as a tombstone because the rows sync: the
  /// bumped `updatedAt` is what makes the next push carry the deletion to the
  /// user's other devices, even when the delete happened offline. Every read
  /// here already skips it.
  Future<void> tombstone(String id) => _tombstoneAll([id]);

  /// Tombstones every conversation that includes [mediaId], and every turn in
  /// them.
  ///
  /// Called when the photo itself is deleted: a conversation about a picture
  /// that no longer exists is an orphan holding commentary about that
  /// picture, which is exactly what this guards against. That covers both the
  /// conversation that STARTED from the photo and any conversation that
  /// attached it in a later turn.
  ///
  /// The later-turn search is a LIKE on the stored JSON, with the pattern
  /// passed through drift's `.like()` so [mediaId] is a bound parameter,
  /// never interpolated SQL. It matches the bare id rather than this client's
  /// exact `"mediaId":"…"` spelling, because the column syncs and another
  /// client may space or order its JSON differently. That makes it only a
  /// prefilter: LIKE also treats `_` and `%` as wildcards, so every candidate
  /// is re-checked against its decoded references before anything is
  /// deleted.
  Future<void> deleteForMedia(String mediaId) async {
    if (mediaId.isEmpty) return;
    final started = await (_db.select(_db.analysisSessions)
          ..where((t) => t.mediaId.equals(mediaId) & t.deletedAt.isNull()))
        .get();

    final candidates = await (_db.select(_db.analysisMessages)
          ..where((t) => t.attachmentsJson.like('%$mediaId%')))
        .get();
    final attachedIn = {
      for (final m in candidates)
        if (decodeAttachments(m.attachmentsJson)
            .any((a) => a.mediaId == mediaId))
          m.sessionId,
    };
    final attached = attachedIn.isEmpty
        ? const <AnalysisSession>[]
        : await (_db.select(_db.analysisSessions)
              ..where((t) => t.id.isIn(attachedIn) & t.deletedAt.isNull()))
            .get();

    await _tombstoneAll({for (final s in [...started, ...attached]) s.id}
        .toList());
  }

  Future<void> _tombstoneAll(List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.analysisSessions)..where((t) => t.id.isIn(ids)))
          .write(AnalysisSessionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        // The title is the user's own first words. The row is kept only to
        // carry the deletion to other devices, so it keeps nothing they said.
        title: const Value(null),
      ));
      await (_db.delete(_db.analysisMessages)
            ..where((t) => t.sessionId.isIn(ids)))
          .go();
    });
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
