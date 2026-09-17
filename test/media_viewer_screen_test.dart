import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/screens/media/media_viewer_screen.dart';
import 'package:menstrul_track/services/media_analysis.dart';
import 'package:menstrul_track/services/media_analysis_service.dart';

/// Describe's resume behaviour: whether a saved conversation short-circuits a
/// fresh network call. No service, no database, no Firebase — [analyze] and
/// [loadExistingTurns] are injected, the same seam every other media screen
/// test in this repo uses.
void main() {
  late Directory tempDir;
  late File imageFile;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('media_viewer_test');
    imageFile = File('${tempDir.path}/photo.png');
    await imageFile.writeAsBytes(_tinyPng);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  MediaItem item() => MediaItem(
        id: 'm1',
        uid: 'u1',
        kind: 'image',
        storagePath: 'users/u1/media/m1/original.jpg',
        bytes: _tinyPng.length,
        capturedAt: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
        thumbnail: Uint8List.fromList(_tinyPng),
      );

  Future<void> pumpViewer(
    WidgetTester tester, {
    required Future<AnalysisOutcome> Function(MediaItem, File, String?)
        analyze,
    Future<List<AnalysisTurn>> Function(MediaItem)? loadExistingTurns,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaViewerScreen(
        item: item(),
        load: (_) async => imageFile,
        analyze: analyze,
        needsConsent: () => false,
        loadExistingTurns: loadExistingTurns,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('media-describe')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Describe resumes a saved conversation instead of asking again',
      (tester) async {
    var analyzeCalls = 0;
    await pumpViewer(
      tester,
      analyze: (_, _, _) async {
        analyzeCalls++;
        return const AnalysisOutcome(
          result: AnalysisResult(prose: 'A fresh description.'),
        );
      },
      loadExistingTurns: (_) async => const [
        AnalysisTurn.model('A pink diamond pattern.'),
        AnalysisTurn.user('what colour is it'),
        AnalysisTurn.model('It is pink.'),
      ],
    );

    // The saved transcript is shown...
    expect(find.text('A pink diamond pattern.'), findsOneWidget);
    expect(find.text('what colour is it'), findsOneWidget);
    expect(find.text('It is pink.'), findsOneWidget);
    // ...and nothing new was asked to produce it.
    expect(analyzeCalls, 0);
    expect(find.text('A fresh description.'), findsNothing);
  });

  testWidgets(
      'Describe still asks fresh when there is no saved conversation '
      '(regression)', (tester) async {
    var analyzeCalls = 0;
    await pumpViewer(
      tester,
      analyze: (_, _, _) async {
        analyzeCalls++;
        return const AnalysisOutcome(
          result: AnalysisResult(prose: 'A fresh description.'),
        );
      },
      loadExistingTurns: (_) async => const [],
    );

    expect(analyzeCalls, 1);
    expect(find.text('A fresh description.'), findsOneWidget);
  });

  testWidgets('a null loadExistingTurns behaves exactly as before (regression)',
      (tester) async {
    var analyzeCalls = 0;
    await pumpViewer(
      tester,
      analyze: (_, _, _) async {
        analyzeCalls++;
        return const AnalysisOutcome(
          result: AnalysisResult(prose: 'A fresh description.'),
        );
      },
      loadExistingTurns: null,
    );

    expect(analyzeCalls, 1);
    expect(find.text('A fresh description.'), findsOneWidget);
  });

  testWidgets(
      'a revoked consent still allows reading a saved transcript, but a '
      'follow-up stays blocked', (tester) async {
    var analyzeCalls = 0;
    var requestConsentCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: MediaViewerScreen(
        item: item(),
        load: (_) async => imageFile,
        analyze: (_, _, _) async {
          analyzeCalls++;
          // Simulates `MediaAnalysisService.analyze`'s OWN, authoritative
          // consent gate — the one that still fires no matter what this
          // widget decided, so a follow-up genuinely cannot get through.
          return const AnalysisOutcome(blocked: AnalysisBlock.notConsented);
        },
        // Consent has been revoked (or was never granted).
        needsConsent: () => true,
        requestConsent: (_) async {
          requestConsentCalls++;
          return true;
        },
        loadExistingTurns: (_) async => const [
          AnalysisTurn.model('A pink diamond pattern.'),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('media-describe')));
    await tester.pumpAndSettle();

    // Reading the saved transcript is NOT gated: it renders, and the consent
    // sheet was never invoked to show it.
    expect(find.text('A pink diamond pattern.'), findsOneWidget);
    expect(requestConsentCalls, 0);
    expect(analyzeCalls, 0);

    // A follow-up IS a send, and stays gated: it still reaches `analyze`,
    // whose own consent check (simulated above) refuses it — reading was
    // never what unlocked sending.
    await tester.enterText(
      find.byKey(const Key('analysis-question-field')),
      'what colour is it',
    );
    await tester.tap(find.byKey(const Key('analysis-ask-button')));
    await tester.pumpAndSettle();

    expect(analyzeCalls, 1);
    expect(
      find.text(messageForAnalysisBlock(AnalysisBlock.notConsented)),
      findsOneWidget,
    );
  });
}

/// The smallest valid PNG, so `Image.file` has something real to decode.
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
