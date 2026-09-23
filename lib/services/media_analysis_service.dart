import 'dart:convert';
import 'dart:typed_data';

import 'media_analysis.dart';
import 'media_analyzer.dart';
import 'media_limits.dart';
import 'sync_trigger.dart';

/// What one `analyze` call did.
class AnalysisOutcome {
  const AnalysisOutcome({
    this.result,
    this.blocked,
    this.error,
    this.videoDeclined = false,
  });

  /// The answer, when it worked.
  final AnalysisResult? result;

  /// Set when the request was refused before any network call.
  final AnalysisBlock? blocked;

  /// Set when the call was made and failed. Already user-facing copy.
  final String? error;

  /// The message attached a video, so nothing was sent and nothing counted.
  ///
  /// Not a block: the video stays in the chat, and the CALLER persists the
  /// message plus a notice as a pair with `includeInModel` false, so a replay
  /// never sends it. This class persists nothing for it.
  final bool videoDeclined;

  bool get isBlocked => blocked != null;
}

/// One thing attached to the message being sent.
///
/// An image carries its bytes, already prepared by the caller (downscaled for
/// the assistant, or the stored file for Describe). A video carries none: it is
/// declined on the device and its bytes are never read.
class AnalysisAttachment {
  const AnalysisAttachment.image({
    required this.mediaId,
    required this.mimeType,
    required Uint8List this.bytes,
  }) : kind = AttachmentKind.image;

  const AnalysisAttachment.video(this.mediaId)
      : kind = AttachmentKind.video,
        mimeType = '',
        bytes = null;

  final String mediaId;
  final AttachmentKind kind;
  final String mimeType;
  final Uint8List? bytes;
}

/// What the daily cap has counted so far, as stored.
typedef AnalysisUsage = ({String? day, int? count});

/// Decides whether a message may be sent to the model, then sends it.
///
/// ## Why the gates are duplicated from MediaUploadService
///
/// They are not the same gates for the same reason. Upload asks "may this
/// device write to this account's cloud storage". This asks "may these bytes be
/// sent to a third party outside the user's own project" — a strictly larger
/// question, which is why it carries the extra [AnalysisBlock.notConsented]
/// step and why it is checked here rather than inherited.
///
/// The overlap is deliberate all the same: `isSyncEnabledFor` is the predicate
/// the Settings sync tile renders from, so gating on it is what makes the tile
/// and this feature incapable of disagreeing. Sending a photograph while the
/// app states the user's data stays on their device is a false privacy claim,
/// which is the one failure this app treats as unshippable.
///
/// ## Gate order
///
/// available → uid → writesBlocked → declined → syncOff → consent, then a
/// video is declined, then an unreadable type, photo size, the photo caps and
/// the inline budget, the turn cap, the memo and last the daily cap. A video is
/// declined AFTER consent so an unconsented user is asked to consent rather
/// than shown a notice, and BEFORE everything else so it never costs a turn, a
/// count or a network call.
///
/// ## The memo is a cost control
///
/// Opening answers about photos are held for the life of this instance, keyed
/// by the sorted photo ids plus the question, so reopening the same photo and
/// asking the same thing does not re-bill. Only an opener with at least one
/// photo is memoized: a text-only opener ("hi") is not about anything the memo
/// can identify. It is a [kAnalysisMemoSize]-entry LRU, cleared when the
/// signed-in account changes or the day rolls over, because this instance can
/// live as long as the app. A memo hit is still forwarded to [_persistTurn]
/// via [_remember] — see [_persistTurn]'s doc comment for why the caller must
/// not simply re-persist it there.
///
/// ## Conversations ARE persisted, but not by this class
///
/// [_transcripts] holds what the model has been told in each conversation so
/// far, keyed by conversation id — the in-memory working copy [analyze] reads
/// for `history` on every call, because `generateContent` keeps no session of
/// its own. [_images] holds the prepared bytes of every photo those turns
/// attach, because every earlier photo is resent on every call. Both are
/// cleared by [endConversation] (and a deleted photo's bytes by
/// [forgetImage]), and seeded back from a STORED transcript by
/// [seedConversation] when the caller resumes a saved conversation: restoring
/// only what the user sees, without restoring what the model was told, gets a
/// conversation that displays history but has none.
///
/// The durable copy lives elsewhere, in the encrypted drift database
/// (`AnalysisSessions` / `AnalysisMessages`), synced to the account — but this
/// class still never imports a repository or the database to do it:
/// [_persistTurn] is an injected closure resolved by the caller, and
/// `test/media_guardrails_test.dart` structurally forbids this file from
/// importing `MediaRepository`, `MediaBlobStore`, `AppDatabase` or
/// `lunaFirestore`. Every early return above [_remember] — a gate, a daily-cap
/// refusal, a thrown [AnalysisException] — skips persistence along with the
/// transcript, so only errorless exchanges are ever saved.
class MediaAnalysisService {
  MediaAnalysisService({
    required MediaAnalyzer analyzer,
    required SyncTrigger trigger,
    required String? Function() consentUid,
    required int? Function() consentVersion,
    required AnalysisUsage Function() readUsage,
    required Future<void> Function(String day, int count) writeUsage,
    required Future<void> Function({
      required String conversationId,
      required String question,
      required List<AttachmentRef> attachments,
      required String answer,
      required bool isMemoHit,
    }) persistTurn,
    DateTime Function() now = DateTime.now,
    // Nullable rather than defaulted: `analysisAvailable` reads a
    // `String.fromEnvironment` getter, which is not a constant expression and
    // so cannot be a default value.
    bool? available,
  })  : _analyzer = analyzer,
        _trigger = trigger,
        _consentUid = consentUid,
        _consentVersion = consentVersion,
        _readUsage = readUsage,
        _writeUsage = writeUsage,
        _persistTurn = persistTurn,
        _now = now,
        _available = available ?? analysisAvailable;

