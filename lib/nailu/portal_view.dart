import 'dart:async';
import 'dart:collection';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'profiles.dart';
import 'session.dart';
import 'web_environment.dart';

class NailuPortalView extends ConsumerStatefulWidget {
  const NailuPortalView({
    super.key,
    required this.route,
    required this.title,
    this.planId,
    this.period,
  });
  final String route;
  final String title;
  final int? planId;
  final String? period;
  @override
  ConsumerState<NailuPortalView> createState() => _NailuPortalViewState();
}

class _NailuPortalViewState extends ConsumerState<NailuPortalView> {
  late Future<({Uri uri, String script})> _request;
  WebViewEnvironment? _environment;
  bool _ready = false;
  bool _failed = false;
  int _generation = 0;
  Timer? _loadTimer;

  @override
  void initState() {
    super.initState();
    _request = _load();
  }

  Future<({Uri uri, String script})> _load() async {
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_ready) setState(() => _failed = true);
    });
    final environment =
        _environment ??
        await createNailuWebEnvironment(
          profile: 'services',
        ).timeout(const Duration(seconds: 12));
    if (!mounted) {
      await environment?.dispose();
      throw StateError('Portal closed');
    }
    _environment = environment;
    var uri = await ref.read(nailuSessionProvider).portalUri(widget.route);
    if (widget.planId != null && widget.period != null) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'nailu_plan': '${widget.planId}',
          'nailu_period': widget.period!,
        },
      );
    }
    final script = await rootBundle.loadString('assets/data/nailu-portal.js');
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_ready) setState(() => _failed = true);
    });
    return (uri: uri, script: script);
  }

  Future<void> _refresh() async {
    try {
      await syncNailuProfile(ref, ref.read(nailuSessionProvider));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.appLocalizations;
    return CommonScaffold(
      title: widget.title,
      body: Padding(
        padding: EdgeInsets.only(top: context.appBarInset),
        child: FutureBuilder<({Uri uri, String script})>(
          future: _request,
          builder: (context, snapshot) {
            if (snapshot.hasError || _failed) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(strings.nailuActionFailed),
                    TextButton(
                      onPressed: () => setState(() {
                        _ready = false;
                        _failed = false;
                        _generation++;
                        _request = _load();
                      }),
                      child: Text(strings.nailuRetryVerification),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CommonCircleLoading());
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: InAppWebView(
                    key: ValueKey(_generation),
                    webViewEnvironment: _environment,
                    initialUrlRequest: URLRequest(
                      url: WebUri.uri(snapshot.data!.uri),
                    ),
                    initialUserScripts: UnmodifiableListView([
                      UserScript(
                        source: snapshot.data!.script,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                        forMainFrameOnly: true,
                      ),
                    ]),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      supportMultipleWindows: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                    ),
                    onLoadStop: (controller, url) async {
                      if (url?.origin == NailuConfig.origin) {
                        await controller.evaluateJavascript(
                          source: snapshot.data!.script,
                        );
                      }
                    },
                    onWebViewCreated: (controller) {
                      controller.addJavaScriptHandler(
                        handlerName: 'nailuPortal',
                        callback: (arguments) async {
                          final uri = await controller.getUrl();
                          if (!mounted || uri?.origin != NailuConfig.origin) {
                            return;
                          }
                          setState(() {
                            _ready = arguments.firstOrNull == 'ready';
                            _failed = arguments.firstOrNull == 'error';
                          });
                          if (_ready || _failed) _loadTimer?.cancel();
                        },
                      );
                    },
                    shouldOverrideUrlLoading: (_, navigation) async {
                      if (!navigation.isForMainFrame) {
                        return NavigationActionPolicy.ALLOW;
                      }
                      final uri = navigation.request.url;
                      if (uri != null &&
                          uri.scheme == 'https' &&
                          uri.origin == NailuConfig.origin &&
                          uri.userInfo.isEmpty) {
                        return NavigationActionPolicy.ALLOW;
                      }
                      if (uri != null) await _openExternal(uri);
                      return NavigationActionPolicy.CANCEL;
                    },
                    onCreateWindow: (_, window) async {
                      if (!mounted) return false;
                      unawaited(
                        showExtend<void>(
                          context,
                          props: const ExtendProps(forceFull: true),
                          builder: (_) => NailuPaymentView(
                            windowId: window.windowId,
                            environment: _environment,
                          ),
                        ).then((_) async {
                          if (mounted) await _refresh();
                        }),
                      );
                      return true;
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
                  ),
                ),
                if (!_ready)
                  Positioned.fill(
                    child: ColoredBox(
                      color: context.colorScheme.surface,
                      child: const Center(child: CommonCircleLoading()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    unawaited(_environment?.dispose());
    super.dispose();
  }
}

Future<void> _openExternal(Uri uri) async {
  if (uri.userInfo.isNotEmpty ||
      !{'https', 'alipay', 'alipays', 'weixin', 'wxpay'}.contains(uri.scheme)) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class NailuPaymentView extends StatelessWidget {
  const NailuPaymentView({super.key, required this.windowId, this.environment});
  final int windowId;
  final WebViewEnvironment? environment;
  @override
  Widget build(BuildContext context) => CommonScaffold(
    title: context.appLocalizations.nailuPayment,
    body: Padding(
      padding: EdgeInsets.only(top: context.appBarInset),
      child: InAppWebView(
        windowId: windowId,
        webViewEnvironment: environment,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          useShouldOverrideUrlLoading: true,
        ),
        shouldOverrideUrlLoading: (_, navigation) async {
          if (!navigation.isForMainFrame) return NavigationActionPolicy.ALLOW;
          final uri = navigation.request.url;
          if (uri?.scheme == 'https' || uri?.toString() == 'about:blank') {
            return NavigationActionPolicy.ALLOW;
          }
          if (uri != null) await _openExternal(uri);
          return NavigationActionPolicy.CANCEL;
        },
        onCloseWindow: (_) {
          if (context.mounted) context.safeNestedPop();
        },
      ),
    ),
  );
}
