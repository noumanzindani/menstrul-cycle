import 'dart:typed_data';

import 'media_analysis.dart';
import 'media_analyzer.dart';
import 'sync_trigger.dart';

/// What one `analyze` call did.
class AnalysisOutcome {
  const AnalysisOutcome({this.result, this.blocked, this.error});

  /// The answer, when it worked.
  final AnalysisResult? result;

  /// Set when the request was refused before any network call.
  final AnalysisBlock? blocked;

  /// Set when the call was made and failed. Already user-facing copy.
  final String? error;

  bool get isBlocked => blocked != null;
}

/// What the daily cap has counted so far, as stored.
typedef AnalysisUsage = ({String? day, int? count});

/// Decides whether a photo may be described, then describes it.
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
/// and this feature incapable of disagreeing. Describing a photograph while the
/// app states the user's data stays on their device is a false privacy claim,
/// which is the one failure this app treats as unshippable.
///
/// ## The memo is a cost control
///
/// Opening descriptions are held per media id for the life of this instance
/// (which is the life of the timeline route). Re-opening the same photo does not
/// re-bill, and nothing reaches disk — see the "nothing derived is stored" note
/// in `media_analysis.dart`.
///
/// ## Conversations are in memory and end when the sheet does
///
/// [_transcripts] holds what the model has been told about each photo so far.
/// It exists because `generateContent` keeps no session: without it, every
/// follow-up would be a cold start and "how many are there?" would have no
/// referent. It is cleared by [endConversation] when the sheet closes, and it
/// never touches disk.
///
/// That last part is not laziness. A saved chat log about a body photo would be
/// a second, softer copy of the most sensitive content in the app, and it would
/// then need its own erasure path in `deleteAllData`, the purge job, `.lunabak`
/// exclusion and the doctor-PDF exclusion — the same argument that keeps single
/// descriptions unsaved, only more so.
class MediaAnalysisService {
  MediaAnalysisService({
    required MediaAnalyzer analyzer,
    required SyncTrigger trigger,
    required String? Function() consentUid,
    required AnalysisUsage Function() readUsage,
    required Future<void> Function(String day, int count) writeUsage,
    DateTime Function() now = DateTime.now,
    // Nullable rather than defaulted: `analysisAvailable` reads a
    // `String.fromEnvironment` getter, which is not a constant expression and
    // so cannot be a default value.
    bool? available,
  })  : _analyzer = analyzer,
        _trigger = trigger,
        _consentUid = consentUid,
        _readUsage = readUsage,
        _writeUsage = writeUsage,
        _now = now,
        _available = available ?? analysisAvailable;

  final MediaAnalyzer _analyzer;
  final SyncTrigger _trigger;
  final String? Function() _consentUid;
  final AnalysisUsage Function() _readUsage;
  final Future<void> Function(String day, int count) _writeUsage;
  final DateTime Function() _now;
  final bool _available;

  /// Opening answers already fetched this session, keyed by `mediaId|question`.
  ///
  /// Keyed on the question too: asking something different about the same photo
  /// is a different request, and returning the previous answer to a new question
  /// would look like the model ignoring it.
  ///
  /// Consulted ONLY when the conversation is empty. Mid-conversation, the same
  /// words mean something different — "and the other one?" asked at turn two and
  /// at turn six are different questions — so a memo hit there would replay a
  /// stale answer.
  final Map<String, AnalysisResult> _memo = {};

  /// The conversation so far for each photo, oldest turn first.
  final Map<String, List<AnalysisTurn>> _transcripts = {};

  /// Forgets the conversation about [mediaId]. Called when the sheet closes, so
  /// re-opening the photo genuinely starts over rather than silently resuming.
  void endConversation(String mediaId) => _transcripts.remove(mediaId);

  /// How many questions have been asked about [mediaId] so far.
  int turnsUsed(String mediaId) =>
      _transcripts[mediaId]?.where((t) => t.role == AnalysisRole.user).length ??
      0;

  /// Whether the account may analyse right now, for gating the affordance.
  ///
  /// Cheap and synchronous — deliberately NOT the full gate. It answers only
  /// "has this account opted in", which is what decides whether the button is
  /// shown versus whether a tap succeeds. The authoritative check is [analyze].
  bool get consented {
    final uid = _trigger.currentUid;
    return uid != null && _consentUid() == uid;
  }

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