  final MediaAnalyzer _analyzer;
  final SyncTrigger _trigger;
  final String? Function() _consentUid;

  /// Which consent disclosure [_consentUid]'s account agreed to. Compared
  /// against [kCurrentConsentVersion] everywhere [_consentUid] is compared
  /// against the current uid — a stale version is exactly as unconsented as
  /// no uid at all, because it means the account agreed to a narrower
  /// disclosure than what this build actually sends.
  final int? Function() _consentVersion;
  final AnalysisUsage Function() _readUsage;
  final Future<void> Function(String day, int count) _writeUsage;

  /// Saves one errorless exchange (the user's message, what it attached, and
  /// the model's reply) to whatever conversation store the CALLER wires up.
  ///
  /// Opaque and injected for the same reason [MediaAnalysisService] never
  /// imports `AnalysisSessionRepository` itself: this class must not be able
  /// to reach the database (`test/media_guardrails_test.dart` enforces it).
  /// The caller resolves the session for the conversation id or creates one,
  /// then appends both turns — this class knows none of that; it just calls
  /// the function once per successful turn.
  ///
  /// [isMemoHit] is true when the answer came from the in-memory memo rather
  /// than a fresh network call — see [_memo]. It exists ONLY so the caller
  /// can decide whether this exchange is already saved: a memo hit re-serves
  /// an answer already shown once before, and if a session already holds
  /// that opening exchange, persisting again would insert an exact
  /// duplicate (`AnalysisSessionRepository.append` is a pure insert, not an
  /// upsert). This class does not make that decision itself — it has no
  /// concept of a "session" to check.
  final Future<void> Function({
    required String conversationId,
    required String question,
    required List<AttachmentRef> attachments,
    required String answer,
    required bool isMemoHit,
  }) _persistTurn;
  final DateTime Function() _now;
  final bool _available;

  /// Opening answers already fetched, least recently used first, keyed by
  /// [_memoKey].
  ///
  /// Keyed on the question too: asking something different about the same
  /// photos is a different request, and returning the previous answer to a new
  /// question would look like the model ignoring it.
  ///
  /// Consulted ONLY when the conversation has nothing the model has seen.
  /// Mid-conversation, the same words mean something different — "and the
  /// other one?" asked at turn two and at turn six are different questions —
  /// so a memo hit there would replay a stale answer.
  final Map<String, AnalysisResult> _memo = {};

  /// Whose memo [_memo] is, and for which day; see [_expireMemo].
  String? _memoUid;
  String? _memoDay;

