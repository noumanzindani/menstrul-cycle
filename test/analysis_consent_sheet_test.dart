import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/screens/media/analysis_consent_sheet.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// The opt-in gate for photo descriptions.
///
/// These run under the REAL app theme at a REAL phone size, and both of those
/// matter. `filledButtonTheme` sets `minimumSize: Size.fromHeight(52)` — an
/// infinite minimum width — which pushed the Allow button off the right edge of
/// a Row and made consent impossible to grant on a device. A test under the
/// default theme, or one that never checks where the button landed, sees
/// nothing wrong.
void main() {
  /// A OnePlus N200: 1080x2400 at 3x, i.e. 360x800 logical.
  Future<void> setPhoneSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<bool?> openSheet(WidgetTester tester) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answer = await showAnalysisConsentSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets(
      'the Allow button is actually on screen, on first paint, with no '
      'scrolling', (tester) async {
    // The original regression: this button was laid out past the RIGHT edge
    // and clipped (a bare FilledButton in a Row demands infinite width), so
    // the sheet offered no way to say yes. A second, later regression reached
    // the same failure a different way: once the disclosure named every
    // tracked category, the whole content column grew taller than the
    // viewport and both buttons landed below the BOTTOM edge — reachable only
    // after a manual scroll, with no on-screen affordance hinting one was
    // needed. Deliberately no `ensureVisible`/scrolling call anywhere in this
    // test: the button must be visible at first paint, unscrolled, because
    // that is what a first-time user actually sees.
    await setPhoneSize(tester);
    await openSheet(tester);

    final allow = find.byKey(const Key('analysis-consent-allow'));
    expect(allow, findsOneWidget);

    final rect = tester.getRect(allow);
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(rect.left, greaterThanOrEqualTo(0.0));
    expect(
      rect.right,
      lessThanOrEqualTo(screenWidth),
      reason: 'Allow is off the right edge — consent cannot be granted',
    );
    expect(
      rect.top,
      greaterThanOrEqualTo(0.0),
      reason: 'Allow is off the top edge — consent cannot be granted',
    );
    expect(
      rect.bottom,
      lessThanOrEqualTo(screenHeight),
      reason: 'Allow is below the fold on first paint — consent cannot be '
          'granted without an unprompted scroll',
    );
    expect(rect.width, greaterThan(0.0));
    expect(rect.height, greaterThan(0.0));
  });

  testWidgets(
      'both choices are on screen and neither is hidden, with no scrolling',
      (tester) async {
    await setPhoneSize(tester);
    await openSheet(tester);

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    for (final label in ['Not now', 'Allow']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0.0), reason: '$label off left');
      expect(rect.right, lessThanOrEqualTo(screenWidth),
          reason: '$label off right');
      expect(rect.top, greaterThanOrEqualTo(0.0), reason: '$label off top');
      expect(rect.bottom, lessThanOrEqualTo(screenHeight),
          reason: '$label off bottom — below the fold with no scroll');
    }
  });

  testWidgets('Allow returns true', (tester) async {
    await setPhoneSize(tester);
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  answer = await showAnalysisConsentSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // No ensureVisible/scroll here, deliberately: the button row is pinned
    // outside the scrollable copy (see analysis_consent_sheet.dart), so it
    // must already be reachable at first paint.
    await tester.tap(find.byKey(const Key('analysis-consent-allow')));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('Not now returns false, and records nothing', (tester) async {
    await setPhoneSize(tester);
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  answer = await showAnalysisConsentSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // No ensureVisible/scroll here either — see the previous test.
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });

  testWidgets('names Google and does not claim the photo is protected',
      (tester) async {
    await setPhoneSize(tester);
    await openSheet(tester);

    expect(find.textContaining('Google'), findsOneWidget);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? '').toLowerCase())
        .join(' ');
    for (final banned in ['safe', 'private', 'secure', 'encrypted', 'protected']) {
      expect(texts, isNot(contains(banned)), reason: 'banned word: $banned');
    }
  });

  testWidgets('names the tracked health data that now travels with the photo',
      (tester) async {
    // The request no longer carries only a photo — it carries the whole
    // tracked health record. Silently widening an existing consent is no
    // consent at all, so the sheet must name what actually travels, not just
    // gesture at "your data".
    await setPhoneSize(tester);
    await openSheet(tester);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? '').toLowerCase())
        .join(' ');

    for (final mustName in [
      'cycle',
      'symptoms',
      'mood',
      'height',
      'weight',
      'discharge',
      'sexual activity',
      'contraception',
      'diagnoses',
      'diary',
      'your age',
      'breastfeeding',
      'pain or bleeding during or after sex',
      'trying to conceive',
      'a recent pregnancy, birth or pregnancy loss',
      'your puberty stage (breast and pubic hair development)',
      // v7: the assistant sends free text and every photo in a conversation,
      // not one photo per Describe tap.
      'messages you type',
      'photos in the conversation',
    ]) {
      expect(texts, contains(mustName), reason: 'sheet must name: $mustName');
    }
  });

  testWidgets('v7: asks about the assistant, not about describing one photo',
      (tester) async {
    await setPhoneSize(tester);
    await openSheet(tester);

    expect(find.text('Use the assistant?'), findsOneWidget);
    expect(find.text('Describe photos?'), findsNothing);
  });

  testWidgets(
      'v7: says when it runs, that photos are resent, that videos stay behind, '
      'and how conversations are kept and deleted', (tester) async {
    // Each line is a behaviour the code has as of consent v7; a sheet that
    // drops one is again asking for agreement to something it did not
    // describe.
    await setPhoneSize(tester);
    await openSheet(tester);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? '').toLowerCase())
        .join(' ');

    for (final mustSay in [
      'only when you send a message in the assistant or tap describe',
      'sent again with every message',
      'about the last 90 days',
      'videos stay in the conversation but are never sent',
      'saved to photos & videos',
      'plain text',
      'you can delete a conversation',
      'deleting a photo deletes the conversations that include it',
    ]) {
      expect(texts, contains(mustSay), reason: 'sheet must say: $mustSay');
    }
  });
}
