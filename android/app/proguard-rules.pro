-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

-keepattributes JavascriptInterface
-keepattributes *Annotation*

# Razorpay
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}

-optimizations !method/inlining/
-keepclasseswithmembers class * {
  public void onPayment*(...);
}

-dontwarn com.google.android.gms.auth.api.credentials.**

# Firebase Messaging
-keepattributes *Annotation*
-dontwarn com.google.firebase.**
-keep class com.google.firebase.** { *; }

# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# Flutter Background Service
-keep class id.flutter.flutter_background_service.** { *; }
-dontwarn id.flutter.flutter_background_service.**

# Audioplayers
-keep class xyz.luan.audioplayers.** { *; }
-dontwarn xyz.luan.audioplayers.**

# UCrop
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# Flutter Engine & AndroidX Insets (R8 Full Mode safety)
-keep class io.flutter.embedding.** { *; }
-keep class androidx.activity.** { *; }
-keep class androidx.core.view.** { *; }

# Google Play Core (deferred components referenced by Flutter embedding)
-dontwarn com.google.android.play.core.**

