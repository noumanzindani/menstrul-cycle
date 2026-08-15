import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// The Cloud Storage bucket LunaTrack owns.
///
/// This is the same argument as [kLunaDatabaseId] in `firestore_ref.dart`, and
/// it matters more here, not less.
///
/// The Firebase project is shared with unrelated apps. Firestore's `(default)`
/// database carries one ruleset for the whole project, which is why LunaTrack
/// uses a NAMED database with its own rules. **Cloud Storage has no named
/// databases — rulesets are per BUCKET**, and a project's default bucket ships
/// with a console template that is commonly
/// `allow read, write: if request.auth != null`. In a shared Auth pool that is
/// not a boundary at all: every other app's users hold a valid token, and in
/// Storage rules `read` includes `list`, so a signed-in stranger could
/// enumerate the whole bucket and download any object in it.
///
/// The payload here is unencrypted photographs and video. So LunaTrack writes
/// to a DEDICATED bucket whose ruleset (`storage.rules`) it alone owns.
///
/// Settled 2026-08-12: LunaTrack lives in the shared project `teddy-2-20649`,
/// alongside `com.pocketchange.app`. Sharing the PROJECT is the owner's
/// decision; sharing the BUCKET is not survivable, and this constant is what
/// keeps them apart.
///
/// That project's default bucket (`teddy-2-20649.firebasestorage.app`) already
/// carries a deployed ruleset for an unrelated NGO/donation app — KYC
/// documents, campaign media, organisation logos, two of those paths
/// world-readable. Pointing media at it would both expose photographs under
/// somebody else's `allow read: if true` and overwrite that app's rules on the
/// next `firebase deploy`. So media gets its OWN bucket, and `firebase.json`
/// scopes the storage deploy to it by name for the same reason.
///
/// Residual risk the owner has accepted: rules bind clients, never project IAM.
/// Anyone with console or Admin-SDK access to `teddy-2-20649` — including
/// whoever maintains the other app — can read this bucket.
const String kLunaStorageBucket = 'gs://teddy-2-20649-lunatrack-media';

/// The ONLY Cloud Storage handle the app may use.
///
/// `FirebaseStorage.instance` targets the project's default bucket — using it
/// anywhere writes intimate media into a bucket governed by somebody else's
/// rules. `grep -rn "FirebaseStorage.instance" lib/` must return nothing, the
/// same standing rule as `FirebaseFirestore.instance`.
///
/// Throws when there is no initialized Firebase app — the state of every test
/// harness, which is why nothing outside `media_blob_store.dart` calls this.
FirebaseStorage lunaStorage() => FirebaseStorage.instanceFor(
      app: Firebase.app(),
      bucket: kLunaStorageBucket,
    );
