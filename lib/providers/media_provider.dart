import 'package:flutter/foundation.dart';

import '../data/media_repository.dart';
import '../db/database.dart';

/// The media timeline's in-memory state, scoped to one signed-in account.
///
/// Mirrors `LogProvider`'s shape — hold the rows, reload after a mutation,
/// notify — with one addition it cannot inherit: an explicit account. Media is
/// cloud-required, so "which account is this" is not incidental context, it is
/// the key every row is filed under, and getting it wrong shows one user
/// another user's photographs.
class MediaProvider extends ChangeNotifier {
  MediaProvider(this._repo);
  final MediaRepository _repo;

  bool _loading = true;
  bool get loading => _loading;

  String? _uid;

  /// The account currently in view. Null when signed out, when Firebase is
  /// unavailable (the local-only hatch), or before the first `setUid`.
  String? get uid => _uid;

  List<MediaItem> _items = const [];

  /// Newest capture first. Empty whenever [uid] is null — there is nothing to
  /// show without an account, because there is no local-only media.
  List<MediaItem> get items => _items;

  /// Points the timeline at [uid], erasing any other account's rows.
  ///
  /// The erase is deliberate and is the reason this is not just `load()`.
  /// Signing out never wipes the device (a rule that protects locally-written
  /// health data), so without this, account A's cached thumbnails would still
  /// be on disk when B signs in. Every read already filters by uid, so this is
  /// the second of two guards, not the only one.
  ///
  /// Re-announcing the SAME uid is not a switch and erases nothing — a resumed
  /// session or a rebuilt provider does that routinely, and treating it as a
  /// switch would delete the user's own timeline.
  Future<void> setUid(String? uid) async {
    final changed = uid != _uid;
    _uid = uid;
    if (changed) await _repo.deleteExcept(uid);
    await reload();
  }

  /// Re-reads the current account's rows. Called after an upload, a delete, or
  /// a pull that wrote straight to the repository.
  Future<void> reload() async {
    // Queries even when signed out — no row can match an empty uid, so the
    // result is the same empty list a special case would produce.
    //
    // Going through the database unconditionally is not defensive padding: it
    // guarantees this method always crosses a real async gap before
    // `notifyListeners()`. `main.dart` drives [setUid] from a `Consumer`
    // builder, and a SYNCHRONOUS notification on that path throws
    // "setState() or markNeedsBuild() called during build". `SyncTrigger`
    // documents the identical hazard for its own state and solves it by never
    // notifying at all; the timeline needs the notification, so it earns it by
    // always awaiting first. An early return for a null uid reintroduces the
    // crash, which is how this was found.
    _items = await _repo.allFor(_uid ?? '');
    _loading = false;
    notifyListeners();
  }
}
