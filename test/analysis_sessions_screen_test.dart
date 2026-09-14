import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/screens/media/analysis_sessions_screen.dart';

/// The saved-conversations list. No service, no database — every lookup is
/// injected, the same pattern `analysis_result_sheet_test.dart` uses for the
/// chat sheet itself.
void main() {
  // 360x800 + AppTheme.light(), the convention from analysis_consent_sheet_test
  // after a shipped bug where a sheet button rendered off-screen.
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: child));
    await tester.pumpAndSettle();
  }

  AnalysisSession session(String id, {DateTime? updatedAt}) => AnalysisSession(
        id: id,
        uid: 'u1',
        mediaId: 'media-$id',
        consentVersion: 2,
        createdAt: updatedAt ?? DateTime(2026, 9, 1),
        updatedAt: updatedAt ?? DateTime(2026, 9, 1),
      );

  MediaItem media(String id, Uint8List? thumbnail) => MediaItem(
        id: id,
        uid: 'u1',
        kind: 'image',
        storagePath: 'users/u1/media/$id/original.jpg',
        bytes: thumbnail?.length ?? 0,
        capturedAt: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
        thumbnail: thumbnail,
      );

  testWidgets('shows an empty state when there are no sessions', (tester) async {
    await pump(tester, AnalysisSessionsScreen(
      load: () async => const [],
      loadMessages: (_) async => const [],
      loadMedia: (_) async => null,
      onOpen: (_, _) {},
    ));
    expect(find.text('No saved descriptions yet'), findsOneWidget);
  });

  testWidgets('lists a session with the first reply as its subtitle',
      (tester) async {
    final s1 = session('s1');
    await pump(tester, AnalysisSessionsScreen(
      load: () async => [s1],
      loadMessages: (_) async => [
        // The real column is `messageText` (SQL `message_text`) — `text`
        // collides with drift's inherited `Table.text()`, so the field on the
        // generated row class is `messageText`, not `text`.
        AnalysisMessage(
            id: 'a',
            sessionId: 's1',
            role: 'user',
            messageText: 'what is this',
            createdAt: DateTime(2026, 9, 1)),
        AnalysisMessage(
            id: 'b',
            sessionId: 's1',
            role: 'model',
            messageText: 'A close-up of skin.',
            createdAt: DateTime(2026, 9, 1)),
      ],
      loadMedia: (_) async => null,
      onOpen: (_, _) {},
    ));
    expect(find.textContaining('A close-up of skin.'), findsOneWidget);
  });

  testWidgets(
      'renders sessions in the order supplied, with a thumbnail per row',
      (tester) async {
    final s1 = session('s1', updatedAt: DateTime(2026, 9, 3));
    final s2 = session('s2', updatedAt: DateTime(2026, 9, 1));
    final bytes = Uint8List.fromList(_tinyPng);

    await pump(tester, AnalysisSessionsScreen(
      // The repository already returns sessions most-recently-active first;
      // this screen must render them in that order, not re-sort.
      load: () async => [s1, s2],
      loadMessages: (sessionId) async => [
        AnalysisMessage(
          id: '$sessionId-m',
          sessionId: sessionId,
          role: 'model',
          messageText: sessionId == 's1' ? 'First reply' : 'Second reply',
          createdAt: DateTime(2026, 9, 1),
        ),
      ],
      loadMedia: (mediaId) async => media(mediaId, bytes),
      onOpen: (_, _) {},
    ));

    final firstY = tester.getTopLeft(find.text('First reply')).dy;
    final secondY = tester.getTopLeft(find.text('Second reply')).dy;
    expect(firstY, lessThan(secondY));

    // One decoded thumbnail per row, drawn from the media row's blob — never
    // a network read to show a list row.
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('a session with no thumbnail still renders, with a placeholder',
      (tester) async {
    final s1 = session('s1');
    await pump(tester, AnalysisSessionsScreen(
      load: () async => [s1],
      loadMessages: (_) async => const [],
      loadMedia: (_) async => null,
      onOpen: (_, _) {},
    ));

    expect(find.byKey(const Key('analysis-session-s1')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('tapping a row calls onOpen with that session', (tester) async {
    final s1 = session('s1');
    AnalysisSession? opened;
    await pump(tester, AnalysisSessionsScreen(
      load: () async => [s1],
      loadMessages: (_) async => const [],
      loadMedia: (_) async => null,
      onOpen: (context, session) => opened = session,
    ));

    await tester.tap(find.byKey(const Key('analysis-session-s1')));
    await tester.pumpAndSettle();

    expect(opened, same(s1));
  });

  testWidgets('the session row is fully inside the 360x800 viewport',
      (tester) async {
    final s1 = session('s1');
    await pump(tester, AnalysisSessionsScreen(
      load: () async => [s1],
      loadMessages: (_) async => const [],
      loadMedia: (_) async => null,
      onOpen: (_, _) {},
    ));

    final rect = tester.getRect(find.byKey(const Key('analysis-session-s1')));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(800));
  });
}

const List<int> _tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];
