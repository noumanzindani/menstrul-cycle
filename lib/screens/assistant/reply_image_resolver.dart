// lib/screens/assistant/reply_image_resolver.dart
import '../../services/reply_image.dart';

/// Turns a model reply's `[image: …]` line into a stored Pexels marker.
///
/// Called twice per answer — from `persistTurn` (inside `analyze`) and from
/// `send` — so results are memoised by reply text: one search per answer,
/// successful or not. A failed search keeps the plain tag, and a stored tag is
/// never re-searched on reopen (it arrives here only from a live reply).
class ReplyImageResolver {
  ReplyImageResolver({
    required Future<ReplyImage?> Function(String query) search,
    required bool enabled,
  })  : _search = search,
        _enabled = enabled;

  /// No key in this build: tags are stripped, nothing is searched.
  factory ReplyImageResolver.off() =>
      ReplyImageResolver(search: (_) async => null, enabled: false);

  final Future<ReplyImage?> Function(String query) _search;
  final bool _enabled;

  /// Bounded: a long session must not grow this forever.
  static const _memoLimit = 64;
  final Map<String, Future<String>> _memo = {};

  Future<String> resolve(String reply, {required String fallbackQuery}) {
    final hit = _memo[reply];
    if (hit != null) return hit;
    if (_memo.length >= _memoLimit) _memo.remove(_memo.keys.first);
    final result = _resolve(reply, fallbackQuery);
    _memo[reply] = result;
    // The resolved text maps to itself, so a second pass is a no-op.
    result.then((out) => _memo[out] = Future.value(out));
    return result;
  }

  Future<String> _resolve(String reply, String fallbackQuery) async {
    final split = splitReply(reply);
    if (split.image != null) return reply;
    if (!_enabled) return split.prose;
    final query = split.query ?? fallbackTopic(fallbackQuery);
    if (query == null) return split.prose;
    final image = await _search(query);
    return image == null
        ? keepTag(split.prose, query)
        : attachImage(split.prose, image);
  }
}
