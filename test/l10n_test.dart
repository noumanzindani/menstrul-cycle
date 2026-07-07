import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/widgets/disclaimer_banner.dart';

/// The i18n pipeline: ARB → generated AppLocalizations → context.l10n. Proves a
/// converted widget resolves its string through the delegate chain.
void main() {
  testWidgets('a converted widget renders its localized string', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: DisclaimerBanner()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('not a contraceptive method'), findsOneWidget);
  });

  test('English is a supported locale', () {
    expect(AppLocalizations.supportedLocales.map((l) => l.languageCode),
        contains('en'));
  });
}
