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

  testWidgets('the Allow button is actually on screen', (tester) async {
    // The regression. Before the fix this button was laid out past the right
    // edge and clipped, so the sheet offered no way to say yes.
    await setPhoneSize(tester);
    await openSheet(tester);

    final allow = find.byKey(const Key('analysis-consent-allow'));
    expect(allow, findsOneWidget);

    final rect = tester.getRect(allow);
    final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(rect.left, greaterThanOrEqualTo(0.0));
    expect(
      rect.right,
      lessThanOrEqualTo(screen),
      reason: 'Allow is off the right edge — consent cannot be granted',
    );
    expect(rect.width, greaterThan(0.0));
  });

  testWidgets('both choices are on screen and neither is hidden',
      (tester) async {
    await setPhoneSize(tester);
    await openSheet(tester);

    final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final label in ['Not now', 'Allow']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0.0), reason: '$label off left');
      expect(rect.right, lessThanOrEqualTo(screen), reason: '$label off right');
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
}
