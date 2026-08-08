import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'check_in_notifications.dart';
import 'check_in_writer.dart';
import 'notification_service.dart';
import 'product_change_writer.dart';
import 'product_timer_plan.dart';

/// Background-isolate entry point for a notification action tap. Annotated
/// `vm:entry-point` so it survives tree-shaking and can be resolved from its
/// callback handle by the plugin's background dispatcher. Must be a top-level
/// function (not a closure) for that resolution to work.
///
/// This is the crux the whole feature rests on: it runs with the app possibly
/// killed, in a fresh isolate, and must reach the encrypted DB via the keystore.
@pragma('vm:entry-point')
Future<void> checkInNotificationBackgroundHandler(
        NotificationResponse response) =>
    handleCheckInResponse(response);

/// Shared by the background handler above and the foreground tap callback.
/// Dispatches on [NotificationResponse.actionId]; a plain body tap (no action
/// id) falls through to the framework, which opens the app.
///
/// Never throws — a failure here must not crash the background isolate.
Future<void> handleCheckInResponse(NotificationResponse response) async {
  switch (response.actionId) {
    case kCheckInNoBleedingAction:
      await _handleCheckIn(response);
    case kProductChangedAction:
      await _handleProductChanged(response);
  }
}

Future<void> _handleCheckIn(NotificationResponse response) async {
  final date = decodeCheckInPayload(response.payload);
  if (date == null) return;

  await _prepareIsolate();
  final wrote = await CheckInWriter.answerNoBleeding(date);

  // Dismiss the answered notification ONLY on a successful write. The action was
  // scheduled with cancelNotification:false, so a failed write leaves the
  // question standing — that is the retry affordance, no "couldn't save" copy.
  if (wrote && response.id != null) {
    await NotificationService.cancel(response.id!);
  }
}

/// "Changed" — swap in a fresh product of the same kind and re-arm the slots.
///
/// The payload identifies WHICH session this notification answers, so a stale
/// one sitting in the shade is recognised and ignored rather than restarting a
/// session the user has already moved on from. That check lives in the writer,
/// which reads the current session to compare against.
Future<void> _handleProductChanged(NotificationResponse response) async {
  await _prepareIsolate();
  final handled = await ProductChangeWriter.markChanged(response.payload);

  // Same contract as the check-in: dismiss only when handled, so a database
  // failure leaves the prompt on screen to be tapped again.
  if (handled && response.id != null) {
    await NotificationService.cancel(response.id!);
  }
}

/// A background isolate starts with fresh globals: register plugins and init the
/// notification plugin HERE so the DB (drift/native), the keystore
/// (flutter_secure_storage), the home widget, and (re)scheduling all work.
/// Cheap and idempotent in the foreground, where all three are already up.
Future<void> _prepareIsolate() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.init();
}
