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

  /// Whether the Describe action should be rendered at all.
  ///
  /// Requires a loaded file: the bytes ARE the request, so an action offered
  /// before the download finishes would either fail or silently re-download.
  bool get _canDescribe =>
      widget.analyze != null && !_isVideo && _file != null && _error == null;

  Future<void> _describe() async {
    final analyze = widget.analyze;
    final file = _file;
    if (analyze == null || file == null || _analyzing) return;

    // Consent first, and it is a hard gate: nothing is read from disk and no
    // request is built until it passes.
    if (widget.needsConsent?.call() ?? false) {
      final request = widget.requestConsent;
      if (request == null) return;
      final granted = await request(context);
      if (!granted || !mounted) return;
    }

    setState(() => _analyzing = true);
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

    await showAnalysisResultSheet(
      context,
      initialText: prose,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(mediaDateFormat.format(widget.item.capturedAt)),
        actions: [
          if (_canDescribe)
            IconButton(
              key: const Key('media-describe'),
              tooltip: 'Describe',
              icon: _analyzing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              onPressed: _analyzing ? null : _describe,
            ),
        ],
      ),
      body: Center(child: _body()),
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
