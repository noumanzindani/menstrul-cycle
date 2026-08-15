import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/models/product_type.dart';
import 'package:menstrul_track/services/product_timer_plan.dart';

/// Structural guards for the product-change timer.
///
/// These assert properties that a reviewer cannot hold in their head across a
/// refactor: that intimate timestamps never reach Firestore, that a duration is
/// never inferred from cycle data, that the manifest keeps its clean
/// permission posture, and that the copy never reassures or counts down.
///
/// Every one of them encodes a council ruling. If one starts failing, the
/// question is whether the ruling changed — not how to make the test pass.

String _read(String path) => File(path).readAsStringSync();

/// Source with comments stripped.
///
/// Necessary, not fastidious: the doc comments explaining these very rules name
/// the things the rules forbid ("never inferred from a prediction", "no
/// SCHEDULE_EXACT_ALARM needed"), so scanning raw text would fail on the
/// explanation rather than on the code.
String _code(String path) => _read(path)
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//.*'), '');

/// XML with `<!-- ... -->` comments stripped, for the same reason.
String _xml(String path) =>
    _read(path).replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// The string literals in a Dart source, so a copy scan does not trip over
/// identifiers or the doc comments that explain the rules themselves.
Iterable<String> _stringLiterals(String source) sync* {
  final withoutComments = source
      .replaceAll(RegExp(r'///.*'), '')
      .replaceAll(RegExp(r'//.*'), '');
  for (final m in RegExp(r"'((?:[^'\\\n]|\\.)*)'").allMatches(withoutComments)) {
    yield m.group(1)!;
  }
  for (final m in RegExp(r'"((?:[^"\\\n]|\\.)*)"').allMatches(withoutComments)) {
    yield m.group(1)!;
  }
}

const _timerSources = [
  'lib/models/product_type.dart',
  'lib/models/product_session.dart',
  'lib/services/product_timer_plan.dart',
  'lib/services/product_timer_payload.dart',
  'lib/services/product_change_writer.dart',
  'lib/data/product_session_repository.dart',
  'lib/providers/product_session_provider.dart',
  'lib/widgets/product_timer_card.dart',
  'lib/widgets/product_timer_start_card.dart',
];

