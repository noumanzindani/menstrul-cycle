/// Whether this build has a usable Firebase app.
///
/// Decided EXACTLY ONCE, in `main.dart`'s `initializeFirebase()` (the try/catch
/// around `Firebase.initializeApp()`), and threaded through the app from there:
/// into `LunaTrackApp.firebaseAvailable` (which picks
/// `FirebaseAuthService`/`UnavailableAuthService` for `AuthProvider`) and, via a
/// single `Provider<FirebaseAvailability>` planted alongside the rest of
/// `main.dart`'s providers, into `AccountSection` (which shows "Cloud sync
/// unavailable on this device" instead of the normal on/off tile).
///
/// This class exists so that fact is a single value passed around, not a
/// question answered twice by two independent null-checks that could disagree
/// -- exactly the failure shape this subsystem has shipped before. Nothing
/// outside `main.dart` may compute a fresh answer; every consumer reads this.
class FirebaseAvailability {
  const FirebaseAvailability(this.available);

  final bool available;
}
