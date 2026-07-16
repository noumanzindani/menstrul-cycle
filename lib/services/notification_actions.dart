import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'check_in_notifications.dart';
import 'check_in_writer.dart';
import 'notification_service.dart';

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

/// Shared by the background handler above and the foreground tap callback. Acts
/// only on the one-tap "no bleeding" action; a plain body tap (no [actionId])
/// falls through to the framework, which opens the app to the relevant screen.
///
/// Never throws — a failure here must not crash the background isolate.
Future<void> handleCheckInResponse(NotificationResponse response) async {
  if (response.actionId != kCheckInNoBleedingAction) return;
  final date = decodeCheckInPayload(response.payload);
  if (date == null) return;

  // A background isolate starts with fresh globals: register plugins and init
  // the notification plugin HERE so the DB (drift/native), the keystore
  // (flutter_secure_storage), the home widget, and (re)scheduling all work.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.init();

  final wrote = await CheckInWriter.answerNoBleeding(date);

  // Dismiss the answered notification ONLY on a successful write. The action was
  // scheduled with cancelNotification:false, so a failed write leaves the
  // question standing — that is the retry affordance, no "couldn't save" copy.
  if (wrote && response.id != null) {
    await NotificationService.cancel(response.id!);
  }
}
