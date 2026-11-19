# The text recognition plugin references language packs we do not ship
# (only Latin script is bundled). They are never loaded at runtime.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# PDFBox optional dependencies (JPEG 2000 images, desktop-only classes).
-dontwarn com.gemalto.jp2.**
-dontwarn com.tom_roush.pdfbox.**
-keep class com.tom_roush.pdfbox.** { *; }
-keep class com.tom_roush.fontbox.** { *; }

# Ads, billing and the web view the ads plugin relies on: kept whole, so that
# shrinking can never remove something they load by name.
-keep class io.flutter.plugins.googlemobileads.** { *; }
-keep class io.flutter.plugins.inapppurchase.** { *; }
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keep class com.android.billingclient.** { *; }
-dontwarn com.google.android.gms.ads.**
