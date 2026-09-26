import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/analysis_session_repository.dart';
import '../../data/media_repository.dart';
import '../../db/database.dart';
import '../../providers/log_provider.dart';
import '../../providers/media_provider.dart';
import '../../providers/medication_provider.dart';
import '../../providers/premium_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/prediction.dart';
import '../../services/device_id.dart';
import '../../services/firebase_availability.dart';
import '../../services/firestore_ref.dart';
import '../../services/health_context.dart';
import '../../services/media_analysis_service.dart';
import '../../services/media_analyzer.dart';
import '../../services/ad_service.dart';
import '../../services/rewarded_describe_gate.dart';
import 'rewarded_describe_prompt.dart';
import '../../services/media_blob_store.dart';
import '../../services/media_cache.dart';
import '../../services/media_limits.dart';
import '../../services/media_picker_config.dart';
import '../../services/picker_temp_cache.dart';
import '../../services/media_sync_service.dart';
import '../../services/media_thumbnailer.dart';
import '../../services/media_upload_service.dart';
import '../../services/pexels_client.dart';
import '../../services/sync_trigger.dart';
import '../assistant/assistant_chat_screen.dart';
import '../assistant/assistant_screen.dart';
import '../assistant/live_assistant_backend.dart';
import '../assistant/reply_image_resolver.dart';
import 'analysis_consent_sheet.dart';
import 'media_timeline_screen.dart';
import 'media_viewer_screen.dart';

/// The media and assistant plumbing, built ONCE for the app's life and
/// provided from `main.dart`.
///
/// All the Firebase-touching construction lives HERE rather than in the
/// screens, so the screens themselves stay plain widgets that widget tests can
/// pump with no Firebase app. Everything below is only ever reached from a
/// live app — the provider is lazy, so a test that never opens media or the
/// assistant never builds it.
///
/// One instance, not one per route, for two reasons. The analysis service's
/// memo, caps and in-memory conversations must be shared by the Assistant and
/// Describe. And there must be ONE uploader: `MediaSyncService.sweepOrphans`
/// skips only the uploads [uploader] knows are in flight, so a photo the
/// assistant is still uploading through a second uploader could be swept as
/// an orphan by a refresh of the timeline.
class MediaWiring {
  MediaWiring._({
    required this.available,
    required this.repo,
    required this.cache,
    required this.blobs,
    required this.uploader,
    required this.sessions,
    required this.assistant,
  });