void main() {
  group('sync exclusion', () {
    test('no sync code names the product session', () {
      // Firestore holds a PLAINTEXT, operator-readable copy, and firestore.rules
      // is not deployed. A minute-resolution log of intimate acts — which is
      // also a de-facto sleep and presence sensor — must not go near it.
      for (final path in [
        'lib/services/sync_mapper.dart',
        'lib/services/sync_service.dart',
      ]) {
        final src = _code(path).toLowerCase();
        for (final token in ['productchange', 'productsession', 'producttype']) {
          expect(src.contains(token), isFalse,
              reason: '$path must not reference $token');
        }
      }
    });

    test('the session lives on Reminders, which sync already excludes', () {
      final repo = _read('lib/data/product_session_repository.dart');
      expect(repo.contains('ReminderRepository'), isTrue);
      // If this ever becomes its own table, the sync exclusion above stops
      // being free and has to be re-established deliberately.
      expect(_read('lib/db/database.dart').contains('productChanges'), isFalse);
    });

    test('nothing is written into the day-tags blob', () {
      // DailyLogs.symptoms IS synced, as a real Firestore map, and encodeDayTags
      // is a full REPLACE under whole-day last-write-wins — so a cross-device
      // merge could fabricate events the user never logged.
      for (final path in _timerSources) {
        final src = _code(path);
        expect(src.contains('encodeDayTags'), isFalse, reason: path);
        expect(src.contains('symptomsJson'), isFalse, reason: path);
        expect(src.contains('kReservedTagPrefixes'), isFalse, reason: path);
      }
    });

    test('the timer still owns no table of its own', () {
      // This test used to pin `schemaVersion => 5` outright, because the whole
      // ephemeral design exists to avoid a migration. The literal went stale at
      // v6, which the MEDIA TIMELINE introduced (`MediaItems`) — a table with no
      // relationship to the timer.
      //
      // Pinning the version number was always a proxy for the real ruling:
      // *the product-change session must not grow a table*. Any future feature
      // bumping the schema would trip it and teach the next reader that the
      // timer had changed when it had not. So assert the ruling directly, and
      // note that `productChanges` is also checked above, where the reason it
      // matters (the free sync exclusion) is written down.
      final src = _read('lib/db/database.dart');
      for (final forbidden in [
        'productChanges',
        'productSessions',
        'ProductChanges',
        'ProductSessions',
      ]) {
        expect(src.contains(forbidden), isFalse,
            reason: 'the timer grew a table: $forbidden');
      }
      // The session still rides a Reminders row, so the table it needs is one
      // that already existed.
      expect(src, contains('Reminders'));
    });
  });

  group('no inference from cycle data', () {
    test('duration depends on the product type and nothing else', () {
      // Varying a wear time by predicted flow or cycle day would turn a timer
      // into a synthesized clinical recommendation.
      final src = _code('lib/models/product_type.dart');
      for (final forbidden in [
        'prediction',
        'DailyLog',
        'CyclePhase',
        'FlowIntensity',
        'log_provider',
      ]) {
        expect(src.contains(forbidden), isFalse,
            reason: 'product_type.dart must not know about $forbidden');
      }
    });

    test('the planner takes no logs, prediction or phase', () {
      final src = _code('lib/services/product_timer_plan.dart');
      expect(src.contains('PredictionResult'), isFalse);
      expect(src.contains('DailyLog'), isFalse);
    });

    test('defaults are stable regardless of anything external', () {
      expect(ProductType.tampon.defaultDuration, const Duration(hours: 4));
      expect(ProductType.cupOrDisc.defaultDuration, const Duration(hours: 8));
    });
  });

  group('copy', () {
    test('never says "safe", reassures, or names TSS', () {
      const banned = [
        'safe',
        'risk-free',
        "you're fine",
        'still good',
        'no rush',
        'tss',
        'toxic shock',
        'overdue',
        'dangerous',
        'emergency',
      ];
      for (final path in _timerSources) {
        for (final literal in _stringLiterals(_read(path))) {
          final lower = literal.toLowerCase();
          for (final word in banned) {
            expect(lower.contains(word), isFalse,
                reason: '$path: "$literal" contains "$word"');
          }
        }
      }
    });

    test('never counts down', () {
      // Elapsed counts UP. Time remaining would draw a deadline the app cannot
      // locate, on a value it does not know: absorbency, flow, individual risk.
      for (final path in _timerSources) {
        for (final literal in _stringLiterals(_read(path))) {
          final lower = literal.toLowerCase();
          for (final word in ['remaining', "time's up", 'time left']) {
            expect(lower.contains(word), isFalse,
                reason: '$path: "$literal" contains "$word"');
          }
        }
      }
    });

    test('never authors a duration as its own advice', () {
      for (final path in _timerSources) {
        for (final literal in _stringLiterals(_read(path))) {
          final lower = literal.toLowerCase();
          expect(lower.contains('we recommend'), isFalse, reason: literal);
          expect(lower.contains('you must'), isFalse, reason: literal);
        }
      }
    });

    test('has no symptom checker or triage affordance', () {
      // A triage instrument is a medical-device function (the same ground that
      // vetoed LH-strip auto-interpretation) and the highest-anxiety possible
      // artefact for the app's teenage users.
      for (final path in _timerSources) {
        final src = _code(path).toLowerCase();
        for (final word in ['fever', 'rash', 'vomit', 'hospital', '911', '999']) {
          expect(src.contains(word), isFalse, reason: '$path mentions $word');
        }
      }
    });

    test('has no gamification', () {
      // A compliance score on intimate hygiene, aimed partly at minors, is a
      // shame mechanic.
      for (final path in _timerSources) {
        final src = _code(path).toLowerCase();
        for (final word in ['streak', 'badge', 'adherence', 'perfect']) {
          expect(src.contains(word), isFalse, reason: '$path mentions $word');
        }
      }
    });

    test('states the best-effort limitation where the user relies on it', () {
      final card = _read('lib/widgets/product_timer_start_card.dart');
      expect(card, contains('may arrive late, or not at all'));
      expect(card, contains('Follow the instructions that came with your product'));
    });
  });

  group('android manifest posture', () {
    final manifest = _xml('android/app/src/main/AndroidManifest.xml');

    test('claims no exact-alarm permission', () {
      // USE_EXACT_ALARM is restricted by Play to alarm-clock and calendar apps.
      // It would also not buy what it appears to: an OEM force-stop drops every
      // pending alarm regardless of exactness, so it converts a best-effort
      // channel into something that merely LOOKS guaranteed.
      expect(manifest.contains('USE_EXACT_ALARM'), isFalse);
      expect(manifest.contains('SCHEDULE_EXACT_ALARM'), isFalse);
    });

    test('declares no foreground service', () {
      // A foreground service means a permanent status-bar icon — continuous
      // self-disclosure, which is the exact threat `secret` visibility exists
      // to prevent.
      expect(manifest.contains('FOREGROUND_SERVICE'), isFalse);
      expect(manifest.contains('<service'), isFalse);
    });

    test('claims no full-screen intent, DND bypass or battery-opt exemption',
        () {
      expect(manifest.contains('USE_FULL_SCREEN_INTENT'), isFalse);
      expect(manifest.contains('ACCESS_NOTIFICATION_POLICY'), isFalse);
      expect(
          manifest.contains('REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'), isFalse);
    });

    test('still omits INTERNET in the main variant', () {
      // Untouched by this feature, and asserted here so it stays that way.
      expect(manifest.contains('android.permission.INTERNET'), isFalse);
    });
  });

  group('surface exclusions', () {
    test('the home-screen widget carries no session state', () {
      // The launcher widget renders OUTSIDE AppLock, so anything it shows is
      // readable by whoever is holding the locked phone. It has exactly two
      // string slots and neither may ever carry the timer.
      final src = _code('lib/services/home_widget_service.dart');
      for (final token in [
        'Product',
        'tampon',
        'Tampon',
        'session',
        'Session',
      ]) {
        expect(src.contains(token), isFalse,
            reason: 'home_widget_service must not reference $token');
      }
    });

    test('the doctor PDF carries no session state', () {
      expect(_read('lib/services/pdf_report_service.dart').contains('Product'),
          isFalse);
    });

    test('the duration sheet shows no ad', () {
      // Home itself keeps its banner in the bottomNavigationBar slot, as
      // ad_placement_test already guards. This asserts the modal the user
      // actually interacts with stays clean.
      expect(_read('lib/widgets/product_timer_start_card.dart').contains('AdBanner'),
          isFalse);
      expect(_read('lib/widgets/product_timer_card.dart').contains('AdBanner'),
          isFalse);
    });
  });

  group('notification slot discipline', () {
    test('exactly two slots, spaced clear of the allow-while-idle throttle', () {
      // Two for delivery redundancy on a deliberately inexact alarm — not to
      // nag. A third would be nagging, and closer spacing would be silently
      // swallowed by Android's ~9-15 minute setAndAllowWhileIdle rate limit.
      expect(ProductTimerPlan.allIds, hasLength(2));
      expect(ProductTimerPlan.followUpDelay,
          greaterThanOrEqualTo(ProductTimerPlan.minSlotSpacing));
    });
  });
}
