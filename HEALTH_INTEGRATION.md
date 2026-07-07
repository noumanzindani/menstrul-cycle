# Health Connect / HealthKit import — device-verify checklist

Imports **basal body temperature** from the platform health store into the daily
log (feeding the symptothermal BBT chart). Everything that can be unit-tested is
green in `test/health_import_test.dart`; the items below can only be verified on a
real device build.

## What was built

- `HealthImportService` (`lib/services/health_import_service.dart`) — pure
  `earliestPerDay` + `applyTemperatureSamples` (tested) and a native
  `importTemperatures()` orchestration (device-only).
- `DailyLogRepository.setBbtIfEmpty()` — **non-destructive** BBT patch: fills only
  empty days, never overwrites a hand-entered reading, never clobbers a day's
  flow/symptoms. (The whole-row `upsert` would erase those, hence a new method.)
- Settings → **Health & wearables → Import temperature** tile.
- Android: `READ_BODY_TEMPERATURE` permission, Health Connect rationale
  intent-filter + `VIEW_PERMISSION_USAGE` alias, HC package `<queries>` entry,
  `minSdk` raised to **26**. **No INTERNET added.**
- iOS: `NSHealthShareUsageDescription` in `Info.plist`.

## Privacy note (important)

- Health Connect reads are **local IPC**, not network. The `health` plugin
  declares **no** Android permissions, so this feature adds **no INTERNET**.
- ⚠️ Separately, the merged release APK *already* contains `INTERNET` — injected
  by `google_mobile_ads` (ads need it). So the truthful store/privacy claim is
  **"your data never leaves the device,"** not "the app can't reach the network."
  This feature does not change that posture.

## Android — verify on a phone

1. Install **Health Connect** (Play Store) if not present; log/seed a body-temperature reading.
2. `flutter run` on an Android 8.0+ (API 26+) device.
3. Settings → Health & wearables → **Import temperature** → grant the permission prompt.
4. Expect a snackbar: "Imported N temperature readings" (or "No new … to import").
5. Confirm the values land on the right days (Insights BBT chart / that day's log)
   and that a day you'd typed a BBT into by hand is **not** overwritten.
6. Confirm the permission screen (Android 14+: Settings → Security & privacy →
   Permission manager → deep-link) shows LunaTrack's rationale.

## iOS — verify on a device

1. In **Xcode → Runner → Signing & Capabilities**, add the **HealthKit** capability
   (writes the `com.apple.developer.healthkit` entitlement — not committable from here).
2. `flutter run` on a real iPhone (HealthKit is unavailable in the Simulator).
3. Same import flow; iOS shows the HealthKit share sheet.

## Known follow-ups (not built)

- Only body temperature is imported. Weight / period-flow import are future adds.
- Unit handling assumes °C (`BODY_TEMPERATURE` → `DEGREE_CELSIUS`); confirm the
  display unit matches the manual-entry field on a device with °F system settings.
- No background/auto sync — import is a manual, user-initiated pull.
