import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/media_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/media_provider.dart';
import 'package:menstrul_track/screens/media/media_timeline_screen.dart';
import 'package:menstrul_track/services/media_limits.dart';
import 'package:menstrul_track/services/media_upload_service.dart';
import 'package:menstrul_track/widgets/ad_banner.dart';
import 'package:menstrul_track/widgets/media_tile.dart';

/// The media timeline, pumped with NO Firebase app — which is the state of
/// every test harness here. That it renders at all is the point of the seams.
void main() {
  late AppDatabase db;
  late MediaRepository repo;
  late MediaProvider provider;

  const uid = 'uid-1';
  String idOf(String c) => c * 32;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MediaRepository(db);
    provider = MediaProvider(repo);
  });
  tearDown(() => db.close());

  Future<void> seed(
    String id, {
    MediaKind kind = MediaKind.image,
    bool withThumb = true,
    DateTime? capturedAt,
    int? durationMs,
  }) =>
      repo.upsert(
        id: id,
        uid: uid,
        kind: kind,
        storagePath: 'users/$uid/media/$id/original.jpg',
        thumbPath: 'users/$uid/media/$id/thumb.jpg',
        capturedAt: capturedAt ?? DateTime(2026, 6, 1),
        durationMs: durationMs,
        thumbnail:
            withThumb ? Uint8List.fromList(_tinyPng) : null,
      );

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<MediaProvider>.value(value: provider),
        ],
        child: MaterialApp(home: child),
      );

  group('rendering', () {
    testWidgets('shows a tile per item and NO ad banner', (tester) async {
      await seed(idOf('a'));
      await seed(idOf('b'));
      await provider.setUid(uid);

      await tester.pumpWidget(wrap(const MediaTimelineScreen()));
      await tester.pumpAndSettle();

      // Positive AND negative. This file exists partly because an earlier
      // ad-placement test only checked that the banner hid, and never that the
      // content it was hiding from actually rendered.
      expect(find.byKey(const Key('media-grid')), findsOneWidget);
      expect(find.byType(MediaTile), findsNWidgets(2));
      expect(find.byType(AdBanner), findsNothing);
    });

    testWidgets('shows the empty state with no items', (tester) async {
      await provider.setUid(uid);

      await tester.pumpWidget(wrap(MediaTimelineScreen(
        onAdd: () async => const MediaUploadOutcome(),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(MediaTile), findsNothing);
      expect(find.textContaining('stored in your account'), findsOneWidget);
    });

    testWidgets('a video tile shows its duration, not a poster', (tester) async {
      await seed(idOf('v'), kind: MediaKind.video, withThumb: false,
          durationMs: 42000);
      await provider.setUid(uid);

      await tester.pumpWidget(wrap(const MediaTimelineScreen()));
      await tester.pumpAndSettle();

      expect(find.text('0:42'), findsOneWidget);
    });

    testWidgets('renders a thumbnail-less item without crashing',
        (tester) async {
      // A second device pulls metadata before any thumbnail has been hydrated.
      await seed(idOf('a'), withThumb: false);
      await provider.setUid(uid);

      await tester.pumpWidget(wrap(const MediaTimelineScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(MediaTile), findsOneWidget);
    });
  });

  group('the cloud-unavailable path', () {
    testWidgets('renders and disables Add when there is no cloud',
        (tester) async {
      // The local-only hatch. The entry point is hidden in that build, but the
      // screen must not crash if it is reached, and must explain itself.
      await provider.setUid(null);

      await tester.pumpWidget(wrap(const MediaTimelineScreen()));
      await tester.pumpAndSettle();

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNull);
      expect(find.textContaining("can't reach it"), findsOneWidget);
    });

    testWidgets('a failing refresh still leaves a usable screen',
        (tester) async {
      await seed(idOf('a'));
      await provider.setUid(uid);

      await tester.pumpWidget(wrap(MediaTimelineScreen(
        onRefresh: () async => throw StateError('offline'),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(MediaTile), findsOneWidget);
    });
  });

  group('adding', () {
    testWidgets('reports how many files were dropped by the pick limit',
        (tester) async {
      await provider.setUid(uid);

      await tester.pumpWidget(wrap(MediaTimelineScreen(
        onAdd: () async => const MediaUploadOutcome(dropped: 3),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // A silent truncation reads as "we took everything".
      expect(find.textContaining('3 not added'), findsOneWidget);
    });

    testWidgets('explains a refusal in the user\'s own terms', (tester) async {
      await provider.setUid(uid);

      await tester.pumpWidget(wrap(MediaTimelineScreen(
        onAdd: () async => const MediaUploadOutcome(
          rejected: [MediaRejection(MediaRefusal.tooLong)],
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('under a minute'), findsOneWidget);
    });

    testWidgets('a declined-sync account is told, not shown an error',
        (tester) async {
      await provider.setUid(uid);

      await tester.pumpWidget(wrap(MediaTimelineScreen(
        onAdd: () async =>
            const MediaUploadOutcome(blocked: MediaUploadBlock.syncDeclined),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('keep your data on this device'),
          findsOneWidget);
    });

    testWidgets('a successful add says nothing and refreshes the grid',
        (tester) async {
      await provider.setUid(uid);

      await tester.pumpWidget(wrap(MediaTimelineScreen(
        onAdd: () async {
          await seed(idOf('a'));
          return MediaUploadOutcome(uploadedIds: [idOf('a')]);
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(MediaTile), findsOneWidget);
    });

    testWidgets('an add that throws is reported, not swallowed', (tester) async {
      await provider.setUid(uid);

      await tester.pumpWidget(wrap(MediaTimelineScreen(
        onAdd: () async => throw StateError('boom'),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.textContaining("didn't upload"), findsOneWidget);
    });
  });

  testWidgets('opens an item when a tile is tapped', (tester) async {
    await seed(idOf('a'));
    await provider.setUid(uid);
    String? opened;

    await tester.pumpWidget(wrap(MediaTimelineScreen(
      onOpen: (_, item) => opened = item.id,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MediaTile));
    await tester.pumpAndSettle();

    expect(opened, idOf('a'));
  });
}

/// The smallest valid PNG, so `Image.memory` has something real to decode.
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
