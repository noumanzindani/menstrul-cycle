# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# Flutter's deferred-components code references Play Core, which we don't bundle
# (this app has no deferred components). Silence + keep so R8 doesn't fail.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Google Mobile Ads (AdMob) + Play services use reflection.
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.ump.** { *; }

# Google Play Billing (in_app_purchase).
-keep class com.android.billingclient.** { *; }

# flutter_local_notifications keeps its scheduled-notification classes.
-keep class com.dexterous.** { *; }

# Keep annotations and generic signatures (drift / sqlite reflection safety).
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
