import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/settings/settings_screen.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// The Settings "Backup & restore" section: export opens a passphrase dialog
/// (with confirmation + validation), and restore CONFIRMS before touching data.
void main() {
  late AppDatabase db;
  late SettingsProvider settings;
  late PremiumProvider premium;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
    // Note: no premium.load() — that opens an in_app_purchase platform channel
    // that isn't available under flutter_test (mirrors the Home test harnesses).
    premium = PremiumProvider(SettingsRepository(db));
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<PremiumProvider>.value(value: premium),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Backup & restore section', (tester) async {
    await pump(tester);
    await tester.dragUntilVisible(find.text('Back up my data'),
        find.byType(Scrollable).first, const Offset(0, -300));
    expect(find.text('Backup & restore'), findsOneWidget);
    expect(find.text('Back up my data'), findsOneWidget);
    expect(find.text('Restore from a backup'), findsOneWidget);
  });

  testWidgets('export opens a passphrase dialog and rejects a mismatch',
      (tester) async {
    await pump(tester);
    await tester.dragUntilVisible(find.text('Back up my data'),
        find.byType(Scrollable).first, const Offset(0, -300));
    await tester.tap(find.text('Back up my data'));
    await tester.pumpAndSettle();

    expect(find.text('Set a passphrase'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2)); // passphrase + confirm

    await tester.enterText(fields.at(0), 'abcdef');
    await tester.enterText(fields.at(1), 'different');
    await tester.tap(find.widgetWithText(FilledButton, 'Back up'));
    await tester.pumpAndSettle();

    expect(find.textContaining("don't match"), findsOneWidget);
  });

  testWidgets('restore confirms before doing anything destructive',
      (tester) async {
    await pump(tester);
    await tester.dragUntilVisible(find.text('Restore from a backup'),
        find.byType(Scrollable).first, const Offset(0, -300));
    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();

    // A destructive-action confirmation must appear FIRST (before any file pick).
    expect(find.text('Replace all current data?'), findsOneWidget);
    // Backing out changes nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Replace all current data?'), findsNothing);
  });
}