  /// Describes [bytes], or explains why it will not.
  ///
  /// [mediaId] keys the memo only. [isImage] is passed rather than derived so
  /// this file does not need to know the `MediaItem` shape.
  Future<AnalysisOutcome> analyze({
    required String mediaId,
    required Uint8List bytes,
    required String mimeType,
    required bool isImage,
    String? question,
  }) async {
    if (!_available) {
      return const AnalysisOutcome(blocked: AnalysisBlock.unavailable);
    }

    final uid = _trigger.currentUid;
    if (uid == null) {
      return const AnalysisOutcome(blocked: AnalysisBlock.notSignedIn);
    }
    if (_trigger.writesBlocked) {
      final declined = await _trigger.declinedUidOnRecord();
      return AnalysisOutcome(
        blocked: declined == uid
            ? AnalysisBlock.syncDeclined
            : AnalysisBlock.writesBlocked,
      );
    }
    if (await _trigger.declinedUidOnRecord() == uid) {
      return const AnalysisOutcome(blocked: AnalysisBlock.syncDeclined);
    }
    // Broadest of the sync gates, and last of them — see MediaUploadBlock.syncOff.
    if (!await _trigger.isSyncEnabledFor(uid)) {
      return const AnalysisOutcome(blocked: AnalysisBlock.syncOff);
    }
    // Consent is checked AFTER the sync gates so a user who has not turned sync
    // on is told that, rather than being sent to a toggle that would not help.
    // Compared against the CURRENT uid: a consent recorded by another account on
    // this device is not this account's consent.
    if (_consentUid() != uid) {
      return const AnalysisOutcome(blocked: AnalysisBlock.notConsented);
    }
    if (!isImage) {
      return const AnalysisOutcome(blocked: AnalysisBlock.notAnImage);
    }
    if (bytes.length > kMaxAnalysisBytes) {
      return const AnalysisOutcome(blocked: AnalysisBlock.tooLarge);
    }

    final asked = normalizeQuestion(question);
    final history = _transcripts[mediaId] ?? const <AnalysisTurn>[];

    // Bounds one conversation. Checked before the memo because the two are
    // mutually exclusive — the memo only ever answers an empty conversation.
    if (turnsUsed(mediaId) >= kMaxChatTurns) {
      return const AnalysisOutcome(blocked: AnalysisBlock.turnCap);
    }

    if (history.isEmpty) {
      final memoized = _memo['$mediaId|$asked'];
      // Served before the cap is consulted: a repeat view costs nothing, so
      // charging it against the day's allowance would be charging for nothing.
      if (memoized != null) {
        // Seeded so a follow-up after a memo hit still has a referent. Without
        // this, re-opening a photo and asking "and the other one?" would send
        // that phrase with no conversation attached.
        _remember(mediaId, history, asked, memoized);
        return AnalysisOutcome(result: memoized);
      }
    }

    final now = _now();
    final day = analysisDayKey(now);
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
        bytes: bytes,
        mimeType: mimeType,
        question: asked,
        history: history,
      );
    } on AnalysisException catch (e) {
      // The transcript is deliberately NOT extended on a failure. Appending a
      // user turn with no model reply would break the alternation the API
      // expects, and the next question would be sent against a conversation
      // that never happened.
      return AnalysisOutcome(error: e.message);
    } catch (_) {
      // Never surfaces the raw object: it can carry the request, and the
      // request carries the image.
      return const AnalysisOutcome(error: 'Something went wrong. Try again.');
    }

    if (history.isEmpty) _memo['$mediaId|$asked'] = result;
    _remember(mediaId, history, asked, result);
    return AnalysisOutcome(result: result);
  }

  /// Appends one exchange to [mediaId]'s conversation.
  ///
  /// A result with no prose (a classifier backend fills `labels` instead) is not
  /// recorded: there is no model utterance to echo back on the next turn.
  void _remember(
    String mediaId,
    List<AnalysisTurn> history,
    String asked,
    AnalysisResult result,
  ) {
    final prose = result.prose;
    if (prose == null || prose.trim().isEmpty) return;
    _transcripts[mediaId] = <AnalysisTurn>[
      ...history,
      AnalysisTurn.user(asked),
      AnalysisTurn.model(prose),
    ];
  }
}
