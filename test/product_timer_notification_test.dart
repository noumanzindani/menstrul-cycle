import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/check_in_notifications.dart';
import 'package:menstrul_track/services/notification_service.dart';
import 'package:menstrul_track/services/product_timer_plan.dart';

/// Words that must never reach a lock screen, a paired watch, a mirrored
/// desktop notification, Notification History, or the OS Settings channel list.
const _revealing = [
  'tampon',
  'cup',
  'disc',
  'pad',
  'period',
  'menstrual',
  'underwear',
];

void main() {
  group('product_change channel', () {
    final android =
        NotificationService.productTimerDetails().android as AndroidNotificationDetails;

    test('is its own channel, so it can be silenced independently', () {
      // Not `cycle_reminders` (the user must be able to mute one without the
      // other) and not `medication_reminders`.
      expect(android.channelId, 'product_change');
      expect(android.channelId, isNot('cycle_reminders'));
      expect(android.channelId, isNot('medication_reminders'));
    });

    test('is secret, which is load-bearing twice over', () {
      // Privacy: this notification names an intimate physical act and is more
      // sensitive than the cycle reminders already ruled secret.
      // Correctness: secret means it cannot be actioned before unlock, which is
      // what guarantees the keystore is available when the background writer
      // opens the encrypted DB.
      expect(android.visibility, NotificationVisibility.secret);
    });

    test('the OS-visible channel name and description reveal nothing', () {
      // Both render in Settings -> Notifications on a shared or supervised
      // phone, where the app must not announce what it is for.
      final metadata =
          '${android.channelName} ${android.channelDescription}'.toLowerCase();
      for (final word in _revealing) {
        expect(metadata, isNot(contains(word)),
            reason: '"$word" must not appear in channel metadata');
      }
      expect(android.channelName, 'Timed reminders');
      expect(android.channelDescription, 'Reminders you set yourself');
    });

    test('carries no ticker or big-text style that could reconstruct content',
        () {
      expect(android.ticker, isNull);
      expect(android.styleInformation, isNull);
    });

    test('carries exactly one action, which reveals nothing', () {
      expect(android.actions, hasLength(1));
      final action = android.actions!.single;
      expect(action.id, kProductChangedAction);
      expect(action.title, 'Changed');
      for (final word in _revealing) {
        expect(action.title.toLowerCase(), isNot(contains(word)));
      }
    });

    test('the action does not self-dismiss, so a failed write can be retried',
        () {
      final action = android.actions!.single;
      expect(action.cancelNotification, isFalse);
      // Answering must not drag the user into the app from a lock screen.
      expect(action.showsUserInterface, isFalse);
    });

    test('the action id is distinct from the check-in action', () {
      // handleCheckInResponse dispatches on this id; a collision would route a
      // product tap into the no-bleeding writer.
      expect(kProductChangedAction, isNot(kCheckInNoBleedingAction));
    });
  });

  group('notification id ranges', () {
    test('the timer ids collide with nothing already allocated', () {
      final taken = <int>{
        NotificationService.idLogNudge,
        NotificationService.idPeriodSoon,
        NotificationService.idFertile,
        for (var i = 0; i < CheckInHorizon.horizonDays; i++)
          CheckInHorizon.idCheckInBase + i,
      };
      for (final id in ProductTimerPlan.allIds) {
        expect(taken, isNot(contains(id)));
        // 2000+ and 3000+ are unbounded row-id offsets; staying above both
        // bases is what keeps the timer clear of them.
        expect(id, greaterThan(NotificationService.idMedicationBase));
        expect(id, greaterThan(NotificationService.idCustomBase));
      }
    });

    test('the timer ids are not in the range rescheduleHorizon cancels', () {
      // rescheduleHorizon cancels 4000-4013 on EVERY app resume. An overlap
      // would silently kill a live timer every time the user opened the app.
      for (final id in ProductTimerPlan.allIds) {
        expect(
          id,
          isNot(inInclusiveRange(CheckInHorizon.idCheckInBase,
              CheckInHorizon.idCheckInBase + CheckInHorizon.horizonDays - 1)),
        );
      }
    });
  });

  group('medication channel (pre-existing leak)', () {
    final android =
        NotificationService.medicationDetails().android as AndroidNotificationDetails;

    test('does not put medication or birth-control state on the lock screen',
        () {
      expect(android.visibility, NotificationVisibility.secret);
    });

    test('its OS-visible description does not say "birth control"', () {
      expect(android.channelDescription?.toLowerCase(),
          isNot(contains('birth control')));
    });
  });
}