  /// Reads every dependency from [context], which must sit below the
  /// providers `main.dart` declares before this one. [context] is kept for
  /// the health context, which is gathered at SEND time so it is current.
  factory MediaWiring.fromContext(BuildContext context) {
    final available = context.read<FirebaseAvailability>().available;
    final db = context.read<AppDatabase>();
    final trigger = context.read<SyncTrigger>();
    final settings = context.read<SettingsProvider>();
    final premium = context.read<PremiumProvider>();
    final mediaProvider = context.read<MediaProvider>();
    final logProvider = context.read<LogProvider>();
    final medicationProvider = context.read<MedicationProvider>();

    final repo = MediaRepository(db);
    final cache = MediaCache();
    final MediaBlobStore blobs =
        available ? FirebaseMediaBlobStore() : const UnavailableMediaBlobStore();
    final uploader = MediaUploadService(
      repo: repo,
      blobStore: blobs,
      thumbnailer: MediaThumbnailer(),
      firestore: lunaFirestore,
      trigger: trigger,
      deviceId: DeviceId.get,
    );
    final sessions = AnalysisSessionRepository(db);
    // Gated on a compiled-in key as well as on Firebase: with no key there is
    // no backend, so the assistant shows its unavailable state rather than a
    // chat that could only fail.
    final canAnalyze = available && analysisAvailable;

    final pexels = PexelsClient();
    final assistant = LiveAssistantBackend(
      available: canAnalyze,
      replyImages: ReplyImageResolver(
        search: pexels.searchTop,
        enabled: canAnalyze && pexels.available,
      ),
      service: (persistTurn) => MediaAnalysisService(
        analyzer:
            canAnalyze ? GeminiMediaAnalyzer() : const UnavailableMediaAnalyzer(),
        trigger: trigger,
        // `settings` is captured once and its fields read lazily, so a consent
        // granted in Settings mid-session is seen without listening to
        // anything.
        consentUid: () => settings.analysisConsentUid,
        consentVersion: () => settings.analysisConsentVersion,
        readUsage: () => (
          day: settings.analysisCountDay,
          count: settings.analysisCountToday,
        ),
        writeUsage: settings.recordAnalysisUsage,
        persistTurn: persistTurn,
        available: canAnalyze,
      ),
      sessions: sessions,
      currentUid: () => trigger.currentUid,
      loadMedia: repo.byId,
      libraryFor: repo.allFor,
      loadOriginal: (item) async {
        final file = await _loadFile(item, cache, blobs);
        return (await file.readAsBytes(), _guessContentType(item.storagePath));
      },
      // Assembled HERE, from providers, and handed over as an opaque string:
      // the analysis service may not read these providers (or the database
      // behind them) at all — see `buildHealthContext`'s doc comment.
      healthContext: () {
        final appSettings = settings.settings;
        if (appSettings == null) return null;
        return buildHealthContext(
          logs: logProvider.logs,
          cycles: logProvider.cycles,
          prediction: context.read<PredictionResult?>(),
          medications: medicationProvider.items,
          settings: appSettings,
          asOf: DateTime.now(),
        );
      },
      syncOn: trigger.isSyncEnabledFor,
      pickAndUpload: !available
          ? null
          : (source, {limit}) =>
              pickAndUploadMedia(uploader, source, limit: limit),
      requestConsent: (context) async {
        final allowed = await showAnalysisConsentSheet(context);
        if (allowed != true) return false;
        final uid = trigger.currentUid;
        if (uid == null) return false;
        // Recorded against the UID that is signed in RIGHT NOW, read after
        // the sheet rather than before it: the account can change while a
        // modal is open, and consent belongs to whoever gave it.
        await settings.setAnalysisConsent(uid);
        return true;
      },
      // Premium is read at TAP time, not captured: a purchase completing
      // mid-session must stop the ads immediately.
      earnConversation: (context) => earnOneConversation(
        premium: premium.isPremium,
        confirm: () => showRewardedDescribePrompt(context),
        showAd: () => AdService.instance.showRewarded(premium: premium.isPremium),
      ),
      // So a photo taken in the assistant shows up in Photos & videos.
      onMediaAdded: mediaProvider.reload,
      // A sync writes pulled conversations straight to the database; this is
      // what tells the Assistant list to re-read them.
      remoteChanges: trigger.syncs,
    );

    return MediaWiring._(
      available: available,
      repo: repo,
      cache: cache,
      blobs: blobs,
      uploader: uploader,
      sessions: sessions,
      assistant: assistant,
    );
  }

  /// Whether Firebase is up. See [FirebaseAvailability].
  final bool available;
  final MediaRepository repo;
  final MediaCache cache;
  final MediaBlobStore blobs;
  final MediaUploadService uploader;
  final AnalysisSessionRepository sessions;
  final LiveAssistantBackend assistant;
}