  /// The conversation so far for each conversation id, oldest turn first.
  final Map<String, List<AnalysisTurn>> _transcripts = {};

  /// The prepared photos each conversation's turns attach, by media id.
  final Map<String, Map<String, InlineImage>> _images = {};

  /// Which opening of each conversation a call belongs to; see [_remember].
  ///
  /// Taken by [analyze] when it starts and dropped by [endConversation], so a
  /// call still in flight when its chat closes finds a different token (or
  /// none) when it returns.
  final Map<String, Object> _openings = {};

  /// Photos a seed handed over that are over [kMaxAnalysisBytes], by
  /// conversation. Held back from [_images] and refused at the next [analyze]
  /// as [AnalysisBlock.tooLarge] — the same answer an oversized attachment
  /// gets — rather than silently dropped, which would send the deleted-photo
  /// placeholder for a photo the user still has.
  final Map<String, Set<String>> _oversized = {};

  /// Media ids deleted while this instance was alive; see [forgetImage].
  ///
  /// Kept, not just applied once, so a turn already in flight when its photo
  /// was deleted, or a resume that loaded the photo just before, cannot write
  /// the bytes back. Ids are never reused, and this only grows by deletions.
  final Set<String> _forgotten = {};

  /// Forgets [conversationId]'s transcript and photos. Called when the chat
  /// closes, so reopening it resumes from storage rather than silently from
  /// memory.
  void endConversation(String conversationId) {
    _transcripts.remove(conversationId);
    _images.remove(conversationId);
    _oversized.remove(conversationId);
    _openings.remove(conversationId);
  }

  /// Drops [mediaId]'s bytes from every live conversation, because the photo
  /// was deleted.
  ///
  /// Every earlier photo is resent on every call, so without this a photo
  /// deleted mid-conversation would keep reaching the model until the chat
  /// closed. Afterwards the request builder sends [kDeletedPhotoPlaceholder]
  /// in its place — exactly what a resumed conversation gets for it.
  ///
  /// Called by the caller's media-deletion path (`media_route.dart` wires it
  /// to `MediaSyncService`'s `onDeleted`): this class cannot see deletions
  /// itself, since it may not reach the database.
  void forgetImage(String mediaId) {
    _forgotten.add(mediaId);
    for (final images in _images.values) {
      images.remove(mediaId);
    }
    for (final ids in _oversized.values) {
      ids.remove(mediaId);
    }
  }

  /// Seeds [conversationId]'s in-memory conversation from a STORED transcript,
  /// so the next [analyze] call carries full prior context instead of treating
  /// a follow-up as an opening question.
  ///
  /// [_transcripts] is the ONLY thing [analyze] reads for `history`. Without a
  /// seed, resuming a saved conversation shows the old turns on screen but the
  /// model has no memory of them — `generateContent` is stateless. This class
  /// cannot load a stored transcript itself (it must stay ignorant of
  /// persistence), so the caller hands it over as plain [AnalysisTurn]s, plus
  /// [images]: the prepared bytes of the photos those turns attach. A photo
  /// the caller no longer has is simply left out, and the request builder
  /// sends the deleted-photo placeholder in its place.
  ///
  /// Seeded turns count toward [kMaxChatTurns] via [turnsUsed], same as any
  /// other turn.
  ///
  /// A no-op for the turns on an empty list, so callers can pass through
  /// whatever a loader returned, and a no-op for the turns if
  /// [conversationId] already has an in-memory conversation — seeding over
  /// live turns would silently discard them. [images] are merged either way,
  /// except a photo [forgetImage] has dropped, and a photo over
  /// [kMaxAnalysisBytes]: that one is held back and makes the next [analyze]
  /// refuse as [AnalysisBlock.tooLarge], as an oversized attachment does.
  void seedConversation(
    String conversationId,
    List<AnalysisTurn> turns, {
    Map<String, InlineImage> images = const {},
  }) {
    for (final MapEntry(key: id, value: image) in images.entries) {
      if (_forgotten.contains(id)) continue;
      if (_decodedLength(image.base64) > kMaxAnalysisBytes) {
        _oversized.putIfAbsent(conversationId, () => {}).add(id);
      } else {
        _images.putIfAbsent(conversationId, () => {})[id] = image;
      }
    }
    if (turns.isEmpty) return;
    if (_transcripts.containsKey(conversationId)) return;
    _transcripts[conversationId] = List.of(turns);
  }

