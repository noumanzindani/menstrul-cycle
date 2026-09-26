// lib/services/reply_image.dart
import 'dart:convert';

/// One Pexels photo attached to an assistant reply, stored INSIDE the reply's
/// `messageText` as a final marker line so it syncs with no schema or rules
/// change. See docs/superpowers/specs/2026-09-26-assistant-pexels-images-design.md.
class ReplyImage {
  const ReplyImage({
    required this.query,
    required this.id,
    required this.src,
    required this.photographer,
    required this.photographerUrl,
    required this.pageUrl,
  });

  final String query;
  final int id;
  final String src;
  final String photographer;
  final String photographerUrl;
  final String pageUrl;

  Map<String, Object> toJson() => {
        'q': query,
        'id': id,
        'src': src,
        'by': photographer,
        'byUrl': photographerUrl,
        'page': pageUrl,
      };

  /// Null for anything malformed: the marker syncs, so another client may
  /// have written it. Only an https image URL is ever rendered.
  static ReplyImage? fromJson(Object? json) {
    if (json is! Map) return null;
    final q = json['q'], id = json['id'], src = json['src'];
    final by = json['by'], byUrl = json['byUrl'], page = json['page'];
    if (q is! String || id is! int || src is! String || by is! String ||
        byUrl is! String || page is! String) {
      return null;
    }
    if (!src.startsWith('https://')) return null;
    return ReplyImage(
      query: q,
      id: id,
      src: src,
      photographer: by,
      photographerUrl: byUrl,
      pageUrl: page,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReplyImage &&
      other.query == query &&
      other.id == id &&
      other.src == src &&
      other.photographer == photographer &&
      other.photographerUrl == photographerUrl &&
      other.pageUrl == pageUrl;

  @override
  int get hashCode =>
      Object.hash(query, id, src, photographer, photographerUrl, pageUrl);
}

typedef SplitReply = ({String prose, String? query, ReplyImage? image});

final _markerLine = RegExp(r'(?:^|\n)[ \t]*\[\[pexels (.*)\]\][ \t]*\s*$');
final _tagLine = RegExp(r'(?:^|\n)[ \t]*\[image:([^\]\n]*)\][ \t]*\s*$');

/// Splits a stored or live reply into its prose and its image line. Only a
/// marker or tag on the LAST non-empty line counts; anything earlier is prose.
SplitReply splitReply(String text) {
  final marker = _markerLine.firstMatch(text);
  if (marker != null) {
    final prose = text.substring(0, marker.start).trimRight();
    ReplyImage? image;
    try {
      image = ReplyImage.fromJson(jsonDecode(marker.group(1)!));
    } on FormatException {
      image = null;
    }
    return (prose: prose, query: image?.query, image: image);
  }
  final tag = _tagLine.firstMatch(text);
  if (tag != null) {
    final query = tag.group(1)!.trim();
    return (
      prose: text.substring(0, tag.start).trimRight(),
      query: query.isEmpty ? null : query,
      image: null,
    );
  }
  return (prose: text, query: null, image: null);
}

String attachImage(String prose, ReplyImage image) =>
    '$prose\n[[pexels ${jsonEncode(image.toJson())}]]';

String keepTag(String prose, String query) => '$prose\n[image: $query]';

/// What a resumed conversation sends back to Gemini: a marker becomes the
/// plain tag again, so the model sees its own format and never a URL or a
/// photographer's name.
String forModel(String text) {
  final s = splitReply(text);
  if (s.image == null && s.query == null) return s.prose;
  return s.query == null ? s.prose : keepTag(s.prose, s.query!);
}

/// The search used when the model left the tag out: the user's own question,
/// tidied and capped.
String? fallbackTopic(String question) {
  final t = question
      .replaceAll(RegExp(r'[\[\]]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) return null;
  return t.length > 60 ? t.substring(0, 60) : t;
}
