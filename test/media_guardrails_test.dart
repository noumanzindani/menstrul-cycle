import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guardrails for the media timeline.
///
/// Modelled on `product_timer_guardrails_test.dart`: these assert invariants
/// about the SHAPE of the codebase rather than the behaviour of one unit,
/// because each of them is a rule that a perfectly reasonable-looking local
/// change would break silently.
///
/// A failure here is a question about whether the ruling changed — not about
/// how to make the test pass.
String _read(String path) => File(path).readAsStringSync();

/// Source with comments stripped. Necessary, not fastidious: the doc comments
/// explaining these very rules name the things the rules forbid, so a raw scan
/// would fail on the explanation rather than on the code.
String _code(String path) => _read(path)
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'///.*'), '')
    .replaceAll(RegExp(r'//.*'), '');

String _xml(String path) =>
    _read(path).replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Every `lib/` Dart file, so a rule cannot be dodged by adding a new one.
Iterable<File> _libSources() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

Iterable<File> _mediaSources() => _libSources().where(
      (f) =>
          f.path.contains('media') ||
          f.path.contains('storage_ref') ||
          f.path.contains('screens/media'),
    );

void main() {
  group('download URLs never enter the codebase', () {
    test('nothing in lib/ calls getDownloadURL', () {
      // A Firebase download URL carries a token that security rules NEVER
      // evaluate, does not expire, and works for anybody holding the string.
      // One leaked into a log line, a crash report, a share sheet or the
      // (unencrypted) Firestore SDK cache is a permanent public link to an
      // intimate photograph.
      //
      // The emulator suite proves storage.rules cannot stop a token being
      // minted, so this scan is not belt-and-braces — it is the primary
      // defence, in the same style as the standing
      // `grep FirebaseFirestore.instance lib/` rule.
      for (final file in _libSources()) {
        expect(_code(file.path).contains('getDownloadURL'), isFalse,
            reason: '${file.path} calls getDownloadURL');
      }
    });

    test('no media source stores a URL field', () {
      for (final file in _mediaSources()) {
        final code = _code(file.path);
        for (final field in ["'downloadUrl'", "'downloadURL'"]) {
          expect(code.contains(field), isFalse, reason: '${file.path} → $field');
        }
      }
    });
  });

  group('the Firebase seams stay intact', () {
    test('only the two seam files import firebase_storage', () {
      // Mirrors the FirebaseFirestore.instance rule. `lunaStorage()` throws
      // with no initialized Firebase app — the state of every test harness —
      // so a third importer is what would make the media feature untestable.
      //
      // Two, not one: `storage_ref.dart` names the bucket (the Storage analogue
      // of `firestore_ref.dart`) and `media_blob_store.dart` is the only thing
      // that performs I/O through it.
      final importers = _libSources()
          .where((f) => _read(f.path).contains('package:firebase_storage'))
          .map((f) => f.path)
          .toList()
        ..sort();
      expect(importers, [
        'lib/services/media_blob_store.dart',
        'lib/services/storage_ref.dart',
      ]);
    });

    test('nothing uses FirebaseStorage.instance', () {
      // `.instance` targets the project's DEFAULT bucket, which in a shared
      // project carries somebody else's ruleset — over unencrypted photographs.
      //
      // The negative lookahead is load-bearing: `instanceFor(...)` is the
      // CORRECT call and contains `.instance` as a substring, so a plain
      // `contains` check fails on the fix rather than on the bug.
      final bad = RegExp(r'FirebaseStorage\.instance(?!For)');
      for (final file in _libSources()) {
        expect(bad.hasMatch(_code(file.path)), isFalse, reason: file.path);
      }
    });
  });

  group('the photo-description seam stays intact', () {
    test('only media_analyzer.dart makes an outbound HTTP request', () {
      // Same reason as the firebase_storage rule, plus a sharper one:
      // `flutter_test` installs a global HttpOverrides whose mock response
      // hardcodes `statusCode => 400`. A real HttpClient call anywhere above
      // this seam does not throw and does not reach the network — it quietly
      // returns 400, and a test written against that passes while proving
      // nothing. A second caller is how that silence spreads.
      final callers = _libSources()
          .where((f) => RegExp(r'\bHttpClient\b').hasMatch(_code(f.path)))
          .map((f) => f.path)
          .toList()
        ..sort();
      expect(callers, ['lib/services/media_analyzer.dart']);
    });

    test('the API key is read in exactly one place', () {
      // A second `fromEnvironment` read is a second place to forget the
      // empty-string default, which is what hides the feature in builds that
      // were never given a key.
      final readers = _libSources()
          .where((f) => _code(f.path).contains('LUNA_GEMINI_KEY'))
          .map((f) => f.path)
          .toList()
        ..sort();
      expect(readers, ['lib/services/media_analyzer.dart']);
    });

    test('no service API key is hardcoded anywhere in lib/', () {
      // Google API keys start `AIza`. One pasted in here as a "temporary"
      // default would be compiled into every build and published to Play, and
      // a Generative Language key is a BILLABLE endpoint — anyone who unpacks
      // the APK can drain it against the owner's account.
      //
      // `firebase_options.dart` is excluded, and the distinction is real rather
      // than a convenience: a Firebase client config key is an identifier, not
      // a credential. It is designed to ship in the app, and access is decided
      // by security rules, not by holding the string. It still should not be
      // committed — see the .gitignore note in README — but it is not this
      // rule's subject.
      final offenders = _libSources()
          .where((f) => !f.path.endsWith('firebase_options.dart'))
          .where((f) => RegExp('AIza[0-9A-Za-z_-]{20,}').hasMatch(_read(f.path)))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty);
    });

    test('the analysis service never touches media storage or the database',
        () {
      // It receives bytes and returns text. Reaching for the repository or the
      // blob store would give it a way to persist a description, which is the
      // one thing this feature must not do — see "nothing derived is stored".
      final code = _code('lib/services/media_analysis_service.dart');
      for (final banned in [
        'MediaRepository',
        'MediaBlobStore',
        'AppDatabase',
        'lunaFirestore',
      ]) {
        expect(code.contains(banned), isFalse, reason: banned);
      }
    });
  });

  group('media stays out of everything it must not reach', () {
    test('never enters the doctor PDF', () {
      // The diary case squared: a printed or emailed clinical document must not
      // carry bodily imagery. Diary text is already excluded; photographs are
      // the stronger version of the same rule.
      final src = _code('lib/services/pdf_report_service.dart');
      expect(src.contains('MediaItem'), isFalse);
      expect(src.contains('mediaItems'), isFalse);
    });

    test('never reaches the home-screen widget', () {
      // The launcher widget renders OUTSIDE AppLock, so anything it shows is
      // visible to whoever picks up the phone.
      final src = _code('lib/services/home_widget_service.dart');
      expect(src.contains('MediaItem'), isFalse);
      expect(src.contains('media'), isFalse);
    });

    test('never rides the day-tags blob', () {
      // `DailyLogs.symptoms` is synced as a real Firestore map under whole-day
      // last-write-wins, and `encodeDayTags` is a full REPLACE — so anything
      // stored there can be fabricated or destroyed by a cross-device merge.
      for (final file in _mediaSources()) {
        final code = _code(file.path);
        expect(code.contains('encodeDayTags'), isFalse, reason: file.path);
        expect(code.contains('symptomsJson'), isFalse, reason: file.path);
        expect(code.contains('kReservedTagPrefixes'), isFalse,
            reason: file.path);
      }
    });

    test('never co-renders with an ad banner', () {
      // Same family as the diary and the day editor. A banner beside a user's
      // body photo is not a placement this app makes.
      for (final file in _mediaSources()) {
        expect(_code(file.path).contains('AdBanner'), isFalse,
            reason: file.path);
      }
    });

    test('is not added as a sixth bottom-nav destination', () {
      // The bottom nav is at Material's five-destination ceiling, and
      // `AppShell._onSelect` fires the interstitial on index 0 — so any
      // reshuffle silently re-targets it.
      final src = _code('lib/screens/app_shell.dart');
      expect(src.contains('Media'), isFalse);
    });
  });

  group('user-facing copy claims nothing the storage does not deliver', () {
    test('no media copy says safe, private, secure or encrypted', () {
      // The bucket is unencrypted and readable by the operator and by any
      // project IAM principal. Copy must describe what the code does today.
      const banned = ['encrypted', 'secure', 'private', 'safe'];
      for (final file in _mediaSources()) {
        final source = _read(file.path)
            .replaceAll(RegExp(r'///.*'), '')
            .replaceAll(RegExp(r'//.*'), '');
        for (final match
            in RegExp(r"'((?:[^'\\\n]|\\.)*)'").allMatches(source)) {
          final literal = match.group(1)!.toLowerCase();
          // Only sentences — identifiers and paths are not user-facing.
          if (!literal.contains(' ')) continue;
          for (final word in banned) {
            expect(literal.contains(word), isFalse,
                reason: '${file.path}: "$literal" contains "$word"');
          }
        }
      }
    });
  });

  group('the Android manifest', () {
    test('declares no media permission, and never ACCESS_MEDIA_LOCATION', () {
      // The system Photo Picker needs none of these, and Play restricts
      // READ_MEDIA_* to apps whose core purpose is photo/video. Each appears
      // only as an explicit tools:node="remove", never as a declaration.
      final xml = _xml('android/app/src/main/AndroidManifest.xml');
      for (final permission in [
        'READ_MEDIA_IMAGES',
        'READ_MEDIA_VIDEO',
        'READ_EXTERNAL_STORAGE',
        'ACCESS_MEDIA_LOCATION',
        'CAMERA',
      ]) {
        final declared = RegExp(
          '<uses-permission[^>]*$permission(?![^>]*tools:node="remove")[^>]*/>',
          dotAll: true,
        ).hasMatch(xml);
        expect(declared, isFalse, reason: '$permission is DECLARED');
      }
    });

    test('still declares no foreground service', () {
      // A media upload is exactly the feature that tempts one. It would mean a
      // permanent status-bar icon: continuous self-disclosure by a period
      // tracker, which is the harm `visibility: secret` exists to prevent.
      final xml = _xml('android/app/src/main/AndroidManifest.xml');
      expect(xml.contains('FOREGROUND_SERVICE'), isFalse);
      expect(xml.contains('<service'), isFalse);
    });

    test('keeps allowBackup off, which the media cache relies on', () {
      // The downloaded-media cache is plain files in the app sandbox. That is
      // acceptable partly BECAUSE Android Auto Backup cannot copy it off the
      // device — so this flag is load-bearing for a second feature now.
      expect(
        _read('android/app/src/main/AndroidManifest.xml'),
        contains('android:allowBackup="false"'),
      );
    });
  });

  group('the deletion contract is stated in every place it must be', () {
    test('media is in the Dart subcollection list and the purge job', () {
      expect(_read('lib/services/account_deletion_service.dart'),
          contains("'media'"));
      expect(_read('functions/purge.js'), contains("'media'"));
    });

    test('the purge sweeps Cloud Storage, not just Firestore', () {
      // Deleting the metadata alone leaves the bytes: unreferenced,
      // unreachable, unencrypted, and belonging to somebody who asked for them
      // to be gone.
      expect(_read('functions/purge.js'), contains('deleteStorageData'));
      expect(_read('functions/index.js'), contains('deleteStoragePrefix'));
    });

    test('storage.rules exists and is wired into firebase.json', () {
      expect(File('storage.rules').existsSync(), isTrue);
      expect(_read('firebase.json'), contains('storage.rules'));
    });
  });
}