  /// How many messages the model has been sent in [conversationId] so far.
  ///
  /// Counts only turns with `includeInModel`: a declined-video pair was never
  /// sent and never billed, so it does not use up the conversation.
  int turnsUsed(String conversationId) =>
      _transcripts[conversationId]
          ?.where((t) => t.role == AnalysisRole.user && t.includeInModel)
          .length ??
      0;

  /// Whether the account may analyse right now, for gating the affordance.
  ///
  /// Cheap and synchronous — deliberately NOT the full gate. It answers only
  /// "has this account opted in", which is what decides whether the button is
  /// shown versus whether a tap succeeds. The authoritative check is [analyze].
  bool get consented => isConsentedFor(
        uid: _trigger.currentUid,
        consentUid: _consentUid(),
        consentVersion: _consentVersion(),
      );

  /// How many analyses remain today.
  int get remainingToday {
    final usage = _readUsage();
    final used = analysisCountForDay(
      storedDay: usage.day,
      storedCount: usage.count,
      now: _now(),
    );
    final left = kMaxAnalysesPerDay - used;
    return left < 0 ? 0 : left;
  }

  /// Sends [question] with [attachments] as the next message of
  /// [conversationId], or explains why it will not.
  ///
  /// [attachments] are this message's only; photos from earlier turns are
  /// already held (see [_images]) and are resent without being passed again.
  ///
  /// [healthContext] is built by the CALLER and passed through untouched.
  /// It is assembled outside this class on purpose: a service that could read
  /// the database could leak health data into a request by accident, which is
  /// why `test/media_guardrails_test.dart` forbids the import.
  Future<AnalysisOutcome> analyze({
    required String conversationId,
    List<AnalysisAttachment> attachments = const [],
    String? question,
    String? healthContext,
  }) async {
    final accountBlock = await _accountGate();
    if (accountBlock != null) return AnalysisOutcome(blocked: accountBlock);
    final uid = _trigger.currentUid!;
    // Consent is checked AFTER the sync gates so a user who has not turned sync
    // on is told that, rather than being sent to a toggle that would not help.
    // Compared against the CURRENT uid: a consent recorded by another account on
    // this device is not this account's consent. Compared against
    // kCurrentConsentVersion too (inside isConsentedFor): a stored version
    // below current means the account agreed to an earlier, narrower
    // disclosure and must be asked again.
    if (!isConsentedFor(
        uid: uid, consentUid: _consentUid(), consentVersion: _consentVersion())) {
      return const AnalysisOutcome(blocked: AnalysisBlock.notConsented);
    }
    // Declined on the device: no bytes read, nothing sent, nothing counted,
    // nothing remembered. The whole message is declined, photos included, so
    // what the model is sent never depends on which part of a message it saw.
    if (attachments.any((a) => a.kind == AttachmentKind.video)) {
      return const AnalysisOutcome(videoDeclined: true);
    }
    for (final photo in attachments) {
      if (mediaKindFor(photo.mimeType) != MediaKind.image) {
        return const AnalysisOutcome(blocked: AnalysisBlock.notAnImage);
      }
    }
    for (final photo in attachments) {
      if (photo.bytes!.length > kMaxAnalysisBytes) {
        return const AnalysisOutcome(blocked: AnalysisBlock.tooLarge);
      }
    }
    // The same per-photo limit, for photos a resume seeded.
    if (_oversized[conversationId]?.isNotEmpty ?? false) {
      return const AnalysisOutcome(blocked: AnalysisBlock.tooLarge);
    }

    final opening = _openings.putIfAbsent(conversationId, Object.new);
    final history = _transcripts[conversationId] ?? const <AnalysisTurn>[];
    final newIds = {for (final photo in attachments) photo.mediaId};
    if (_tooManyPhotos(history, newIds)) {
      return const AnalysisOutcome(blocked: AnalysisBlock.tooManyPhotos);
    }

    final asked = normalizeQuestion(question);
    final refs = [for (final id in newIds) AttachmentRef.image(id)];
    final next = AnalysisTurn.user(asked, attachments: refs);
    final images = <String, InlineImage>{
      ...?_images[conversationId],
      for (final photo in attachments)
        photo.mediaId: InlineImage(
          mimeType: photo.mimeType,
          base64: base64Encode(photo.bytes!),
        ),
    };
    // Every earlier photo rides along again, so this is checked against the
    // whole request, not just this message's photos.
    if (!withinInlineBudget(history: history, next: next, images: images)) {
      return const AnalysisOutcome(blocked: AnalysisBlock.tooLarge);
    }

    // Bounds one conversation. Checked before the memo because the two are
    // mutually exclusive — the memo only ever answers an empty conversation.
    if (turnsUsed(conversationId) >= kMaxChatTurns) {
      return const AnalysisOutcome(blocked: AnalysisBlock.turnCap);
    }

    final now = _now();
    final day = analysisDayKey(now);
    _expireMemo(uid, day);
    final fresh = !history.any((t) => t.includeInModel);
    final memoKey = fresh && newIds.isNotEmpty ? _memoKey(newIds, asked) : null;
    if (memoKey != null) {
      final memoized = _memo.remove(memoKey);
      // Served before the cap is consulted: a repeat view costs nothing, so
      // charging it against the day's allowance would be charging for nothing.
      if (memoized != null) {
        _memo[memoKey] = memoized; // most recently used again
        // Seeded so a follow-up after a memo hit still has a referent.
        await _remember(conversationId, opening, history, next, images,
            memoized,
            isMemoHit: true);
        return AnalysisOutcome(result: memoized);
      }
    }

    final usage = _readUsage();
    final used = analysisCountForDay(
      storedDay: usage.day,
      storedCount: usage.count,
      now: now,
    );
    if (used >= kMaxAnalysesPerDay) {
      return const AnalysisOutcome(blocked: AnalysisBlock.dailyCap);
    }

    // Counted BEFORE the call, not after. A crash or a kill mid-request would
    // otherwise leave a billed call uncounted, and the cap exists to bound
    // spend rather than to bound successes. The user loses at most one of
    // twenty on a failure, which is the cheaper of the two mistakes.
    await _writeUsage(day, used + 1);

    final AnalysisResult result;
    try {
      result = await _analyzer.analyze(
        history: history,
        next: next,
        images: images,
        healthContext: healthContext,
      );
    } on AnalysisException catch (e) {
      // The transcript is deliberately NOT extended on a failure. Appending a
      // user turn with no model reply would break the alternation the API
      // expects, and the next question would be sent against a conversation
      // that never happened. Its photos are not kept either.
      return AnalysisOutcome(error: e.message);
    } catch (_) {
      // Never surfaces the raw object: it can carry the request, and the
      // request carries the image.
      return const AnalysisOutcome(error: 'Something went wrong. Try again.');
    }

    if (memoKey != null) {
      _memo[memoKey] = result;
      if (_memo.length > kAnalysisMemoSize) _memo.remove(_memo.keys.first);
    }
    await _remember(conversationId, opening, history, next, images, result,
        isMemoHit: false);
    return AnalysisOutcome(result: result);
  }

