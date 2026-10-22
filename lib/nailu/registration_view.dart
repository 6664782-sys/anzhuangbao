import 'dart:async';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';
import 'config.dart';
import 'web_environment.dart';

class NailuRegistrationView extends StatefulWidget {
  const NailuRegistrationView({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<NailuRegistrationView> createState() => _NailuRegistrationViewState();
}

class _NailuRegistrationViewState extends State<NailuRegistrationView> {
  late Future<WebViewEnvironment?> _environment;
  WebViewEnvironment? _ownedEnvironment;
  int _generation = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _environment = _prepare();
  }

  Future<WebViewEnvironment?> _prepare() async {
    final environment = await createNailuWebEnvironment();
    if (!mounted) {
      await environment?.dispose();
      return null;
    }
    _ownedEnvironment = environment;
    return environment;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.appLocalizations;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: strings.nailuBackToLogin,
                    onPressed: widget.onBack,
                    icon: const GlyphIcon(AppGlyphs.arrowBack),
                  ),
                  Expanded(
                    child: Text(
                      strings.nailuRegister,
                      style: AppTextStyle.headline.of(context),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onBack,
                    child: Text(strings.nailuBackToLogin),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(strings.nailuRegistrationHint),
              ),
              if (_failed) Text(strings.nailuChallengeFailed),
              Expanded(
                child: FutureBuilder<WebViewEnvironment?>(
                  future: _environment,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _environment = _prepare()),
                          child: Text(strings.nailuRetryVerification),
                        ),
                      );
                    }
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CommonCircleLoading());
                    }
                    return InAppWebView(
                      key: ValueKey(_generation),
                      webViewEnvironment: snapshot.data,
                      initialUrlRequest: URLRequest(
                        url: WebUri(NailuConfig.register),
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        thirdPartyCookiesEnabled: true,
                        useShouldOverrideUrlLoading: true,
                      ),
                      shouldOverrideUrlLoading: (_, navigation) async {
                        if (!navigation.isForMainFrame) {
                          return NavigationActionPolicy.ALLOW;
                        }
                        final uri = navigation.request.url;
                        return uri != null &&
                                uri.scheme == 'https' &&
                                uri.origin == NailuConfig.origin &&
                                uri.userInfo.isEmpty &&
                                uri.port == 443
                            ? NavigationActionPolicy.ALLOW
                            : NavigationActionPolicy.CANCEL;
                      },
                      onReceivedError: (_, request, _) {
                        if (mounted && request.isForMainFrame == true) {
                          setState(() => _failed = true);
                        }
                      },
                      onReceivedHttpError: (_, request, _) {
                        if (mounted && request.isForMainFrame == true) {
                          setState(() => _failed = true);
                        }
                      },
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _failed = false;
                  _generation++;
                }),
                child: Text(strings.nailuRetryVerification),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_ownedEnvironment?.dispose());
    super.dispose();
  }
}
