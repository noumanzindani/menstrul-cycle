import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/screens/assistant/analysis_chat_view.dart';
import 'package:menstrul_track/screens/assistant/assistant_backend.dart';
import 'package:menstrul_track/screens/assistant/assistant_chat_screen.dart';
import 'package:menstrul_track/services/media_analysis.dart';
import 'package:menstrul_track/theme/app_theme.dart';

import 'support/fake_assistant_backend.dart';

/// The assistant chat: its composer, its gates and the one-send-in-flight
/// rule. Everything outside the screen is [FakeAssistantBackend].
void main() {
  Future<void> pump(
    WidgetTester tester,
    FakeAssistantBackend backend, {
    String? conversationId,
    List<MediaItem> pending = const [],
    bool adEarned = false,
    bool settle = true,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: AssistantChatScreen(
        backend: backend,
        conversationId: conversationId,
        pendingAttachments: pending,
        adEarned: adEarned,
      ),
    ));
    // A reply held in flight keeps the pending spinner turning, which
    // pumpAndSettle would wait on forever.
    settle ? await tester.pumpAndSettle() : await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) => tester.enterText(
      find.byKey(const Key('analysis-question-field')), text);

  Future<void> tapSend(WidgetTester tester) =>
      tester.tap(find.byKey(const Key('analysis-ask-button')));

  IconButton sendButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.byKey(const Key('analysis-ask-button')));

  group('sending', () {
    testWidgets('shows the message at once, then the answer', (tester) async {
      final backend = FakeAssistantBackend()..gate = Completer();
      await pump(tester, backend);

      await type(tester, 'how long is a cycle?');
      await tapSend(tester);
      await tester.pump();

      expect(find.text('how long is a cycle?'), findsOneWidget);
      expect(find.byKey(const Key('analysis-pending')), findsOneWidget);

      backend.gate!.complete(
          const AssistantReply(AssistantReplyKind.answer, 'Usually 21-35 days.'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('analysis-pending')), findsNothing);
      expect(find.text('Usually 21-35 days.'), findsOneWidget);
      expect(backend.sends.single.conversationId, 'new-chat');
      expect(backend.sends.single.text, 'how long is a cycle?');
    });

    testWidgets('only one send is ever in flight', (tester) async {
      final backend = FakeAssistantBackend()..gate = Completer();
      await pump(tester, backend);

      await type(tester, 'first');
      await tapSend(tester);
      await tester.pump();
      await type(tester, 'second');
      await tapSend(tester);
      await tester.pump();

      // Every send bills and counts against the daily cap, so a double tap
      // must not buy two.
      expect(backend.sends, hasLength(1));
      backend.gate!.complete(backend.reply);
      await tester.pumpAndSettle();
    });

    testWidgets('clears the field, and an empty message is never sent',
        (tester) async {
      final backend = FakeAssistantBackend();
      await pump(tester, backend);

      await type(tester, '   ');
      await tapSend(tester);
      await tester.pumpAndSettle();
      expect(backend.sends, isEmpty);

      await type(tester, 'hello');
      await tapSend(tester);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
          find.byKey(const Key('analysis-question-field')));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('a failure is shown neutrally and can be retried',
        (tester) async {
      final backend = FakeAssistantBackend()
        ..reply = const AssistantReply(
            AssistantReplyKind.failed, "Couldn't reach the service.");
      await pump(tester, backend);

      await type(tester, 'hi');
      await tapSend(tester);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't reach the service."), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsWidgets);

      backend.reply =
          const AssistantReply(AssistantReplyKind.answer, 'Hello.');
      await type(tester, 'hi');
      await tapSend(tester);
      await tester.pumpAndSettle();
      expect(find.text('Hello.'), findsOneWidget);
    });

    testWidgets('the caveat and the messages left are always shown',
        (tester) async {
      final backend = FakeAssistantBackend(messagesLeft: 5);
      await pump(tester, backend);

      expect(find.text(kAnalysisCaveat), findsOneWidget);
      expect(find.text('5 of $kMaxAnalysesPerDay messages left today'),
          findsOneWidget);

      await type(tester, 'hi');
      await tapSend(tester);
      await tester.pumpAndSettle();
      expect(find.text(kAnalysisCaveat), findsOneWidget);
      expect(find.text('4 of $kMaxAnalysesPerDay messages left today'),
          findsOneWidget);
    });

    testWidgets('at the daily cap Send is disabled and says why',
        (tester) async {
      final backend = FakeAssistantBackend(messagesLeft: 0);
      await pump(tester, backend);

      expect(sendButton(tester).onPressed, isNull);
      expect(find.byKey(const Key('analysis-cap-notice')), findsOneWidget);
      expect(find.text(messageForAnalysisBlock(AnalysisBlock.dailyCap)),
          findsOneWidget);
    });

    testWidgets('a declined video shows the neutral notice', (tester) async {
      final backend = FakeAssistantBackend(
          libraryItems: [fakeMedia('v1', kind: 'video', durationMs: 5000)])
        ..reply = const AssistantReply(
            AssistantReplyKind.declined, kVideoDeclinedNotice);
      await pump(tester, backend);

      await tester.tap(find.byKey(const Key('analysis-attach-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Photos & videos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('media-select-v1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('media-select-attach')));
      await tester.pumpAndSettle();
      await tapSend(tester);
      await tester.pumpAndSettle();

      expect(backend.calls, isNot(contains('ad')),
          reason: 'a video is never sent, so it is never billed');
      expect(backend.sends.single.attachments.single.id, 'v1');
      expect(find.byKey(const Key('analysis-notice')), findsOneWidget);
      expect(find.text(kVideoDeclinedNotice), findsOneWidget);
    });
  });

  group('gates', () {
    testWidgets('consent comes before the ad, and the ad before the send',
        (tester) async {
      final backend = FakeAssistantBackend(needsConsent: true);
      await pump(tester, backend);

      await type(tester, 'hi');
      await tapSend(tester);
      await tester.pumpAndSettle();

      expect(backend.calls, ['consent', 'ad', 'send']);
    });

    testWidgets('a declined consent sends nothing and keeps the words',
        (tester) async {
      final backend =
          FakeAssistantBackend(needsConsent: true, consentGranted: false);
      await pump(tester, backend);

      await type(tester, 'hi');
      await tapSend(tester);
      await tester.pumpAndSettle();

      expect(backend.calls, ['consent']);
      final field = tester.widget<TextField>(
          find.byKey(const Key('analysis-question-field')));
      expect(field.controller!.text, 'hi');
    });

    testWidgets('a declined ad sends nothing', (tester) async {
      final backend = FakeAssistantBackend(adEarned: false);
      await pump(tester, backend);

      await type(tester, 'hi');
      await tapSend(tester);
      await tester.pumpAndSettle();

      expect(backend.calls, ['ad']);
    });

    testWidgets('only the first send of a new conversation asks for the ad',
        (tester) async {
      final backend = FakeAssistantBackend();
      await pump(tester, backend);

      await type(tester, 'one');
      await tapSend(tester);
      await tester.pumpAndSettle();
      await type(tester, 'two');
      await tapSend(tester);
      await tester.pumpAndSettle();

      expect(backend.calls, ['ad', 'send', 'send']);
    });

    testWidgets('a resumed conversation never asks for the ad',
        (tester) async {
      final backend = FakeAssistantBackend(saved: {
        'c1': const [
          ChatEntry.user('what colour is it'),
          ChatEntry.reply('It is pink.'),
        ],
      });
      await pump(tester, backend, conversationId: 'c1');

      expect(find.text('It is pink.'), findsOneWidget);
      await type(tester, 'and now?');
      await tapSend(tester);
      await tester.pumpAndSettle();

      expect(backend.calls, ['open', 'send']);
      expect(backend.sends.single.conversationId, 'c1');
    });
  });

  testWidgets('a pending photo sends the default question by itself',
      (tester) async {
    final photo = fakeMedia('p1');
    final backend = FakeAssistantBackend()..gate = Completer();
    await pump(tester, backend,
        pending: [photo], adEarned: true, settle: false);
    await tester.pump();

    expect(backend.sends.single.text, '');
    expect(backend.sends.single.originMediaId, 'p1');
    expect(backend.sends.single.attachments.single.id, 'p1');
    expect(backend.calls, ['send'],
        reason: 'Describe already asked for consent and the ad');
    expect(find.text(kDefaultAnalysisQuestion), findsOneWidget);
    expect(find.byKey(const Key('analysis-attachment-p1')), findsOneWidget);

    backend.gate!.complete(
        const AssistantReply(AssistantReplyKind.answer, 'A pink pattern.'));
    await tester.pumpAndSettle();
    expect(find.text('A pink pattern.'), findsOneWidget);
  });

  group('attachments', () {
    Future<void> openAttach(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('analysis-attach-button')));
      await tester.pumpAndSettle();
    }

    testWidgets('the attach sheet offers the four sources', (tester) async {
      await pump(tester, FakeAssistantBackend());
      await openAttach(tester);

      for (final label in [
        'Take photo',
        'Record video',
        'Choose from gallery',
        'From Photos & videos',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('with no picker only Photos & videos is offered',
        (tester) async {
      await pump(tester, FakeAssistantBackend(canCapture: false));
      await openAttach(tester);

      expect(find.text('Take photo'), findsNothing);
      expect(find.text('From Photos & videos'), findsOneWidget);
    });

    testWidgets('an upload shows a spinner chip and holds Send',
        (tester) async {
      final backend = FakeAssistantBackend()..captureGate = Completer();
      await pump(tester, backend);
      await type(tester, 'look at this');
      await openAttach(tester);
      await tester.tap(find.text('Take photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(backend.calls, contains('capture:camera'));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(sendButton(tester).onPressed, isNull,
          reason: 'a message must not leave without the photo it is about');

      backend.captureGate!
          .complete(AttachOutcome(items: [fakeMedia('p9')]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('analysis-chip-p9')), findsOneWidget);
      expect(sendButton(tester).onPressed, isNotNull);

      await tapSend(tester);
      await tester.pumpAndSettle();
      expect(backend.sends.single.attachments.single.id, 'p9');
      expect(find.byKey(const Key('analysis-chip-p9')), findsNothing,
          reason: 'sent attachments leave the composer');
    });

    testWidgets('a failed upload leaves a neutral chip that can be removed',
        (tester) async {
      final backend = FakeAssistantBackend()
        ..captureOutcome = const AttachOutcome(failed: 1);
      await pump(tester, backend);
      await openAttach(tester);
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      final chip = find.byIcon(Icons.cloud_off_outlined);
      expect(chip, findsOneWidget);
      await tester.tap(find.byTooltip('Remove attachment').first);
      await tester.pumpAndSettle();
      expect(chip, findsNothing);
    });

    testWidgets('a cancelled pick leaves nothing behind', (tester) async {
      final backend = FakeAssistantBackend();
      await pump(tester, backend);
      await openAttach(tester);
      await tester.tap(find.text('Record video'));
      await tester.pumpAndSettle();

      expect(backend.calls, contains('capture:videoCamera'));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    });

    testWidgets('with sync off, the composer says so', (tester) async {
      final backend = FakeAssistantBackend()
        ..captureOutcome = AttachOutcome(
            message: messageForAnalysisBlock(AnalysisBlock.syncOff));
      await pump(tester, backend);
      await openAttach(tester);
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();

      expect(find.text(messageForAnalysisBlock(AnalysisBlock.syncOff)),
          findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    });

    testWidgets('never offers more than a message can carry', (tester) async {
      final backend = FakeAssistantBackend(libraryItems: [
        for (var i = 0; i < 8; i++) fakeMedia('m$i'),
      ]);
      await pump(tester, backend);
      await openAttach(tester);
      await tester.tap(find.text('From Photos & videos'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        final tile = find.byKey(Key('media-select-m$i'));
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('media-select-attach')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('analysis-chip-m5')), findsOneWidget);
      expect(find.byKey(const Key('analysis-chip-m6')), findsNothing);
      expect(
        tester
            .widget<IconButton>(
                find.byKey(const Key('analysis-attach-button')))
            .onPressed,
        isNull,
      );
    });
  });

  testWidgets('closing the chat forgets its in-memory history',
      (tester) async {
    final backend = FakeAssistantBackend();
    await pump(tester, backend);
    await tester.pumpWidget(const SizedBox());
    expect(backend.ended, ['new-chat']);
  });

  testWidgets('fits a 360dp phone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pump(tester, FakeAssistantBackend(messagesLeft: 0));
    expect(tester.takeException(), isNull);
    final attach =
        tester.getRect(find.byKey(const Key('analysis-attach-button')));
    final send = tester.getRect(find.byKey(const Key('analysis-ask-button')));
    expect(attach.left, greaterThanOrEqualTo(0));
    expect(send.right, lessThanOrEqualTo(360));
    expect(send.bottom, lessThanOrEqualTo(800));
  });
}
