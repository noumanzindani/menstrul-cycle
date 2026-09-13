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

/// Every merged `AndroidManifest.xml` an Android build has produced.
///
/// Empty on a clean checkout, which is why the tests using it declare a `skip`
/// reason rather than quietly passing — a guardrail that reports success when
/// it examined nothing is the exact defect this group was written to fix.
Iterable<File> _mergedManifests() sync* {
  final dir = Directory('build/app/intermediates/merged_manifests');
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('AndroidManifest.xml')) {
      yield entity;
    }
  }
}

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
  group('in-app capture must not declare a camera permission', () {
    // The counter-intuitive one, and the reason it is a test rather than a
    // comment: `image_picker` captures by launching the SYSTEM camera app via
    // ACTION_IMAGE_CAPTURE, which needs no permission at all — UNLESS the app
    // declares android.permission.CAMERA, at which point Android starts
    // requiring it to be granted. Declaring the permission therefore BREAKS the
    // feature it looks like it enables, and does so at runtime on a device, not
    // at build time.
    //
    // Same shape as the media-permission reasoning already in this file: the
    // system-delegated route is both the compliant one and the one that needs
    // nothing declared.
    const forbidden = ['android.permission.CAMERA'];

    test('the SOURCE manifest declares no camera permission', () {
      final xml = _xml('android/app/src/main/AndroidManifest.xml');
      for (final p in forbidden) {
        expect(xml, isNot(contains(p)),
            reason: '$p makes ACTION_IMAGE_CAPTURE require a grant the app '
                'never requests, so capture fails silently on device');
      }
    });

    test('no MERGED manifest declares one either', () {
      // A dependency can add a permission the app never wrote. Only the merged
      // manifest shows that, and it exists only after an Android build.
      final manifests = _mergedManifests().toList();
      for (final f in manifests) {
        final xml = f.readAsStringSync();
        for (final p in forbidden) {
          expect(xml, isNot(contains(p)),
              reason: '${f.path} merges in $p from a dependency');
        }
      }
    }, skip: _mergedManifests().isEmpty
        ? 'no merged manifest on disk; run an Android build first'
        : false);

    test('iOS DOES declare the camera and microphone usage strings', () {
      // The matched pair to the Android rule above, and they pull in opposite
      // directions: Android must declare NOTHING, iOS must declare BOTH or the
      // app crashes the moment the camera opens. Asserting only one half would
      // leave the other silently wrong on a platform this repo builds for but
      // rarely runs.
      final plist = _read('ios/Runner/Info.plist');
      for (final key in const [
        'NSCameraUsageDescription',
        'NSMicrophoneUsageDescription',
      ]) {
        expect(plist, contains(key),
            reason: 'iOS hard-crashes on camera launch without $key');
      }
    });

    test('capture goes through the configured picker, like every other pick',
        () {
      // `useSystemPhotoPicker` has to run before ANY picker call, capture
      // included. A second entry point that built a bare ImagePicker would
      // bypass the Photo Picker delegation for library picks.
      final route = _read('lib/screens/media/media_route.dart');
      expect(route, contains('useSystemPhotoPicker()'));
      final pickerCalls = RegExp(r'ImagePicker\(\)').allMatches(route).length;
      expect(pickerCalls, 1,
          reason: 'one picker construction, configured once — a second would '
              'be a second place to forget the configuration');
    });
  });

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

    test('declares no service of its own, and no foreground permission', () {
      // A media upload is exactly the feature that tempts one. It would mean a
      // permanent status-bar icon: continuous self-disclosure by a period
      // tracker, which is the harm `visibility: secret` exists to prevent.
      //
      // Scoped to OUR file on purpose. This assertion used to be written as if
      // it covered the shipped app, and it did not — see the merged-manifest
      // group below, which is the one Play actually scans.
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

  group('the MERGED manifest, which is the one Play scans', () {
    // The source manifest is not what ships. Manifest merge folds in every
    // dependency's declarations, and `home_widget` alone brings
    // androidx.glance plus androidx.work — which is how thirteen <service>
    // entries and FOREGROUND_SERVICE arrive without appearing in our file.
    //
    // So the invariant cannot be "no service" — every app using Firebase, Play
    // Services or Glance has a dozen. It is that none of them is OURS, and that
    // none is TYPED: `foregroundServiceType` is the attribute that forces a
    // Play Console declaration and produces the persistent, typed notification.
    // An untyped service that nothing ever starts costs the user nothing.
    final manifests = _mergedManifests().toList();
    // Skipping is honest on a clean checkout and dishonest at release time, so
    // the release pipeline sets LUNA_REQUIRE_MERGED_MANIFEST=1 and these become
    // a hard failure instead. `flutter test` alone reports them as skipped —
    // which reads as `~2` in the summary, NOT as a pass.
    final required =
        Platform.environment['LUNA_REQUIRE_MERGED_MANIFEST'] == '1';
    final absent = manifests.isEmpty && !required
        ? 'no merged manifest built yet — run `flutter build apk` (or any '
            'Android build) to produce it, then re-run this test'
        : null;

    void requireBuilt() => expect(
          manifests,
          isNotEmpty,
          reason: 'LUNA_REQUIRE_MERGED_MANIFEST=1, but no Android build output '
              'exists to check — build before gating a release on this',
        );

    test('carries no foregroundServiceType, and no service of ours', () {
      requireBuilt();
      for (final file in manifests) {
        final xml = _xml(file.path);
        expect(
          xml.contains('foregroundServiceType'),
          isFalse,
          reason: '${file.path} declares a TYPED foreground service',
        );
        for (final match
            in RegExp(r'<service\b(.*?)(?:/>|>)', dotAll: true).allMatches(xml)) {
          final name =
              RegExp(r'android:name="([^"]+)"').firstMatch(match.group(1)!);
          final declared = name?.group(1) ?? '';
          expect(
            declared.startsWith('.') ||
                declared.startsWith('com.lunatrack') ||
                declared.startsWith('com.example.menstrul_track'),
            isFalse,
            reason: '$declared is OUR service, in ${file.path}',
          );
        }
      }
    }, skip: absent);

    test('nothing in the app ever asks for foreground or expedited work', () {
      // This is the assertion that actually prevents the harm. androidx.work's
      // SystemForegroundService is DECLARED in the merged manifest and cannot
      // be removed without risking Glance's widget updates — but it only ever
      // starts if something requests it. Nothing does, and nothing may.
      //
      // Matched on call shapes, not the bare word: `onForegroundResponse` and
      // `disabledForegroundColor` are legitimate and unrelated.
      const forbidden = [
        'ForegroundInfo',
        'setForeground(',
        'startForeground(',
        'startForegroundService(',
        'setExpedited(',
        'OutOfQuotaPolicy',
      ];
      final sources = <File>[
        ..._libSources(),
        ...Directory('android/app/src/main')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.kt') || f.path.endsWith('.java')),
      ];
      for (final file in sources) {
        final code = _code(file.path);
        for (final symbol in forbidden) {
          expect(
            code.contains(symbol),
            isFalse,
            reason: '${file.path} requests foreground work via $symbol',
          );
        }
      }
    });

    test('still carries no media permission after the merge', () {
      requireBuilt();
      // The tools:node="remove" entries in our manifest are only a REQUEST.
      // Whether they survived the merge can only be read here.
      for (final file in manifests) {
        final xml = _xml(file.path);
        for (final permission in [
          'READ_MEDIA_IMAGES',
          'READ_MEDIA_VIDEO',
          'READ_EXTERNAL_STORAGE',
          'ACCESS_MEDIA_LOCATION',
        ]) {
          expect(
            RegExp('<uses-permission[^>]*$permission').hasMatch(xml),
            isFalse,
            reason: '$permission survived the merge into ${file.path}',
          );
        }
      }
    }, skip: absent);
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
