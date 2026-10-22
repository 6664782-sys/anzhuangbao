import 'dart:io';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<WebViewEnvironment?> createNailuWebEnvironment() async {
  if (!Platform.isWindows) return null;
  if (await WebViewEnvironment.getAvailableVersion() == null) {
    throw StateError('Microsoft Edge WebView2 Runtime is required');
  }
  final directory = await getApplicationSupportDirectory();
  return WebViewEnvironment.create(
    settings: WebViewEnvironmentSettings(
      userDataFolder: path.join(directory.path, 'verification-webview'),
    ),
  );
}
