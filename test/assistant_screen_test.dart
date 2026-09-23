import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/screens/assistant/analysis_chat_view.dart';
import 'package:menstrul_track/screens/assistant/assistant_backend.dart';
import 'package:menstrul_track/screens/assistant/assistant_chat_screen.dart';
import 'package:menstrul_track/screens/assistant/assistant_screen.dart';
import 'package:menstrul_track/services/media_analysis.dart';
import 'package:menstrul_track/theme/app_theme.dart';

import 'support/fake_assistant_backend.dart';

/// The conversation list. Everything behind it is [FakeAssistantBackend].
void main() {
  AssistantConversation convo(
    String id, {
    String? title,
    String? subtitle,
    AttachmentRef? first,
    bool coverGone = false,
  }) =>
      AssistantConversation(
        id: id,
        updatedAt: DateTime.now(),
        title: title,
        subtitle: subtitle,
        firstAttachment: first,
        cover: first == null || coverGone
            ? null
            : fakeMedia(first.mediaId,
                kind: first.kind == AttachmentKind.video ? 'video' : 'image'),
      );

  Future<void> pump(WidgetTester tester, FakeAssistantBackend backend) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: AssistantScreen(backend: backend),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('each row shows a thumbnail, a title and the first answer',
      (tester) async {
    await pump(
      tester,
      FakeAssistantBackend(conversations: [
        convo('a',
            title: 'Is this normal?',
            subtitle: 'Cycles vary.',
            first: const AttachmentRef.image('p1')),
        convo('b', subtitle: 'A pink pattern.'),
      ]),
    );

    final a = find.byKey(const Key('assistant-conversation-a'));
    expect(find.descendant(of: a, matching: find.text('Is this normal?')),
        findsOneWidget);
    expect(find.descendant(of: a, matching: find.text('Cycles vary.')),
        findsOneWidget);
    expect(find.descendant(of: a, matching: find.byType(Image)),
        findsOneWidget);

    final b = find.byKey(const Key('assistant-conversation-b'));
    expect(find.descendant(of: b, matching: find.text('Photo description')),
        findsOneWidget,
        reason: 'a conversation with no words of its own is named for what '
            'it started as');
  });

  testWidgets('a deleted first photo reads as removed, not loading',
      (tester) async {
    await pump(
      tester,
      FakeAssistantBackend(conversations: [
        convo('a',
            title: 'hi', first: const AttachmentRef.image('p1'), coverGone: true),
      ]),
    );
    expect(find.byIcon(Icons.hide_image_outlined), findsOneWidget);
  });

  testWidgets('tapping a row resumes that conversation', (tester) async {
    final backend = FakeAssistantBackend(
      conversations: [convo('a', title: 'hi')],
      saved: {
        'a': const [ChatEntry.user('hi'), ChatEntry.reply('Hello.')],
      },
    );
    await pump(tester, backend);

    await tester.tap(find.byKey(const Key('assistant-conversation-a')));
    await tester.pumpAndSettle();

    expect(find.byType(AssistantChatScreen), findsOneWidget);
    expect(find.text('Hello.'), findsOneWidget);
  });

  testWidgets('New conversation opens an empty chat, and the list reloads '
      'on return', (tester) async {
    final backend = FakeAssistantBackend();
    await pump(tester, backend);

    await tester.tap(find.byKey(const Key('assistant-new-conversation')));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantChatScreen), findsOneWidget);
    expect(backend.calls.where((c) => c == 'open'), isEmpty);

    backend.list.add(convo('fresh', title: 'Just asked'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Just asked'), findsOneWidget);
  });

  testWidgets('a conversation saved elsewhere (Describe) appears without '
      'leaving the list', (tester) async {
    final backend = FakeAssistantBackend();
    await pump(tester, backend);
    expect(find.byKey(const Key('assistant-empty')), findsOneWidget);

    backend.list.add(convo('d', subtitle: 'A pink pattern.'));
    backend.changed();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assistant-conversation-d')), findsOneWidget);
  });

  testWidgets('signing in after it was built loads the list', (tester) async {
    final backend = FakeAssistantBackend(
        available: false, conversations: [convo('a', title: 'hi')]);
    await pump(tester, backend);
    expect(find.byKey(const Key('assistant-unavailable')), findsOneWidget);

    backend.available = true;
    await pump(tester, backend); // the rebuild a sign-in causes

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('assistant-conversation-a')), findsOneWidget);
  });

  group('delete', () {
    Future<void> longPress(WidgetTester tester) async {
      await tester.longPress(find.byKey(const Key('assistant-conversation-a')));
      await tester.pumpAndSettle();
    }

    testWidgets('long-press, confirm, and the conversation is gone',
        (tester) async {
      final backend =
          FakeAssistantBackend(conversations: [convo('a', title: 'hi')]);
      await pump(tester, backend);
      await longPress(tester);

      await tester.tap(find.byKey(const Key('assistant-delete-confirm')));
      await tester.pumpAndSettle();

      expect(backend.deleted, ['a']);
      expect(find.byKey(const Key('assistant-conversation-a')), findsNothing);
    });

    testWidgets('cancel keeps it', (tester) async {
      final backend =
          FakeAssistantBackend(conversations: [convo('a', title: 'hi')]);
      await pump(tester, backend);
      await longPress(tester);

      await tester.tap(find.byKey(const Key('assistant-delete-cancel')));
      await tester.pumpAndSettle();

      expect(backend.deleted, isEmpty);
      expect(find.byKey(const Key('assistant-conversation-a')), findsOneWidget);
    });

    testWidgets('both buttons fit a 360dp phone', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pump(tester,
          FakeAssistantBackend(conversations: [convo('a', title: 'hi')]));
      await longPress(tester);

      expect(tester.takeException(), isNull);
      for (final key in ['assistant-delete-confirm', 'assistant-delete-cancel']) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(rect.left, greaterThanOrEqualTo(0), reason: key);
        expect(rect.right, lessThanOrEqualTo(360), reason: key);
        expect(rect.bottom, lessThanOrEqualTo(800), reason: key);
      }
      // Each wrapped in Expanded: a bare FilledButton in a Row demands
      // infinite width and pushes its neighbour off screen.
      expect(
        find.ancestor(
          of: find.byKey(const Key('assistant-delete-confirm')),
          matching: find.byType(Expanded),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('an empty list says what the assistant is for', (tester) async {
    await pump(tester, FakeAssistantBackend());
    expect(find.byKey(const Key('assistant-empty')), findsOneWidget);
    expect(find.byKey(const Key('assistant-new-conversation')), findsOneWidget);
  });

  testWidgets('unavailable is a neutral state with nothing to tap',
      (tester) async {
    final backend = FakeAssistantBackend(available: false);
    await pump(tester, backend);

    expect(find.byKey(const Key('assistant-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('assistant-new-conversation')), findsNothing);
    expect(backend.calls, isNot(contains('list')));
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });
}