  /// Whether a message attaching [newImageIds] would be refused before it
  /// was sent, for a reason the caller could have known up front: the account
  /// gates, the daily cap, and the photo caps. Sends nothing, counts nothing.
  ///
  /// For running BEFORE a rewarded ad, so nobody watches one for a message
  /// that was always going to be refused — a reward taken and never
  /// delivered. Consent is deliberately not checked: the caller asks for it
  /// itself, between this and the ad. [analyze] still runs every gate; this
  /// only moves the predictable refusals earlier.
  Future<AnalysisBlock?> preflight({
    String? conversationId,
    Set<String> newImageIds = const {},
  }) async {
    final accountBlock = await _accountGate();
    if (accountBlock != null) return accountBlock;
    final history = conversationId == null
        ? const <AnalysisTurn>[]
        : _transcripts[conversationId] ?? const <AnalysisTurn>[];
    if (_tooManyPhotos(history, newImageIds)) {
      return AnalysisBlock.tooManyPhotos;
    }
    if (remainingToday <= 0) return AnalysisBlock.dailyCap;
    return null;
  }

  /// The gates about the build and the account, in [analyze]'s order: shared
  /// with [preflight] so the two cannot disagree.
  Future<AnalysisBlock?> _accountGate() async {
    if (!_available) return AnalysisBlock.unavailable;
    final uid = _trigger.currentUid;
    if (uid == null) return AnalysisBlock.notSignedIn;
    if (_trigger.writesBlocked) {
      final declined = await _trigger.declinedUidOnRecord();
      return declined == uid
          ? AnalysisBlock.syncDeclined
          : AnalysisBlock.writesBlocked;
    }
    if (await _trigger.declinedUidOnRecord() == uid) {
      return AnalysisBlock.syncDeclined;
    }
    // Broadest of the sync gates, and last of them — see MediaUploadBlock.syncOff.
    if (!await _trigger.isSyncEnabledFor(uid)) return AnalysisBlock.syncOff;
    return null;
  }

