import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Play Store listing copy in `store/play/`.
///
/// Store copy is the one piece of user-facing text that no other test sees: it
/// lives outside `lib/`, so the `lib/`-scanning guards (the body-judgement scan
/// in `weight_trend_service_test.dart`, the change-timer scan in
/// `product_timer_guardrails_test.dart`) never reach it. It is also the text a
/// Play reviewer reads first, and the place where a privacy claim the code
/// cannot keep is most tempting and most damaging.
///
/// Length limits are enforced here too, because Play rejects on them and the
/// feedback loop through the console is slow.
void main() {
  final short = File('store/play/short-description.txt');
  final full = File('store/play/full-description.txt');

  String read(File f) => f.readAsStringSync().trimRight();

  group('Play listing copy exists and fits', () {
    test('short description is within Play\'s 80-character limit', () {
      expect(short.existsSync(), isTrue);
      final s = read(short);
      expect(s, isNotEmpty);
      expect(s.length, lessThanOrEqualTo(80),
          reason: 'Play truncates past 80; this is ${s.length}');
      expect(s.contains('\n'), isFalse,
          reason: 'the short description is a single line');
    });

    test('full description is within Play\'s 4000-character limit', () {
      expect(full.existsSync(), isTrue);
      final s = read(full);
      expect(s.length, lessThanOrEqualTo(4000),
          reason: 'Play rejects past 4000; this is ${s.length}');
    });
  });

  group('the fertility guardrails reach the store listing', () {
    // Same rulings as CLAUDE.md, applied to copy the app itself never renders.
    // "safe day" is banned even NEGATED ("you will never see a safe day"):
    // a skimming reader takes away the two words, in a fertility context,
    // which is the entire harm the ruling exists to prevent.
    const banned = <String>[
      'safe day',
      'safe days',
      'safe period',
      "you're fine",
      'no rush',
      'overdue',
      'urgent',
      'guaranteed',
      '100% accurate',
      'prevent pregnancy',
      'birth control method',
    ];

    test('no banned fertility or urgency phrasing', () {
      for (final f in [short, full]) {
        final s = read(f).toLowerCase();
        for (final phrase in banned) {
          expect(s.contains(phrase), isFalse,
              reason: '"$phrase" appears in ${f.path}');
        }
      }
    });

    test('the full description states it is not contraception', () {
      final s = read(full).toLowerCase();
      expect(s.contains('not a contraceptive'), isTrue,
          reason: 'the non-contraception disclaimer is mandatory copy');
      expect(s.contains('estimate'), isTrue);
    });

    test('no synthesised fertility percentage is implied', () {
      final s = read(full);
      expect(RegExp(r'\d+\s?%\s+(chance|likely|accurate|fertile)')
          .hasMatch(s), isFalse);
    });
  });

  group('privacy claims match what the code actually does', () {
    // Logs and settings sync to Firestore in PLAINTEXT and the operator can
    // read them; uploaded media is unencrypted in Cloud Storage. Any listing
    // that claims otherwise is false, and on a health app that is the kind of
    // false that ends an account.
    test('never claims the cloud copy is encrypted or unreadable', () {
      final s = read(full).toLowerCase();
      // A POSITIVE claim is banned. The required DISCLOSURE
      // ("not end-to-end encrypted") contains the same words, so match on the
      // claim shape rather than the bare phrase.
      for (final claim in [
        'is end-to-end encrypted',
        'fully encrypted',
        'completely private',
        'only you can read',
        'only you can see',
        'we cannot see',
        'nobody can see',
        'zero knowledge',
        'zero-knowledge',
      ]) {
        expect(s.contains(claim), isFalse, reason: '"$claim" is not true');
      }
    });

    test('discloses that the synced copy is readable by the operator', () {
      final s = read(full).toLowerCase();
      expect(s.contains('not end-to-end encrypted'), isTrue,
          reason: 'the plaintext cloud copy must be disclosed in the listing');
    });

    test('on-device encryption is claimed only for the device', () {
      final s = read(full).toLowerCase();
      if (s.contains('encrypted at rest')) {
        expect(
          s.contains('on your device') || s.contains('database on your device'),
          isTrue,
          reason: '"encrypted at rest" covers the drift database ONLY, never '
              'the cloud copy or uploaded media',
        );
      }
    });
  });

  group('required listing assets are present', () {
    test('icon and feature graphic exist at the sizes Play demands', () {
      expect(File('store/play/icon-512.png').existsSync(), isTrue);
      expect(
          File('store/play/feature-graphic-1024x500.png').existsSync(), isTrue);
    });
  });
}
