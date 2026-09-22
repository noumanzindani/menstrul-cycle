import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../db/database.dart';
import '../../services/media_analysis.dart';
import '../../services/media_analysis_service.dart';
import 'analysis_result_sheet.dart';
import 'media_timeline_screen.dart' show mediaDateFormat;

/// Builds the player for a downloaded file.
///
/// Injected so widget tests never construct a real [VideoPlayerController]. A
/// live controller keeps a platform texture and a ticking position, and ~50
/// test files in this repo call `pumpAndSettle`, which never settles while
/// anything keeps scheduling frames.
typedef VideoControllerFactory = VideoPlayerController Function(File file);

VideoPlayerController _defaultController(File file) =>
    VideoPlayerController.file(file);

/// One item, full screen.
///
/// ## Video keeps playing through the app lock unless this stops it
///
/// `AppLock` sits above the Navigator and hides the app by wrapping it in
/// `Offstage` + `TickerMode(enabled: false)`. That suppresses painting, hit
/// testing and tickers — it does NOT stop a `video_player` texture, and audio
/// is not a ticker. Lock the phone mid-video and a menstrual tracker carries on
/// playing the user's own video out loud from their pocket, which is the same
/// class of harm the `visibility: secret` notification rule exists to prevent.
///
/// So this screen observes the lifecycle itself and pauses on
/// `inactive`/`paused`/`hidden` — the same signal `AppLock` engages on, one
/// step earlier. It deliberately does not read `LockFlag`: that is a plain
/// mutable box precisely so nothing listens to it.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.item,
    required this.load,
    this.controllerFactory = _defaultController,
    this.analyze,
    this.needsConsent,
    this.requestConsent,
    this.endConversation,
    this.messagesLeft,
    this.loadExistingTurns,
    this.earnDescribe,
  });

  final MediaItem item;

  /// Fetches the full-size file, from cache or the network.
  final Future<File> Function(MediaItem item) load;

  final VideoControllerFactory controllerFactory;

  /// Sends the photo out for description. Null hides the action entirely —
  /// the "hidden, not disabled" rule the media entry point itself follows,
  /// and what keeps this absent from any build with no API key compiled in.
  final Future<AnalysisOutcome> Function(
    MediaItem item,
    File file,
    String? question,
  )? analyze;

  /// Whether the account still has to opt in. Read at TAP time rather than at
  /// build time so a consent granted in Settings mid-session takes effect
  /// without this screen having to listen to anything.
  final bool Function()? needsConsent;

  /// Shows the opt-in sheet and records the answer. True = may proceed.
  final Future<bool> Function(BuildContext context)? requestConsent;

  /// Forgets this photo's conversation when the sheet closes, so re-opening it
  /// starts over rather than silently resuming a transcript the user can no
  /// longer see.
  final VoidCallback? endConversation;

  /// How many messages today's cap still allows, read at build time. Null hides
  /// the counter — a display of a budget nobody supplied would be a guess, and
  /// this one costs real money to be wrong about.
  final int Function()? messagesLeft;

  /// Earns the right to make ONE fresh description request -- the rewarded-ad
  /// gate. True = may proceed, false = the user did not earn it and nothing is
  /// sent. Null leaves the action ungated, which is what a premium user and
  /// every test that is not about ads get.
  ///
  /// Shaped exactly like [requestConsent], and injected for the same reason:
  /// AdMob's platform channels have no handler under `flutter_tester`, so a
  /// screen that reached for `AdService` directly could not be widget-tested
  /// at all.
  final Future<bool> Function(BuildContext context)? earnDescribe;

  /// The saved conversation about this photo, if one exists, oldest turn
  /// first. Checked on every Describe tap, before any network call: when this
  /// returns a non-empty list, Describe reopens that conversation instead of
  /// asking the model a brand new opening question and silently starting a
  /// second one about the same picture. Null or an empty list behaves exactly
  /// as before — a fresh description is requested.
  final Future<List<AnalysisTurn>> Function(MediaItem item)? loadExistingTurns;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  File? _file;
  Object? _error;
  bool _analyzing = false;

  bool get _isVideo => widget.item.kind == 'video';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // See the class doc. Pausing on anything that is not `resumed` covers the
      // lock, a phone call, the recents switcher and the notification shade.
      _controller?.pause();
    }
  }

  Future<void> _load() async {
    try {
      final file = await widget.load(widget.item);
      if (!mounted) return;
      if (_isVideo) {
        final controller = widget.controllerFactory(file);
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() {
          _file = file;
          _controller = controller;
        });
      } else {
        setState(() => _file = file);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Whether the Describe action can actually run.
  ///
  /// Requires a loaded file: the bytes ARE the request, so an action offered
  /// before the download finishes would either fail or silently re-download.
  /// The control itself appears one state earlier (see [_showDescribe]) and is
  /// disabled until this holds.
  bool get _canDescribe =>
      widget.analyze != null && !_isVideo && _file != null && _error == null;

  Future<void> _describe() async {
    final analyze = widget.analyze;
    final file = _file;
    if (analyze == null || file == null || _analyzing) return;

    setState(() => _analyzing = true);

    // Checked BEFORE the consent gate AND before any network call. This is a
    // READ of a conversation already stored on this device — see
    // [MediaViewerScreen.loadExistingTurns]'s doc comment — and reading it
    // sends nothing anywhere. Consent governs SENDING, so a resumed,
    // read-only reopen must not be blocked by a revoked or missing consent;
    // conflating "may I read what I already have" with "may I send more" is
    // exactly the bug this ordering avoids. A follow-up typed into the
    // reopened sheet is a SEND, and remains fully gated: it goes through
    // [analyze] below, and `MediaAnalysisService.analyze` enforces its own
    // consent check regardless of anything decided here.
    final existing = await _loadExisting();
    if (!mounted) return;
    if (existing.isNotEmpty) {
      setState(() => _analyzing = false);
      await _openSheet(analyze, file, initialTurns: existing);
      return;
    }

    // Consent next, and it is a hard gate for every path below: nothing is
    // read from disk and no request is built until it passes. Reached only
    // once no resumable conversation was found — from here on every path may
    // reach the network.
    if (widget.needsConsent?.call() ?? false) {
      final request = widget.requestConsent;
      if (request == null) {
        setState(() => _analyzing = false);
        return;
      }
      final granted = await request(context);
      if (!mounted) return;
      if (!granted) {
        setState(() => _analyzing = false);
        return;
      }
    }

    // The rewarded-ad gate, and its position is the whole design.
    //
    // AFTER the resume check above: reopening a stored conversation sends
    // nothing and costs no API call, so there is nothing for an ad to offset
    // and charging one would be a pure toll on the user's own saved text.
    //
    // AFTER consent: the other order makes someone watch a full ad and THEN
    // meet a sheet they decline -- a reward taken and never delivered, which
    // is an AdMob policy problem before it is a UX one.
    //
    // BEFORE `analyze`: this is the call that costs real money, and it is the
    // one the ad exists to pay for.
    final earn = widget.earnDescribe;
    if (earn != null) {
      final earned = await earn(context);
      if (!mounted) return;
      if (!earned) {
        setState(() => _analyzing = false);
        return;
      }
    }

    final outcome = await analyze(widget.item, file, null);
    if (!mounted) return;
    setState(() => _analyzing = false);

    final blocked = outcome.blocked;
    if (blocked != null) {
      _say(messageForAnalysisBlock(blocked));
      return;
    }
    final error = outcome.error;
    if (error != null) {
      _say(error);
      return;
    }
    final prose = outcome.result?.prose;
    if (prose == null || prose.trim().isEmpty) {
      _say('No description came back for this photo.');
      return;
    }

    await _openSheet(analyze, file, initialText: prose);
  }

  /// Reads the stored conversation for this photo, if [MediaViewerScreen.
  /// loadExistingTurns] was given one. A lookup failure reads the same as "no
  /// saved conversation" — Describe simply falls through to asking the model
  /// fresh, rather than getting stuck on a database error the user cannot act
  /// on.
  Future<List<AnalysisTurn>> _loadExisting() async {
    final load = widget.loadExistingTurns;
    if (load == null) return const [];
    try {
      return await load(widget.item);
    } catch (_) {
      return const [];
    }
  }

  /// Opens the conversation sheet, either freshly seeded from [initialText]
  /// (a new description just came back) or hydrated from [initialTurns] (an
  /// existing session is being resumed). Exactly one of the two is meaningful
  /// per call; [showAnalysisResultSheet] itself ignores [initialText]
  /// whenever [initialTurns] is non-empty.
  Future<void> _openSheet(
    Future<AnalysisOutcome> Function(MediaItem, File, String?) analyze,
    File file, {
    String? initialText,
    List<AnalysisTurn> initialTurns = const [],
  }) {
    return showAnalysisResultSheet(
      context,
      initialText: initialText ?? '',
      initialTurns: initialTurns,
      // The sheet sits over the photo but does not show it: at 80% height the
      // top-left thumbnail is the only thing that says which picture the
      // answer is about.
      title: mediaDateFormat.format(widget.item.capturedAt),
      thumbnail: widget.item.thumbnail,
      messagesLeft: widget.messagesLeft,
      onClosed: widget.endConversation,
      onAsk: (question) async {
        final next = await analyze(widget.item, file, question);
        final nextBlock = next.blocked;
        if (nextBlock != null) {
          return AnalysisSheetReply(
            messageForAnalysisBlock(nextBlock),
            isError: true,
          );
        }
        if (next.error != null) {
          return AnalysisSheetReply(next.error!, isError: true);
        }
        final text = next.result?.prose;
        if (text == null || text.trim().isEmpty) {
          return const AnalysisSheetReply(
            'No description came back for this photo.',
            isError: true,
          );
        }
        return AnalysisSheetReply(text);
      },
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Whether the Describe control belongs on screen at all.
  ///
  /// Wider than [_canDescribe] by exactly one state — the download — so the
  /// action does not pop into existence a second after the photo does. When the
  /// feature is absent (no key, or a video) there is no bar at all: hidden, not
  /// disabled, the same rule the media entry point itself follows.
  bool get _showDescribe =>
      widget.analyze != null && !_isVideo && _error == null;

  @override
  Widget build(BuildContext context) {
    // Full-bleed black in BOTH themes, and the one place in this app that is
    // right: a photograph is judged against its surround, and a light frame
    // tints everything inside it. The chrome over it is translucent so the
    // image keeps the whole screen.
    const scrim = Color(0xCC000000);
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: scrim,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          mediaDateFormat.format(widget.item.capturedAt),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ),
      body: Center(child: _body()),
      bottomNavigationBar: !_showDescribe
          ? null
          : Container(
              color: scrim,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: OutlinedButton.icon(
                    key: const Key('media-describe'),
                    // Labelled, not a lone sparkle in the app bar. This action
                    // sends the photograph to a third party; an icon nobody can
                    // name is not the affordance for that.
                    onPressed: _analyzing || !_canDescribe ? null : _describe,
                    icon: _analyzing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Describe'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white38,
                      side: const BorderSide(color: Colors.white70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          "This one couldn't be loaded. It may have been deleted from another "
          'device.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    final file = _file;
    if (file == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    final controller = _controller;
    if (_isVideo) {
      if (controller == null) {
        return const CircularProgressIndicator(color: Colors.white);
      }
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            IconButton(
              iconSize: 64,
              color: Colors.white70,
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
              ),
              onPressed: () => setState(
                () => controller.value.isPlaying
                    ? controller.pause()
                    : controller.play(),
              ),
            ),
          ],
        ),
      );
    }
    return InteractiveViewer(
      child: Image.file(
        file,
        fit: BoxFit.contain,
        // Bounded decode. A 12MP original at full resolution is ~48 MB of
        // raster; on a 1GB Android 8 device that alone can be fatal.
        cacheWidth: 2048,
      ),
    );
  }
}