/// Builds the media timeline over the app-wide [MediaWiring].
///
/// Whether media is reachable at all is [FirebaseAvailability]: the entry point
/// is hidden when there is no Firebase, because a cloud-only feature with no
/// cloud is a dead end, not a degraded one.
Route<void> mediaTimelineRoute(BuildContext context) {
  final wiring = context.read<MediaWiring>();
  final available = wiring.available;
  final trigger = context.read<SyncTrigger>();
  final provider = context.read<MediaProvider>();
  final repo = wiring.repo;
  final cache = wiring.cache;
  final blobs = wiring.blobs;
  final uploader = wiring.uploader;
  final assistant = wiring.assistant;

  MediaSyncService? syncFor(String uid, String deviceId) => available
      ? MediaSyncService(
          repo: repo,
          blobStore: blobs,
          firestore: lunaFirestore(),
          uid: uid,
          deviceId: deviceId,
          evictCache: cache.evict,
          // A deleted photo must stop riding along in a live conversation.
          onDeleted: assistant.forgetMedia,
        )
      : null;

  // Hidden rather than shown and failing when there is no key, no Firebase
  // or no account — the assistant's own notion of available.
  final canAnalyze = assistant.available;

  // Opens one item full-screen, from a grid tile. Describe on it opens the
  // assistant: resuming the conversation that started from this photo, or
  // starting one that sends the photo with the default question.
  void openViewer(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaViewerScreen(
          item: item,
          load: (item) => _loadFile(item, cache, blobs),
          openConversation: !canAnalyze
              ? null
              : (context, {conversationId, attach}) =>
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => AssistantChatScreen(
                      backend: assistant,
                      conversationId: conversationId,
                      pendingAttachments: [?attach],
                      // The viewer ran consent and the ad before opening a
                      // new conversation. A resumed one decides from its own
                      // transcript whether it has ever billed.
                      adEarned: attach != null,
                    ),
                  )),
          // Looked up fresh on every Describe tap rather than once here: a
          // conversation can be created (or, via `deleteForMedia`, removed)
          // while this viewer is already open.
          findConversation: (item) => assistant.conversationForMedia(item.id),
          // Re-read at TAP time, so consent granted in Settings mid-session
          // and a purchase completing mid-session both take effect at once.
          needsConsent: () => assistant.needsConsent,
          requestConsent: assistant.requestConsent,
          earnDescribe: assistant.earnConversation,
          preflight: (item) => assistant.preflight(attachments: [item]),
        ),
      ),
    );
  }

  return MaterialPageRoute<void>(
    builder: (_) => ChangeNotifierProvider<MediaProvider>.value(
      // Re-provided for the same reason `DayEntrySheet` re-provides
      // LogProvider: a route builds from the navigator's context, which in
      // tests sits above the pumped providers.
      value: provider,
      child: MediaTimelineScreen(
        onRefresh: !available
            ? null
            : () async {
                final uid = trigger.currentUid;
                if (uid == null) return;
                final sync = syncFor(uid, await DeviceId.get())!;
                await sync.pull();
                await sync.hydrateThumbnails();
                // Opportunistic, and last: it is the only step whose failure
                // costs nothing.
                await sync.sweepOrphans(skipIds: uploader.inFlightIds);
              },
        onAdd: !available
            ? null
            : (source) => pickAndUploadMedia(uploader, source),
        onOpen: openViewer,
        // The assistant's conversation list, which now holds every saved
        // photo description as well. Gated on the same thing the assistant
        // itself is, so a build with no key offers nothing here to browse.
        onOpenSessions: !canAnalyze
            ? null
            : (context) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AssistantScreen(backend: assistant),
                  ),
                ),
      ),
    ),
  );
}

/// Fetches an item's full-size bytes, from the cache when possible.
Future<File> _loadFile(
  MediaItem item,
  MediaCache cache,
  MediaBlobStore blobs,
) async {
  final file = await cache.fileFor(item.id, item.storagePath);
  if (await file.exists() && await file.length() > 0) return file;
  await blobs.downloadToFile(item.storagePath, file);
  // Trimmed AFTER the write so the file just fetched is the newest and cannot
  // be the one evicted.
  if (cache.canHold(item.bytes)) {
    await cache.trim();
  }
  return file;
}

