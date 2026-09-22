import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guard on the Android adaptive launcher icon.
///
/// This exists because the defect it catches has shipped twice. Running
/// `dart run flutter_launcher_icons` REWRITES
/// `mipmap-anydpi-v26/ic_launcher.xml` and puts back a 16% inset on the
/// foreground and monochrome layers. `assets/icon/icon_foreground.png` already
/// places the artwork at 66% of its canvas, so that inset pads the safe zone a
/// second time and the logo renders at roughly 45% — small, floating, and
/// obviously wrong, but only on a device or in a launcher preview. Nothing else
/// in the suite looks at this file.
///
/// If this test fails right after regenerating icons, the fix is to restore the
/// file, not to relax the test.
void main() {
  final xml = File(
    'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
  );

  test('the adaptive icon exists and declares all three layers', () {
    expect(xml.existsSync(), isTrue);
    final s = xml.readAsStringSync();
    expect(s, contains('<background android:drawable="@color/ic_launcher_background"/>'));
    expect(s, contains('<foreground android:drawable="@drawable/ic_launcher_foreground"/>'));
    expect(s, contains('<monochrome android:drawable="@drawable/ic_launcher_monochrome"/>'));
  });

  test('no inset wrapper — the source art already carries its safe zone', () {
    // Checked against the markup only, so a mention of the word "inset" in the
    // file's explanatory comment does not trip it.
    final body = xml
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    expect(
      body.contains('<inset'),
      isFalse,
      reason: 'flutter_launcher_icons has re-added its 16% inset. Restore '
          'ic_launcher.xml; do not accept the generated version.',
    );
  });

  test('the launcher background matches the brand pink in colors.xml', () {
    // Three files have to agree: this colour resource, the
    // `adaptive_icon_background` in flutter_launcher_icons.yaml (which
    // regenerates the resource from its own value), and Brand.pink.
    final colors =
        File('android/app/src/main/res/values/colors.xml').readAsStringSync();
    expect(
      colors,
      contains('<color name="ic_launcher_background">#F489AF</color>'),
    );
    final yaml = File('flutter_launcher_icons.yaml').readAsStringSync();
    expect(yaml, contains('adaptive_icon_background: "#F489AF"'));
  });
}
