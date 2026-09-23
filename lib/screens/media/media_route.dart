import 'dart:convert';
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
import '../../services/media_analysis.dart';
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
import '../../services/sync_trigger.dart';
import '../assistant/assistant_screen.dart';
import '../assistant/live_assistant_backend.dart';
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

    final assistant = LiveAssistantBackend(
      available: canAnalyze,
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
        )
      : null;

  // Photo descriptions. Gated on a compiled-in key as well as on Firebase:
  // with no key there is no backend, so the action is hidden rather than shown
  // and failing. `settings` is captured once and its fields read lazily, so a
  // consent granted in Settings mid-session is seen without this route
  // listening to anything.
  final settings = context.read<SettingsProvider>();
  // Read here with every other provider, NOT inside the viewer: the gate is
  // handed down as a callback so the screen never reaches for AdMob itself.
  final premium = context.read<PremiumProvider>();
  final canAnalyze = available && analysisAvailable;

  final sessionRepo = wiring.sessions;

  // Persists one errorless exchange, resuming the existing session for this
  // mediaId when there is one rather than starting a second conversation
  // about the same photo. Handed to MediaAnalysisService as an opaque
  // callback: that class must never import AnalysisSessionRepository or
  // AppDatabase itself (test/media_guardrails_test.dart enforces it), so the
  // find-or-create logic lives here, where the database already is.
  //
  // [isMemoHit] (see MediaAnalysisService._persistTurn's doc comment) is
  // where the duplicate-turn defect lived: a memo hit re-serves an answer
  // already shown once before, and `AnalysisSessionRepository.append` is a
  // pure insert with no dedup, so persisting it again would insert an exact
  // duplicate pair into a session that already holds it. The live transcript
  // never repeats that exchange, so the saved one must not either — hence
  // the early return below whenever a session already exists. The one case
  // that must still persist a memo hit is when NO session exists yet (it was
  // deleted independently of the in-memory memo, e.g. by `deleteForMedia`):
  // skipping there would leave a later follow-up with no opening turn to
  // attach to, which is a worse transcript than a duplicated one.
  //
  // A Describe conversation's id IS its photo's media id, which is what
  // `forMedia` looks the session up by.
  Future<void> persistAnalysisTurn({
    required String conversationId,
    required String question,
    required List<AttachmentRef> attachments,
    required String answer,
    required bool isMemoHit,
  }) async {
    final uid = trigger.currentUid;
    if (uid == null) return;
    final mediaId = conversationId;
    final existing =
        await sessionRepo.forMedia(uid: uid, mediaId: mediaId);
    if (isMemoHit && existing != null) return;
    final session = existing ??
        await sessionRepo.create(
          uid: uid,
          mediaId: mediaId,
          consentVersion: kCurrentConsentVersion,
        );
    await sessionRepo.append(
      sessionId: session.id,
      role: 'user',
      text: question,
      attachments: attachments,
    );
    await sessionRepo.append(
      sessionId: session.id,
      role: 'model',
      text: answer,
    );
  }

  final analysisService = MediaAnalysisService(
    analyzer: canAnalyze ? GeminiMediaAnalyzer() : const UnavailableMediaAnalyzer(),
    trigger: trigger,
    consentUid: () => settings.analysisConsentUid,
    consentVersion: () => settings.analysisConsentVersion,
    readUsage: () => (
      day: settings.analysisCountDay,
      count: settings.analysisCountToday,
    ),
    writeUsage: settings.recordAnalysisUsage,
    persistTurn: persistAnalysisTurn,
    available: canAnalyze,
  );

  // Opens one item full-screen, from a grid tile.
  void openViewer(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaViewerScreen(
          item: item,
          load: (item) => _loadFile(item, cache, blobs),
          analyze: !canAnalyze
              ? null
              : (item, file, question) async {
                  // Gathered from providers BEFORE the async gap, so no
                  // BuildContext is used across an await — mirrors
                  // insights_screen.dart:79-99's PDF export. The service
                  // itself may not read these providers (or the database
                  // behind them) at all; assembling the context is this
                  // caller's job precisely so it stays that way.
                  final logProvider = context.read<LogProvider>();
                  final medicationProvider =
                      context.read<MedicationProvider>();
                  final prediction = context.read<PredictionResult?>();
                  final appSettings = settings.settings;
                  final healthContext = appSettings == null
                      ? null
                      : buildHealthContext(
                          logs: logProvider.logs,
                          cycles: logProvider.cycles,
                          prediction: prediction,
                          medications: medicationProvider.items,
                          settings: appSettings,
                          asOf: DateTime.now(),
                        );
                  if (item.kind != 'image') {
                    return analysisService.analyze(
                      conversationId: item.id,
                      attachments: [AnalysisAttachment.video(item.id)],
                      question: question,
                      healthContext: healthContext,
                    );
                  }
                  final bytes = await file.readAsBytes();
                  final mimeType = _guessContentType(item.storagePath);
                  // The photo rides the opening turn only; after that it is
                  // resent from the service's own copy. A resumed
                  // conversation already names it on its first turn (see
                  // `loadExistingTurns` below), so only its bytes are handed
                  // over, never a second attachment.
                  if (analysisService.turnsUsed(item.id) == 0) {
                    return analysisService.analyze(
                      conversationId: item.id,
                      attachments: [
                        AnalysisAttachment.image(
                          mediaId: item.id,
                          mimeType: mimeType,
                          bytes: bytes,
                        ),
                      ],
                      question: question,
                      healthContext: healthContext,
                    );
                  }
                  analysisService.seedConversation(
                    item.id,
                    const [],
                    images: {
                      item.id: InlineImage(
                        mimeType: mimeType,
                        base64: base64Encode(bytes),
                      ),
                    },
                  );
                  return analysisService.analyze(
                    conversationId: item.id,
                    question: question,
                    healthContext: healthContext,
                  );
                },
          // The rewarded-ad gate. Premium is read at TAP time, not captured
          // here: a purchase completing while this viewer is open must stop
          // the ads immediately, the same way `needsConsent` re-reads consent
          // rather than snapshotting it.
          earnDescribe: !canAnalyze
              ? null
              : (context) => earnOneConversation(
                    premium: premium.isPremium,
                    confirm: () => showRewardedDescribePrompt(context),
                    showAd: () =>
                        AdService.instance.showRewarded(premium: premium.isPremium),
                  ),
          needsConsent: () => !analysisService.consented,
          endConversation: () => analysisService.endConversation(item.id),
          // Display only, and computed from the SAME pure helper the
          // service counts with — a second reading of "how many are left"
          // is a second place for it to be wrong. Read lazily, so it is
          // current every time the sheet rebuilds.
          messagesLeft: !canAnalyze
              ? null
              : () {
                  final used = analysisCountForDay(
                    storedDay: settings.analysisCountDay,
                    storedCount: settings.analysisCountToday,
                    now: DateTime.now(),
                  );
                  final left = kMaxAnalysesPerDay - used;
                  return left < 0 ? 0 : left;
                },
          // Looked up fresh on every Describe tap rather than once here: a
          // conversation can be created (or, via `deleteForMedia`, removed)
          // while this viewer is already open.
          loadExistingTurns: !canAnalyze
              ? null
              : (item) async {
                  final uid = trigger.currentUid;
                  if (uid == null) return const <AnalysisTurn>[];
                  final session =
                      await sessionRepo.forMedia(uid: uid, mediaId: item.id);
                  if (session == null) return const <AnalysisTurn>[];
                  final messages = await sessionRepo.messagesFor(session.id);
                  // A v15 session stored no attachments; its photo is the
                  // session's, on the first user turn — `effectiveAttachments`
                  // restores that reading.
                  final refs = effectiveAttachments(session.mediaId, [
                    for (final m in messages)
                      (role: m.role, attachmentsJson: m.attachmentsJson),
                  ]);
                  // includeInModel is carried over, not filtered here: the
                  // sheet still shows such a turn, and the request builder
                  // is what leaves it out of what the model sees.
                  final turns = [
                    for (var i = 0; i < messages.length; i++)
                      messages[i].role == 'user'
                          ? AnalysisTurn.user(messages[i].messageText,
                              attachments: refs[i],
                              includeInModel: messages[i].includeInModel)
                          : AnalysisTurn.model(messages[i].messageText,
                              attachments: refs[i],
                              includeInModel: messages[i].includeInModel),
                  ];
                  // Seeds the SERVICE's in-memory history, not just the UI:
                  // the sheet renders these turns from the return value below,
                  // but the next follow-up goes through `analysisService`
                  // (captured above), whose `_transcripts` map is the only
                  // thing `analyze()` reads for context. Without this call a
                  // resumed conversation would show old turns on screen while
                  // the model itself remembers none of them. See
                  // `MediaAnalysisService.seedConversation`'s doc comment.
                  analysisService.seedConversation(item.id, turns);
                  return turns;
                },
          requestConsent: (context) async {
            final allowed = await showAnalysisConsentSheet(context);
            if (allowed != true) return false;
            final uid = trigger.currentUid;
            if (uid == null) return false;
            // Recorded against the UID that is signed in RIGHT NOW, read
            // after the sheet rather than before it: the account can change
            // while a modal is open, and consent belongs to whoever gave it.
            await settings.setAnalysisConsent(uid);
            return true;
          },
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
