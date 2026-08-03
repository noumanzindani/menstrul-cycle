import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// The named Firestore database LunaTrack owns.
///
/// The Firebase project (`hbgapp-c3c88`) is shared with four unrelated apps.
/// Firestore's `(default)` database has exactly ONE ruleset for the whole
/// project, so a permissive rule written for any of those apps would expose
/// LunaTrack's menstrual logs. A NAMED database carries its own independent
/// ruleset, which is the only isolation available without a new project.
const String kLunaDatabaseId = 'lunatrack';

/// The ONLY Firestore handle the app may use.
///
/// `FirebaseFirestore.instance` targets `(default)` — using it anywhere writes
/// health data to the wrong database under the wrong rules. Always call this.
FirebaseFirestore lunaFirestore() => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: kLunaDatabaseId,
    );
