import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/screens/assistant/analysis_chat_view.dart';
import 'package:menstrul_track/services/media_analysis.dart';
import 'package:menstrul_track/services/reply_image.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// The conversation surface, pumped with plain values: it owns no
/// conversation and reaches for no service, which is what makes it testable.
void main() {
  MediaItem media(String id, {String kind = 'image', int? durationMs}) =>
      MediaItem(
        id: id,
        uid: 'u1',
        kind: kind,
        storagePath: 'users/u1/media/$id/original.jpg',
        bytes: 10,
        durationMs: durationMs,
        capturedAt: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
        thumbnail: kind == 'image' ? Uint8List.fromList(_tinyPng) : null,
      );

  Future<void> pump(
    WidgetTester tester, {
    List<ChatEntry> entries = const [],
    VoidCallback? onSend,
    bool pending = false,
    int? messagesLeft,
    String? notice,
    VoidCallback? onAttach,
    List<PendingAttachment> attachments = const [],
    void Function(PendingAttachment)? onRemove,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: AnalysisChatView(
          entries: entries,
          controller: TextEditingController(),
          onSend: onSend,
          pending: pending,
          messagesLeft: messagesLeft,
          notice: notice,
          onAttach: onAttach,
          attachments: attachments,
          onRemoveAttachment: onRemove,
        ),
      ),
    ));
  }

  testWidgets('renders the transcript in order, user turns on the right',
      (tester) async {
    await pump(tester, entries: const [
      ChatEntry.reply('A pink diamond pattern.'),
      ChatEntry.user('what colour is it'),
      ChatEntry.reply('It is pink.'),
    ]);

    final openingY = tester.getTopLeft(find.text('A pink diamond pattern.')).dy;
    final followUpY = tester.getTopLeft(find.text('what colour is it')).dy;
    final secondY = tester.getTopLeft(find.text('It is pink.')).dy;
    expect(openingY, lessThan(followUpY));
    expect(followUpY, lessThan(secondY));

    Iterable<Alignment> alignmentsAbove(Finder text) => find
        .ancestor(of: text, matching: find.byType(Align))
        .evaluate()
        .map((e) => (e.widget as Align).alignment as Alignment);
    expect(alignmentsAbove(find.text('what colour is it')),
        contains(Alignment.centerRight));
    expect(alignmentsAbove(find.text('It is pink.')),
        isNot(contains(Alignment.centerRight)));
  });

  testWidgets('a reply is selectable and never drawn in the error colour',
      (tester) async {
    await pump(tester, entries: const [
      ChatEntry.reply('It is pink.'),
      ChatEntry.error("Couldn't reach the service."),
    ]);

    final scheme = AppTheme.light().colorScheme;
    for (final text in ['It is pink.', "Couldn't reach the service."]) {
      final widget = tester.widget<SelectableText>(
          find.widgetWithText(SelectableText, text));
      expect(widget.style?.color, isNot(scheme.error), reason: text);
    }
  });

  testWidgets('the declined-video notice is neutral, with an info icon',
      (tester) async {
    await pump(tester, entries: const [
      ChatEntry.notice(kVideoDeclinedNotice),
    ]);

    final notice = find.byKey(const Key('analysis-notice'));
    expect(notice, findsOneWidget);
    expect(
      find.descendant(of: notice, matching: find.byIcon(Icons.info_outline)),
      findsOneWidget,
    );
    final text = tester.widget<SelectableText>(
        find.descendant(of: notice, matching: find.byType(SelectableText)));
    expect(text.style?.color, AppTheme.light().colorScheme.onSurfaceVariant);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('the caveat is always shown, with the messages left',
      (tester) async {
    await pump(tester, messagesLeft: 7);

    expect(find.text(kAnalysisCaveat), findsOneWidget);
    expect(find.text('7 of $kMaxAnalysesPerDay messages left today'),
        findsOneWidget);
  });

  testWidgets('the counter is hidden when no budget was supplied',
      (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('analysis-messages-left')), findsNothing);
    expect(find.text(kAnalysisCaveat), findsOneWidget);
  });

  testWidgets('shows the pending indicator while a reply is on its way',
      (tester) async {
    await pump(tester, pending: true, entries: const [ChatEntry.user('hi')]);
    expect(find.byKey(const Key('analysis-pending')), findsOneWidget);
  });

  testWidgets('a null onSend disables the Send button', (tester) async {
    await pump(tester);
    final button = tester.widget<IconButton>(
        find.byKey(const Key('analysis-ask-button')));
    expect(button.onPressed, isNull);
  });

  testWidgets('a notice line renders above the composer', (tester) async {
    await pump(tester, notice: 'You have sent 20 messages today.');
    expect(find.byKey(const Key('analysis-cap-notice')), findsOneWidget);
  });

  testWidgets('the attach button is hidden without onAttach', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('analysis-attach-button')), findsNothing);

    var taps = 0;
    await pump(tester, onAttach: () => taps++);
    await tester.tap(find.byKey(const Key('analysis-attach-button')));
    expect(taps, 1);
  });

  testWidgets('sent attachments show a thumbnail, or say they were removed',
      (tester) async {
    await pump(tester, entries: [
      ChatEntry.user('look', attachments: [
        ChatAttachment(
            mediaId: 'm1', kind: AttachmentKind.image, item: media('m1')),
        const ChatAttachment(mediaId: 'gone', kind: AttachmentKind.image),
      ]),
    ]);

    expect(find.byKey(const Key('analysis-attachment-m1')), findsOneWidget);
    expect(find.byKey(const Key('analysis-attachment-removed-gone')),
        findsOneWidget);
    expect(find.text('Photo removed'), findsOneWidget);
  });

  group('composer chips', () {
    testWidgets('an uploading chip shows a spinner', (tester) async {
      await pump(tester, attachments: const [
        PendingAttachment(key: 'p1', state: PendingState.uploading),
      ]);
      expect(
        find.descendant(
          of: find.byKey(const Key('analysis-chip-p1')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failed chip is neutral, not the error colour',
        (tester) async {
      await pump(tester, attachments: const [
        PendingAttachment(key: 'p1', state: PendingState.failed),
      ]);
      final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('analysis-chip-p1')),
        matching: find.byIcon(Icons.cloud_off_outlined),
      ));
      expect(icon.color, AppTheme.light().colorScheme.onSurfaceVariant);
    });

    testWidgets('a video chip is a play tile with its length', (tester) async {
      await pump(tester, attachments: [
        PendingAttachment(
          key: 'v1',
          state: PendingState.ready,
          item: media('v1', kind: 'video', durationMs: 75000),
        ),
      ]);
      final chip = find.byKey(const Key('analysis-chip-v1'));
      expect(find.descendant(of: chip, matching: find.byIcon(Icons.play_arrow_rounded)),
          findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text('1:15')),
          findsOneWidget);
    });

    testWidgets('the remove control hands back that chip', (tester) async {
      PendingAttachment? removed;
      await pump(
        tester,
        attachments: [
          PendingAttachment(
              key: 'p1', state: PendingState.ready, item: media('m1')),
        ],
        onRemove: (a) => removed = a,
      );
      await tester.tap(find.byKey(const Key('analysis-chip-remove-p1')));
      expect(removed?.key, 'p1');
    });
  });

  testWidgets('fits a 360dp phone with chips and the attach button',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      onSend: () {},
      onAttach: () {},
      messagesLeft: 3,
      notice: 'You have sent 20 messages today. This resets tomorrow.',
      attachments: [
        for (var i = 0; i < 6; i++)
          PendingAttachment(
              key: 'p$i', state: PendingState.ready, item: media('m$i')),
      ],
    );

    expect(tester.takeException(), isNull);
    final send = tester.getRect(find.byKey(const Key('analysis-ask-button')));
    expect(send.right, lessThanOrEqualTo(360));
    expect(send.bottom, lessThanOrEqualTo(800));
  });
  testWidgets('a reply with a photo shows the prose, the photo and a credit '
      'once loaded, and never the marker', (tester) async {
    final text = attachImage(
        'Heat can help.',
        const ReplyImage(
            query: 'heat pad', id: 9, src: 'https://i/9.jpg',
            photographer: 'Sam', photographerUrl: 'https://p/@sam',
            pageUrl: 'https://p/9'));
    await pump(tester, entries: [ChatEntry.reply(text)]);

    expect(find.text('Heat can help.'), findsOneWidget);
    expect(find.textContaining('[[pexels'), findsNothing);
    expect(find.byKey(const Key('reply-image')), findsOneWidget);
  });

  testWidgets('a photo that fails to load hides itself and its credit',
      (tester) async {
    // flutter_test answers every real network request with a 400, so this
    // is the failure path.
    final text = attachImage(
        'Heat can help.',
        const ReplyImage(
            query: 'heat pad', id: 9, src: 'https://i/9.jpg',
            photographer: 'Sam', photographerUrl: 'https://p/@sam',
            pageUrl: 'https://p/9'));
    await pump(tester, entries: [ChatEntry.reply(text)]);
    await tester.pumpAndSettle();

    expect(find.textContaining('Photo by Sam'), findsNothing);
    expect(find.text('Heat can help.'), findsOneWidget);
  });

  testWidgets('a bare tag is never shown as text', (tester) async {
    await pump(tester, entries: const [ChatEntry.reply('Rest.\n[image: sleep]')]);
    expect(find.text('Rest.'), findsOneWidget);
    expect(find.textContaining('[image:'), findsNothing);
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
