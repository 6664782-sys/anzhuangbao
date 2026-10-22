# NaiLu compatibility patch

Vendored from flutter_inappwebview_android 1.1.3 (https://pub.dev/packages/flutter_inappwebview_android/versions/1.1.3), retaining its original license and attribution.

The only implementation change is using `proguard-android-optimize.txt` instead of the removed `proguard-android.txt` default in android/build.gradle. Android Gradle Plugin 9 rejects the old default before configuration completes. Remove this local override when a stable upstream version supports AGP 9.
