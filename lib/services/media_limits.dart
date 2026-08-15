/// What LunaTrack will accept into the media timeline, and why each limit
/// exists. Pure: no I/O, no Flutter imports, no plugin calls — so the rules a
/// user actually hits are the rules the test suite checks.
///
/// ## Caps are a REFUSAL, not a clamp
///
/// The same ruling as the change-timer stepper: when a file exceeds a limit the
/// picker says so and skips that file. It never silently truncates, re-encodes
/// or "fixes" it. There is no transcoding anywhere in this feature (the
/// ffmpeg_kit Flutter wrapper was retired in 2025), so a clamp is not even
/// available — which makes an honest refusal the only correct behaviour.
///
/// ## These caps are UX, not enforcement
///
/// The API key ships inside the APK, so a client-side limit governs only this
/// app's behaviour. `storage.rules` carries the same numbers as
/// `request.resource.size` assertions and is what actually enforces them. If
/// you change a number here, change it there in the same commit or the two
/// disagree and users hit an unexplained server rejection.
library;

/// The kinds of media the timeline holds.
enum MediaKind { image, video }

/// Accepted image content types → the extension used in the object path.
///
/// heic/heif are included because they are the iPhone camera default; an
/// allowlist without them rejects most real uploads from iOS.
const Map<String, String> kAllowedImageTypes = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'image/heif': 'heif',
};

/// Accepted video content types → extension.
const Map<String, String> kAllowedVideoTypes = {
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
};

/// Largest single image, in bytes.
///
/// In practice unreachable: the picker is asked to downscale to 2048px at
/// quality 85 before we ever see the file, which lands a phone photo at
/// 300–800 KB. This is the backstop for paths where the plugin hands back the
/// original untouched.
const int kMaxImageBytes = 12 * 1024 * 1024;

/// Largest single video, in bytes.
///
/// Phone 1080p30 H.264 runs ~17 Mbps (~130 MB/min); HEVC 1080p ~8 Mbps
/// (~60 MB/min). 150 MB therefore admits a normal short clip and refuses a 4K
/// minute. It is also an UPLOAD-time ceiling: with no background queue, the
/// user holds the screen open for the whole upload, and 150 MB on a 5 Mbps
/// uplink is about four minutes of watching a progress bar.
const int kMaxVideoBytes = 150 * 1024 * 1024;

/// Longest single video.
///
/// Deliberately chosen to bind at roughly the same point as [kMaxVideoBytes]
/// rather than well beyond it. A cap that can never fire teaches the user
/// nothing and produces a confusing "too big" only after they have waited for
/// the duration probe.
const Duration kMaxVideoDuration = Duration(seconds: 60);

/// How many files one pick may contribute.
///
/// Bounds a sequential-upload session to something a user will actually wait
/// through, since there is no queue to walk away from.
const int kMaxItemsPerPick = 10;

/// Why a picked file was refused.
enum MediaRefusal {
  /// Not an image or video type LunaTrack accepts.
  unsupportedType,

  /// Zero bytes.
  empty,

  /// Over [kMaxImageBytes] / [kMaxVideoBytes] for its kind.
  tooLarge,

  /// Over [kMaxVideoDuration].
  tooLong,

  /// A video whose duration could not be read. The probe has a short timeout
  /// because a malformed file can hang it; an unmeasurable video is refused
  /// rather than uploaded unmeasured, because a cap that cannot be evaluated
  /// is not a cap.
  unreadable,
}

/// A refused file, with copy the picker can show as-is.
class MediaRejection {
  const MediaRejection(this.reason);

  final MediaRefusal reason;

  String get message => messageFor(reason);

  @override
  String toString() => 'MediaRejection($reason)';
}

/// User-facing copy for each refusal.
///
/// GUARDRAIL: none of these strings may claim the media is safe, private,
/// secure, encrypted or protected. The bucket is unencrypted and readable by
/// the operator, and copy must describe what the code does today.
/// `media_limits_test.dart` scans for those words.
String messageFor(MediaRefusal reason) {
  switch (reason) {
    case MediaRefusal.unsupportedType:
      return 'LunaTrack takes photos (JPEG, PNG, WebP, HEIC) and videos '
          '(MP4, MOV).';
    case MediaRefusal.empty:
      return "That file is empty, so there's nothing to add.";
    case MediaRefusal.tooLarge:
      return 'Photos need to be under 12 MB and videos under 150 MB.';
    case MediaRefusal.tooLong:
      return 'Videos need to be under a minute so they finish uploading.';
    case MediaRefusal.unreadable:
      return "LunaTrack couldn't read how long that video is, so it wasn't "
          'added.';
  }
}

/// The kind [contentType] denotes, or null if LunaTrack does not accept it.
///
/// Parameters after `;` are dropped and the type is lowercased, then matched
/// EXACTLY against the allowlists — the same anchored comparison
/// `storage.rules` makes, so `text/html;image/jpeg` and `image/jpeg.evil` both
/// fail here exactly as they fail there.
MediaKind? mediaKindFor(String contentType) {
  final base = contentType.split(';').first.trim().toLowerCase();
  if (kAllowedImageTypes.containsKey(base)) return MediaKind.image;
  if (kAllowedVideoTypes.containsKey(base)) return MediaKind.video;
  return null;
}

/// The object-path extension for [contentType], or null if not accepted.
String? extensionFor(String contentType) {
  final base = contentType.split(';').first.trim().toLowerCase();
  return kAllowedImageTypes[base] ?? kAllowedVideoTypes[base];
}

/// Checks one picked file against every limit. Returns null when it is fine.
///
/// [duration] is required for video and ignored for images; passing null for a
/// video means the probe failed, which is [MediaRefusal.unreadable].
MediaRejection? checkPickedFile({
  required String contentType,
  required int bytes,
  Duration? duration,
}) {
  final kind = mediaKindFor(contentType);
  if (kind == null) return const MediaRejection(MediaRefusal.unsupportedType);
  if (bytes <= 0) return const MediaRejection(MediaRefusal.empty);

  switch (kind) {
    case MediaKind.image:
      if (bytes > kMaxImageBytes) {
        return const MediaRejection(MediaRefusal.tooLarge);
      }
    case MediaKind.video:
      if (bytes > kMaxVideoBytes) {
        return const MediaRejection(MediaRefusal.tooLarge);
      }
      if (duration == null) {
        return const MediaRejection(MediaRefusal.unreadable);
      }
      if (duration > kMaxVideoDuration) {
        return const MediaRejection(MediaRefusal.tooLong);
      }
  }
  return null;
}

/// The outcome of applying [kMaxItemsPerPick] to a pick.
class PickLimitResult<T> {
  const PickLimitResult(this.accepted, this.dropped);

  final List<T> accepted;

  /// How many files were left out. Never let this go unreported: a silent
  /// truncation reads to the user as "we took everything".
  final int dropped;
}

/// Keeps the first [kMaxItemsPerPick] items and counts the rest.
PickLimitResult<T> applyPickLimit<T>(List<T> items) {
  if (items.length <= kMaxItemsPerPick) {
    return PickLimitResult<T>(items, 0);
  }
  return PickLimitResult<T>(
    items.sublist(0, kMaxItemsPerPick),
    items.length - kMaxItemsPerPick,
  );
}
