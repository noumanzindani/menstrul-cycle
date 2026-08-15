import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/media_repository.dart';
import '../../db/database.dart';
import '../../providers/media_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/device_id.dart';
import '../../services/firebase_availability.dart';
import '../../services/firestore_ref.dart';
import '../../services/media_analysis_service.dart';
import '../../services/media_analyzer.dart';
import '../../services/media_blob_store.dart';
import '../../services/media_cache.dart';
import '../../services/media_limits.dart';
import '../../services/media_sync_service.dart';
import '../../services/media_thumbnailer.dart';
import '../../services/media_upload_service.dart';
import '../../services/sync_trigger.dart';
import 'analysis_consent_sheet.dart';
import 'media_timeline_screen.dart';
import 'media_viewer_screen.dart';

/// Builds the media timeline with its real dependencies wired up.
///
/// All the Firebase-touching construction lives HERE rather than in the screen,
/// so the screen itself stays a plain widget over `MediaProvider` that widget
/// tests can pump with no Firebase app. Everything below is only ever reached
/// from a live app.
///
/// Whether media is reachable at all is [FirebaseAvailability]: the entry point
/// is hidden when there is no Firebase, because a cloud-only feature with no
/// cloud is a dead end, not a degraded one.
Route<void> mediaTimelineRoute(BuildContext context) {
  final available = context.read<FirebaseAvailability>().available;
  final db = context.read<AppDatabase>();
  final trigger = context.read<SyncTrigger>();
  final provider = context.read<MediaProvider>();
  final repo = MediaRepository(db);
  final cache = MediaCache();

  final blobs =
      available ? FirebaseMediaBlobStore() : const UnavailableMediaBlobStore();

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

  final uploader = MediaUploadService(
    repo: repo,
    blobStore: blobs,
    thumbnailer: MediaThumbnailer(),
    firestore: lunaFirestore,
    trigger: trigger,
    deviceId: DeviceId.get,
  );

  // Photo descriptions. Gated on a compiled-in key as well as on Firebase:
  // with no key there is no backend, so the action is hidden rather than shown
  // and failing. `settings` is captured once and its fields read lazily, so a
  // consent granted in Settings mid-session is seen without this route
  // listening to anything.
  final settings = context.read<SettingsProvider>();
  final canAnalyze = available && analysisAvailable;
  final analysisService = MediaAnalysisService(
    analyzer: canAnalyze ? GeminiMediaAnalyzer() : const UnavailableMediaAnalyzer(),
    trigger: trigger,
    consentUid: () => settings.analysisConsentUid,
    readUsage: () => (
      day: settings.analysisCountDay,
      count: settings.analysisCountToday,
    ),
    writeUsage: settings.recordAnalysisUsage,
    available: canAnalyze,
  );

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
        onAdd: !available ? null : () => _pickAndUpload(uploader),
        onOpen: (context, item) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MediaViewerScreen(
              item: item,
              load: (item) => _loadFile(item, cache, blobs),
              analyze: !canAnalyze
                  ? null
                  : (item, file, question) async => analysisService.analyze(
                        mediaId: item.id,
                        bytes: await file.readAsBytes(),
                        mimeType: _guessContentType(item.storagePath),
                        isImage: item.kind == 'image',
                        question: question,
                      ),
              needsConsent: () => !analysisService.consented,
              endConversation: () => analysisService.endConversation(item.id),
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
/// interaction, and on Android 13+ it delegates to the system Photo Picker —
/// which grants a per-item read and needs no media permission. That matters
/// beyond convenience: Play restricts `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` to
/// apps whose core purpose is photo/video, which a period tracker is not, so
/// the picker route is the only compliant one.
Future<MediaUploadOutcome> _pickAndUpload(MediaUploadService uploader) async {
  final picker = ImagePicker();
  final files = await picker.pickMultipleMedia(
    limit: kMaxItemsPerPick,
    // Downscale images in the plugin, before we ever hold them: a phone photo
    // lands at a few hundred KB instead of several MB, which is the real
    // control on upload size. Videos are unaffected — there is no transcoding.
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 85,
  );
  if (files.isEmpty) return const MediaUploadOutcome();

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
  return uploader.upload(picked);
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
