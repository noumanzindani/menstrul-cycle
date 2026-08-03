# menstrul_track

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Firebase setup

`android/app/google-services.json` is intentionally gitignored (it identifies the
Firebase project). To build from a fresh clone, download it from the Firebase
console: project `hbgapp-c3c88` → Project settings → the `com.lunatrack.app`
Android app → `google-services.json`, and place it at `android/app/`.

LunaTrack uses the **named** Firestore database `lunatrack`, not `(default)`.
