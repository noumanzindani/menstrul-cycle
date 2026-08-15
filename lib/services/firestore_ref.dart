import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// The named Firestore database LunaTrack owns.
///
/// The Firebase project (`teddy-2-20649`) is shared with unrelated apps.
/// Firestore's `(default)` database has exactly ONE ruleset for the whole
/// project, so a permissive rule written for any of those apps would expose
/// LunaTrack's menstrual logs. A NAMED database carries its own independent
/// ruleset, which is the only isolation available without a new project.
///
/// ## Why `-db`, and why this is not cosmetic
///
/// The first attempt used the id `lunatrack`, created with `gcloud firestore
/// databases create`. That database never bound to its ruleset: the release
/// `cloud.firestore/lunatrack` existed and pointed at the compiled rules, yet
/// the database denied EVERY request — including one deployed under a literal
/// `allow read: if true`. It was running deny-all and ignoring the release, so
/// no rules edit could ever have fixed it. A database created through Firebase
/// itself does bind. Compare Cloud Storage, where the same thing is explicit:
/// a gcloud-created bucket needs a `buckets:addFirebase` call before Firebase
/// governs it. Firestore has no public equivalent, so the creation path IS the
/// registration, and it cannot be repaired after the fact.
///
/// If this id ever needs changing again, note that it is pinned in five other
/// places — `test/firestore_ref_test.dart`, `functions/index.js`
/// (`LUNA_DATABASE_ID`, asserted equal to this constant by
/// `firebase_test/purge.test.mjs`), `firebase_test/emulator.mjs`,
/// `firebase_test/purge_mutation_check.mjs`, and `firebase.json`.
const String kLunaDatabaseId = 'lunatrack-db';

/// The ONLY Firestore handle the app may use.
///
/// `FirebaseFirestore.instance` targets `(default)` — using it anywhere writes
/// health data to the wrong database under the wrong rules. Always call this.
FirebaseFirestore lunaFirestore() => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: kLunaDatabaseId,
    );

/// Destroys Firestore's ON-DEVICE cache — the copy of `users/{uid}/…` the SDK
/// keeps *outside* SQLCipher.
///
/// Wiping drift is not "everything on this device is erased". Firestore's local
/// persistence is enabled by default on mobile and physically holds every
/// document this app has read or written — `users/{uid}/dailyLogs` and
/// `users/{uid}/settings/current` among them — in an **unencrypted** SDK store,
/// while drift itself is encrypted at rest. Without this, a device wipe that
/// claims total erasure leaves the user's menstrual history sitting on the
/// device in the clear.
///
/// ## Sequencing (this is the whole difficulty)
///
/// 1. `clearPersistence()` **fails while the client is running**, so
///    `terminate()` has to come first.
/// 2. After `terminate()` the instance accepts NOTHING but `clearPersistence()`
///    — every other call throws. So this must be the **last** Firestore
///    operation in whatever flow calls it: the deletion marker write, the
///    marker read, and the final sync must all have completed already. In
///    `AccountSection._requestDeletion` that means after `suspend()` (which
///    proves no run is still writing), after `requestDeletion()` has been
///    acknowledged, and after `signOut()`.
/// 3. `terminate()` alone does not cancel queued writes — the SDK would resume
///    sending them next launch. `clearPersistence()` discards them, which is
///    the point: an offline-queued push of health data must not outlive the
///    wipe either.
///
/// ## Afterwards
///
/// The next `lunaFirestore()` use in this process gets a working client:
/// FlutterFire's native `terminate` handler drops the instance from its own
/// registry (`FlutterFirebaseFirestorePlugin.terminate` →
/// `destroyCachedFirebaseFirestoreInstanceForKey`), and the platform SDK
/// likewise unregisters a terminated instance, so `getInstance` builds a fresh
/// one. That is belt-and-braces rather than load-bearing: both callers end in a
/// state where nothing touches Firestore again without an explicit user action
/// (signing in, or turning sync back on from Settings → Account).
///
/// Throws whenever [lunaFirestore] does — a build with no initialized Firebase
/// app. Callers treat that as "there is no cache to clear".
Future<void> clearLunaFirestoreCache() async {
  final firestore = lunaFirestore();
  await firestore.terminate();
  await firestore.clearPersistence();
}
