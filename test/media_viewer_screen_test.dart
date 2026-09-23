import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/screens/media/media_viewer_screen.dart';
import 'package:menstrul_track/services/media_analysis.dart';
import 'package:menstrul_track/screens/assistant/assistant_chat_screen.dart';

import 'support/fake_assistant_backend.dart';

/// Describe: resume a saved conversation, or run consent then the ad and
/// open a new one with the photo attached. No service, no database, no
/// Firebase — the lookups and the opener are injected, the same seam every
/// other media screen test in this repo uses.
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

  MediaItem item({String kind = 'image'}) => MediaItem(
        id: 'm1',
        uid: 'u1',
        kind: kind,
        storagePath: 'users/u1/media/m1/original.jpg',
        bytes: _tinyPng.length,
        capturedAt: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
        thumbnail: Uint8List.fromList(_tinyPng),
      );

  /// What the viewer asked to open, in order.
  late List<String> calls;

  Future<void> openRecorder(
    BuildContext context, {
    String? conversationId,
    MediaItem? attach,
  }) async {
    calls.add(conversationId != null
        ? 'resume:$conversationId'
        : 'new:${attach?.id}');
  }

  setUp(() => calls = []);

  Future<void> pumpViewer(
    WidgetTester tester, {
    Future<String?> Function(MediaItem)? findConversation,
    Future<void> Function(BuildContext, {String? conversationId, MediaItem? attach})?
        openConversation,
    Future<bool> Function(BuildContext)? earnDescribe,
    bool needsConsent = false,
    Future<bool> Function(BuildContext)? requestConsent,
    Future<String?> Function(MediaItem)? preflight,
    bool tap = true,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaViewerScreen(
        item: item(),
        load: (_) async => imageFile,
        openConversation: openConversation ?? openRecorder,
        findConversation: findConversation,
        needsConsent: () => needsConsent,
        requestConsent: requestConsent,
        earnDescribe: earnDescribe,
        preflight: preflight,
      ),
    ));
    await tester.pumpAndSettle();
    if (!tap) return;
    await tester.tap(find.byKey(const Key('media-describe')));
    await tester.pumpAndSettle();
  }

  Future<bool> Function(BuildContext) recording(String name, bool result) =>
      (_) async {
        calls.add(name);
        return result;
      };

  testWidgets('Describe resumes a saved conversation: no consent, no ad',
      (tester) async {
    await pumpViewer(
      tester,
      findConversation: (_) async => 'c1',
      needsConsent: true,
      requestConsent: recording('consent', true),
      earnDescribe: recording('ad', true),
    );

    // Reading what is already stored sends nothing, so neither the consent
    // gate (which governs SENDING) nor the ad (which pays for a call) applies.
    expect(calls, ['resume:c1']);
  });

  testWidgets('a fresh Describe runs consent, then the ad, then opens the chat '
      'with the photo attached', (tester) async {
    await pumpViewer(
      tester,
      findConversation: (_) async => null,
      needsConsent: true,
      requestConsent: recording('consent', true),
      earnDescribe: recording('ad', true),
    );
    expect(calls, ['consent', 'ad', 'new:m1']);
  });

  testWidgets('at the daily cap, Describe says so and never shows the ad',
      (tester) async {
    final cap = messageForAnalysisBlock(AnalysisBlock.dailyCap);
    await pumpViewer(
      tester,
      findConversation: (_) async => null,
      needsConsent: true,
      requestConsent: recording('consent', true),
      earnDescribe: recording('ad', true),
      preflight: (_) async => cap,
    );
    expect(calls, isEmpty,
        reason: 'an ad watched for a send that cannot happen is a reward '
            'taken and never delivered');
    expect(find.text(cap), findsOneWidget);
  });

  testWidgets('the preflight never blocks resuming a saved conversation',
      (tester) async {
    await pumpViewer(
      tester,
      findConversation: (_) async => 'c1',
      preflight: (_) async =>
          messageForAnalysisBlock(AnalysisBlock.dailyCap),
    );
    expect(calls, ['resume:c1']);
  });

  testWidgets('a declined consent never shows the ad or opens the chat',
      (tester) async {
    await pumpViewer(
      tester,
      needsConsent: true,
      requestConsent: recording('consent', false),
      earnDescribe: recording('ad', true),
    );
    expect(calls, ['consent']);
  });

  testWidgets('a declined ad opens nothing', (tester) async {
    await pumpViewer(tester, earnDescribe: recording('ad', false));
    expect(calls, ['ad'],
        reason: 'a declined reward must not reach the model -- the request '
            'costs real money and the user did not earn it');
  });

  testWidgets('a null gate leaves Describe ungated, as premium gets it',
      (tester) async {
    await pumpViewer(tester);
    expect(calls, ['new:m1']);
  });

  testWidgets('a failed lookup falls through to a fresh conversation',
      (tester) async {
    await pumpViewer(
      tester,
      findConversation: (_) async => throw StateError('db'),
    );
    expect(calls, ['new:m1']);
  });

  testWidgets('no openConversation hides Describe entirely', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaViewerScreen(item: item(), load: (_) async => imageFile),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('media-describe')), findsNothing);
  });

  testWidgets('a video offers no Describe: it could only be declined',
      (tester) async {
    // Held mid-download, where a photo already shows the control (so this
    // fails on the kind check, not on a load error).
    Future<void> pumpKind(String kind) => tester.pumpWidget(MaterialApp(
          key: ValueKey(kind),
          home: MediaViewerScreen(
            item: item(kind: kind),
            load: (_) => Completer<File>().future,
            openConversation: openRecorder,
          ),
        ));

    await pumpKind('image');
    await tester.pump();
    expect(find.byKey(const Key('media-describe')), findsOneWidget);

    await pumpKind('video');
    await tester.pump();
    expect(find.byKey(const Key('media-describe')), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('the chat it opens sends the default question with the photo',
      (tester) async {
    final backend = FakeAssistantBackend();
    await pumpViewer(
      tester,
      openConversation: (context, {conversationId, attach}) =>
          Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AssistantChatScreen(
          backend: backend,
          conversationId: conversationId,
          pendingAttachments: [?attach],
          adEarned: true,
        ),
      )),
    );

    expect(find.byType(AssistantChatScreen), findsOneWidget);
    expect(backend.calls, ['send']);
    expect(backend.sends.single.originMediaId, 'm1');
    expect(backend.sends.single.attachments.single.id, 'm1');
    expect(find.text(kDefaultAnalysisQuestion), findsOneWidget);
    expect(find.text('An answer.'), findsOneWidget);
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
