# --- AUDIRE PROGUARD RULES ---

# 1. Fix for read_pdf_text (PDFBox)
# Ignores the missing JPEG2000 decoder since we don't strictly need it for basic PDFs
-dontwarn com.gemalto.jp2.**
-dontwarn com.tom_roush.pdfbox.filter.JPXFilter

# 2. Fix for Google ML Kit (OCR)
# The Flutter plugin references Chinese/Korean/Japanese classes, 
# but we only downloaded the Latin script model. This tells R8 to ignore the others.
-dontwarn com.google.mlkit.vision.text.**
-dontwarn com.google.android.gms.**

# 3. Standard Flutter Rules (Safety)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# 4. NEW: Fix for Play Store Split Install (The R8 Error)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**