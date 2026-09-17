// Copyright-free: LunarFlow test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:menstrul_track/services/media_picker_config.dart';

/// A stand-in for any non-Android implementation.
///
/// `ImagePickerPlatform` has no abstract members — every method has a default
/// that throws — so an empty subclass is a legal platform. Nothing here is
/// called; the point is only that it is NOT [ImagePickerAndroid].
class _NotAndroid extends ImagePickerPlatform {}

void main() {
  group('useSystemPhotoPicker', () {
    late ImagePickerPlatform original;

    setUp(() => original = ImagePickerPlatform.instance);
    // The instance is global. Leaving a test's platform installed would leak
    // into every later test in the same shard.
    tearDown(() => ImagePickerPlatform.instance = original);

    test('turns the Android system Photo Picker on', () {
      final android = ImagePickerAndroid();
      expect(
        android.useAndroidPhotoPicker,
        isFalse,
        reason: 'the plugin default — if this ever flips upstream, this whole '
            'file can go',
      );

      ImagePickerPlatform.instance = android;
      useSystemPhotoPicker();

      expect(android.useAndroidPhotoPicker, isTrue);
    });

    test('is safe to call twice', () {
      final android = ImagePickerAndroid();
      ImagePickerPlatform.instance = android;

      useSystemPhotoPicker();
      useSystemPhotoPicker();

      expect(android.useAndroidPhotoPicker, isTrue);
    });

    test('leaves a non-Android platform untouched', () {
      final other = _NotAndroid();
      ImagePickerPlatform.instance = other;

      useSystemPhotoPicker();

      expect(
        ImagePickerPlatform.instance,
        same(other),
        reason: 'iOS and the test platform have no such flag; the guard must '
            'fall through, not replace the implementation',
      );
    });
  });

  test('every ImagePicker in lib/ is configured first', () {
    // The defect this file exists for was a claim drifting away from the code.
    // A second picker entry point that forgot the call would re-open it
    // silently, so the rule is structural rather than a comment.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains('ImagePicker()')) continue;
      if (!source.contains('useSystemPhotoPicker()')) offenders.add(entity.path);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these construct a picker without routing it through the system '
          'Photo Picker, so they open the SAF file browser instead',
    );
  });
}
