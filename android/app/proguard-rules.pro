# Drift / sqlite3 yerel bağlamaları
-keep class org.sqlite.** { *; }
-keep class com.tekartik.** { *; }

# flutter_secure_storage
-keep class androidx.security.crypto.** { *; }

# Uygulama sınıfları — yansıma kullanan üretilmiş kod için
-keep class com.sungerbob.** { *; }
