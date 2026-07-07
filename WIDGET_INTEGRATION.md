# Home-screen widget — device-verify checklist

A glanceable widget showing **"N days until your next period"** (or "Today" /
"Late" / gestational week in pregnancy). The Dart that decides the text is unit-
tested (`test/home_widget_test.dart`); everything below is device-only.

## What was built

- `buildHomeWidgetData(...)` (`lib/services/home_widget_service.dart`) — pure,
  tested: prediction/mode → `{value, caption}`. Pregnancy shows the week and
  never a period countdown.
- `HomeWidgetService.push()` — guarded platform-channel bridge (`saveWidgetData`
  + `updateWidget`); no-ops off-device.
- `HomeWidgetSync` (`lib/widgets/home_widget_sync.dart`) — wraps `AppGate`, pushes
  a deduped snapshot whenever the prediction/settings change.
- **Android (complete):** `LunaWidgetProvider.kt`, `res/layout/luna_widget.xml`,
  `res/drawable/luna_widget_background.xml`, `res/xml/luna_widget_info.xml`, and a
  `<receiver>` in the manifest.
- **iOS (below, manual Xcode step):** the WidgetKit source + target setup.

## Android — verify on a phone

1. `flutter run` on an Android device.
2. Long-press the home screen → **Widgets** → **LunaTrack** → drag the widget out.
3. It should show the countdown (e.g. "5 / days to your period"). Log/change a
   period in-app, return to the home screen — the widget updates when the app runs.
4. Tap the widget → the app opens.

**Known limitation:** the countdown refreshes when the app runs, not silently at
midnight (the native provider re-renders the last *pushed* data; it doesn't
recompute). A daily background refresh via `home_widget`'s background callback +
`workmanager` is a follow-up.

## iOS — manual (Android-first project; do this when iOS is in scope)

1. Xcode → File → New → Target → **Widget Extension** named `LunaWidget`
   (uncheck "Include Live Activity").
2. Add an **App Group** (e.g. `group.com.lunatrack.app`) to BOTH the Runner target
   and the widget target (Signing & Capabilities → App Groups).
3. In `main()` (guarded for iOS), call once before the first push:
   `await HomeWidget.setAppGroupId('group.com.lunatrack.app');`
4. Replace the generated widget body with:

```swift
import WidgetKit
import SwiftUI

struct LunaEntry: TimelineEntry {
    let date: Date
    let value: String
    let caption: String
}

struct LunaProvider: TimelineProvider {
    let defaults = UserDefaults(suiteName: "group.com.lunatrack.app")

    func placeholder(in context: Context) -> LunaEntry {
        LunaEntry(date: Date(), value: "—", caption: "Tap to log your period")
    }
    func getSnapshot(in context: Context, completion: @escaping (LunaEntry) -> Void) {
        completion(read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LunaEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .atEnd))
    }
    private func read() -> LunaEntry {
        LunaEntry(
            date: Date(),
            value: defaults?.string(forKey: "value") ?? "—",
            caption: defaults?.string(forKey: "caption") ?? "Tap to log your period"
        )
    }
}

struct LunaWidgetView: View {
    var entry: LunaEntry
    var body: some View {
        VStack(spacing: 2) {
            Text(entry.value).font(.system(size: 30, weight: .bold))
            Text(entry.caption).font(.system(size: 12))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.40, green: 0.31, blue: 0.64))
    }
}

@main
struct LunaWidget: Widget {
    // `kind` MUST equal HomeWidgetService._iosWidgetName ("LunaWidget").
    let kind = "LunaWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LunaProvider()) { entry in
            LunaWidgetView(entry: entry)
        }
        .configurationDisplayName("LunaTrack")
        .description("Days until your next period.")
        .supportedFamilies([.systemSmall])
    }
}
```

5. `flutter run` on a real iPhone; add the widget from the widget gallery.
