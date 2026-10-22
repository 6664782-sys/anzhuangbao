import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'web_environment.dart';

class NailuChallenge extends StatefulWidget {
  const NailuChallenge({super.key, required this.onToken});
  final ValueChanged<String?> onToken;

  @override
  State<NailuChallenge> createState() => _NailuChallengeState();
}

class _NailuChallengeState extends State<NailuChallenge> {
  InAppWebViewController? _controller;
  bool _failed = false;
  late Future<WebViewEnvironment?> _environment;
  WebViewEnvironment? _ownedEnvironment;

  @override
  void initState() {
    super.initState();
    _environment = _prepareEnvironment();
  }

  Future<WebViewEnvironment?> _prepareEnvironment() async {
    final environment = await createNailuWebEnvironment();
    if (!mounted) {
      await environment?.dispose();
      return null;
    }
    _ownedEnvironment = environment;
    return environment;
  }

  bool _trusted(WebUri? url) => url?.toString() == NailuConfig.challenge;

  void _fail() {
    if (!mounted) return;
    widget.onToken(null);
    setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.appLocalizations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 90,
          child: FutureBuilder<WebViewEnvironment?>(
            future: _environment,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text(strings.nailuChallengeFailed);
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CommonCircleLoading());
              }
              return InAppWebView(
                webViewEnvironment: snapshot.data,
                initialUrlRequest: URLRequest(
                  url: WebUri(NailuConfig.challenge),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  javaScriptCanOpenWindowsAutomatically: false,
                  supportMultipleWindows: false,
                  allowsBackForwardNavigationGestures: false,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'nailuChallenge',
                    callback: (arguments) async {
                      if (!_trusted(await controller.getUrl()) || !mounted) {
                        return;
                      }
                      final value = arguments.firstOrNull;
                      final token =
                          value is String &&
                              value.length <= 2048 &&
                              value.isNotEmpty
                          ? value
                          : null;
                      widget.onToken(token);
                    },
                  );
                },
                shouldOverrideUrlLoading: (_, navigation) async {
                  if (navigation.isForMainFrame &&
                      !_trusted(navigation.request.url)) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onReceivedError: (_, request, _) {
                  if (request.isForMainFrame == true) _fail();
                },
                onReceivedHttpError: (_, request, _) {
                  if (request.isForMainFrame == true) _fail();
                },
              );
            },
          ),
        ),
        if (_failed) Text(strings.nailuChallengeFailed),
        TextButton(
          onPressed: () async {
            widget.onToken(null);
            if (_controller != null) {
              setState(() => _failed = false);
              await _controller!.reload();
            } else {
              setState(() => _environment = _prepareEnvironment());
            }
          },
          child: Text(strings.nailuRetryVerification),
        ),
      ],
    );
  }

  @override
  void dispose() {
    unawaited(_ownedEnvironment?.dispose());
    super.dispose();
  }
}
