import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Routes Android media picking through the system Photo Picker.
///
/// `image_picker_android` ships `useAndroidPhotoPicker = false`, and false is
/// not a neutral default here. `ImagePickerDelegate.launchPickMediaFromGallery`
/// branches on it: false builds `ACTION_GET_CONTENT` with type `*/*`, which is
/// the SAF document browser — it offers every file on the device, not only
/// media, and the read it grants is not the per-item grant the Photo Picker
/// gives. True builds `PickVisualMedia`, which is.
///
/// That distinction is the one PRIVACY_POLICY.md, `AndroidManifest.xml` and
/// this app's own pubspec comment all already describe to users, so leaving the
/// flag alone made three published statements false.
///
/// No version gate is needed: AndroidX's `createIntent` resolves the backend
/// itself — `ACTION_PICK_IMAGES` on API 33+, the Play-services backport below
/// that, `ACTION_OPEN_DOCUMENT` where neither exists.
///
/// The guard is a type test rather than a `Platform.isAndroid` check so it also
/// falls through under `flutter test`, where the platform is the method-channel
/// default and the flag does not exist.
void useSystemPhotoPicker() {
  final platform = ImagePickerPlatform.instance;
  if (platform is ImagePickerAndroid) {
    platform.useAndroidPhotoPicker = true;
  }
}