  /// Whether [newIds] is more photos than one message may attach, or would
  /// take the conversation past its own cap. Only photos the model was sent
  /// count: a declined message's photos never reached it.
  static bool _tooManyPhotos(List<AnalysisTurn> history, Set<String> newIds) {
    if (newIds.length > kMaxImagesPerMessage) return true;
    final conversationIds = {
      for (final turn in history)
        if (turn.includeInModel && turn.role == AnalysisRole.user)
          for (final ref in turn.attachments)
            if (ref.kind == AttachmentKind.image) ref.mediaId,
      ...newIds,
    };
    return conversationIds.length > kMaxImagesPerConversation;
  }

  /// How many bytes [base64] decodes to, without decoding it.
  static int _decodedLength(String base64) {
    final padding = base64.endsWith('==')
        ? 2
        : base64.endsWith('=')
            ? 1
            : 0;
    return base64.length * 3 ~/ 4 - padding;
  }

  /// `'<sorted photo ids>|<question>'`. Sorted so the same photos attached in
  /// a different order are the same request.
  static String _memoKey(Set<String> ids, String asked) =>
      '${(ids.toList()..sort()).join(',')}|$asked';

  /// Drops the memo when the account or the day changed since it was filled.
  ///
  /// An answer about one account's photo must never be served to another,
  /// and a day's memo must not outlive the day's cap it saved billing against.
  void _expireMemo(String uid, String day) {
    if (_memoUid == uid && _memoDay == day) return;
    _memo.clear();
    _memoUid = uid;
    _memoDay = day;
  }

  /// Appends one exchange to [conversationId]'s conversation, keeps its
  /// photos, and saves it through [_persistTurn].
  ///
  /// A result with no prose (a classifier backend fills `labels` instead) is not
  /// recorded: there is no model utterance to echo back on the next turn, and
  /// nothing to save either.
  ///
  /// This is the ONLY path that calls [_persistTurn] — every early return
  /// above it (a gate, a daily-cap refusal, a thrown [AnalysisException])
  /// skips this method entirely, which is what keeps errors and refusals out
  /// of the saved transcript.
  ///
  /// [isMemoHit] is forwarded to [_persistTurn] untouched — see that field's
  /// doc comment for why this class does not act on it itself.
  ///
  /// [opening] is the token [analyze] took when it started. When the chat
  /// was closed while the call was out, it no longer matches, and the
  /// exchange is saved but NOT written back into memory: [endConversation]
  /// already forgot that conversation, and rewriting it here would hold its
  /// transcript and photo bytes for the life of the app.
  Future<void> _remember(
    String conversationId,
    Object opening,
    List<AnalysisTurn> history,
    AnalysisTurn next,
    Map<String, InlineImage> images,
    AnalysisResult result, {
    required bool isMemoHit,
  }) async {
    final prose = result.prose;
    if (prose == null || prose.trim().isEmpty) return;
    if (identical(_openings[conversationId], opening)) {
      _transcripts[conversationId] = <AnalysisTurn>[
        ...history,
        next,
        AnalysisTurn.model(prose),
      ];
      images.removeWhere((id, _) => _forgotten.contains(id));
      if (images.isNotEmpty) _images[conversationId] = images;
    }
    await _persistTurn(
      conversationId: conversationId,
      question: next.text,
      attachments: next.attachments,
      answer: prose,
      isMemoHit: isMemoHit,
    );
  }
}