/// Opens the system picker and uploads what comes back.
///
/// `pickMultipleMedia` is the only API that returns images AND videos from one
/// interaction, and once [useSystemPhotoPicker] has run it delegates to the
/// system Photo Picker — which grants a per-item read and needs no media
/// permission. That matters beyond convenience: Play restricts
/// `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` to apps whose core purpose is
/// photo/video, which a period tracker is not, so the picker route is the only
/// compliant one.
///
/// The configuration is applied HERE, next to the only picker in the app,
/// rather than at startup: it is idempotent, it costs a type test, and a
/// structural test in `media_picker_config_test.dart` fails if a second entry
/// point ever constructs a picker without it.
///
/// Exported for the assistant's composer, which attaches new photos by
/// uploading them to Photos & videos first — this stays the ONE place an
/// `ImagePicker` is constructed (`media_guardrails_test.dart` counts them).
/// [limit] caps a library pick below [kMaxItemsPerPick]; a limit of one uses
/// the single-item picker, because the multi-item one refuses a limit under
/// two.
Future<MediaUploadOutcome> pickAndUploadMedia(
  MediaUploadService uploader,
  MediaSource source, {
  int? limit,
}) async {
  final pickLimit = (limit ?? kMaxItemsPerPick).clamp(1, kMaxItemsPerPick);
  // Runs for capture too, not only for library picks. The configuration is
  // per-platform-instance rather than per-call, and a capture path that skipped
  // it would leave the flag unset for whichever call came next.
  useSystemPhotoPicker();
  final picker = ImagePicker();
  // Downscaling happens in the plugin, before we ever hold the bytes: a phone
  // photo lands at a few hundred KB instead of several MB, which is the real
  // control on upload size. Videos are unaffected — there is no transcoding,
  // and the duration cap is what bounds them instead.
  final files = switch (source) {
    MediaSource.library when pickLimit == 1 => [
        ?await picker.pickMedia(
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
        ),
      ],
    MediaSource.library => await picker.pickMultipleMedia(
        limit: pickLimit,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      ),
    // Capture returns ONE item or none — the system camera app takes one thing
    // at a time — so both branches normalise to a list rather than making the
    // shared pipeline below care which source it came from.
    MediaSource.camera => [
        ?await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
        ),
      ],
    MediaSource.videoCamera => [
        ?await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: kMaxVideoDuration,
        ),
      ],
  };
  if (files.isEmpty) return const MediaUploadOutcome();

  try {
    final picked = <PickedMedia>[];
    for (final xfile in files) {
      final contentType = xfile.mimeType ?? _guessContentType(xfile.path);
      final kind = mediaKindFor(contentType);
      Duration? duration;
      if (kind == MediaKind.video) {
        duration = await _probeDuration(File(xfile.path));
      }
      picked.add(PickedMedia(
        file: File(xfile.path),
        contentType: contentType,
        duration: duration,
        capturedAt: await _capturedAt(xfile),
      ));
    }
    // `return await`, not a bare `return uploader.upload(picked)`. In an async
    // function `finally` runs when control leaves the try — which, for a
    // returned-but-unawaited future, is BEFORE the upload has read a byte. The
    // sweep would delete the files out from under it.
    return await uploader.upload(picked);
  } finally {
    try {
      await sweepPickerTempFiles();
    } catch (_) {
      // Cache hygiene must not mask an upload error, nor turn a successful
      // upload into a thrown one. The startup sweep gets it next launch.
    }
  }
}

/// Reads a video's length from its container header.
///
/// This is how the duration cap is enforced with no transcoding library: an
/// `initialize()` is a header read, not a decode. Bounded by a timeout because
/// a malformed file can hang it indefinitely, and a picker that never returns
/// is worse than a refused file. Null means "unreadable", which the caps treat
/// as a refusal — an unenforceable cap is not a cap.
Future<Duration?> _probeDuration(File file) async {
  VideoPlayerController? controller;
  try {
    controller = VideoPlayerController.file(file);
    await controller.initialize().timeout(const Duration(seconds: 5));
    return controller.value.duration;
  } catch (_) {
    return null;
  } finally {
    // Always: an initialized controller holds a platform texture.
    await controller?.dispose();
  }
}

Future<DateTime?> _capturedAt(XFile file) async {
  try {
    return await file.lastModified();
  } catch (_) {
    return null;
  }
}

String _guessContentType(String path) {
  final ext = path.split('.').last.toLowerCase();
  for (final entry in {...kAllowedImageTypes, ...kAllowedVideoTypes}.entries) {
    if (entry.value == ext) return entry.key;
  }
  // Deliberately not a fallback to something acceptable: an unknown extension
  // must reach the caps as unsupported and be refused there, in one place.
  return 'application/octet-stream';
}

/// The Calendar app-bar action that reaches the timeline.
///
/// Lives beside the Diary action for the same reason the Diary does: the bottom
/// nav is already at Material's five-destination ceiling, and adding a sixth
/// would also silently re-target `AppShell`'s interstitial, which fires on
/// index 0.
class MediaAppBarAction extends StatelessWidget {
  const MediaAppBarAction({super.key});

  @override
  Widget build(BuildContext context) {
    // Hidden, not disabled: a cloud-only feature with no cloud has nothing to
    // offer, and an always-greyed button invites the question forever.
    //
    // Read as NULLABLE on purpose. An absent provider means the same thing an
    // unavailable one does — there is no cloud here — and it keeps every
    // existing Calendar test harness from having to learn that media exists
    // just to pump the screen. `main.dart` always supplies the real value.
    final availability = context.read<FirebaseAvailability?>();
    if (availability == null || !availability.available) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Photos & videos',
      icon: const Icon(Icons.photo_library_outlined),
      onPressed: () => Navigator.of(context).push(mediaTimelineRoute(context)),
    );
  }
}
