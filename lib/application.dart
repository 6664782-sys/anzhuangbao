import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/window.dart';
import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/nailu/auth_gate.dart';
import 'package:fl_clash/nailu/session.dart';
import 'package:fl_clash/nailu/profiles.dart';
import 'package:fl_clash/manager/hotkey_manager.dart';
import 'package:fl_clash/manager/manager.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nailu/shell.dart';

Widget buildManagerStack({
  required bool isDesktop,
  required Future<void> Function(List<ConnectivityResult> results)
  onConnectivityChanged,
  Stream<ProcessSignal>? terminateSignals,
  required Widget child,
}) {
  final platformApp = isDesktop
      ? WindowHeaderContainer(child: child)
      : VpnManager(child: child);
  final state = AppStateManager(
    child: CoreManager(
      child: ConnectivityManager(
        onConnectivityChanged: onConnectivityChanged,
        child: platformApp,
      ),
    ),
  );
  final platformState = isDesktop
      ? WindowManager(
          terminateSignals: terminateSignals,
          child: TrayManager(
            child: HotKeyManager(child: ProxyManager(child: state)),
          ),
        )
      : AndroidManager(child: TileManager(child: state));
  return AppEnvManager(
    child: LocaleManager(
      child: StatusManager(child: ThemeManager(child: platformState)),
    ),
  );
}

class Application extends ConsumerStatefulWidget {
  const Application({super.key});

  @override
  ConsumerState<Application> createState() => ApplicationState();
}

class ApplicationState extends ConsumerState<Application> {
  late final NailuSession _session;
  bool _ready = false;
  bool _attaching = false;
  bool _attachFailed = false;
  Timer? _autoUpdateProfilesTaskTimer;
  bool _preHasVpn = false;
  // Windows can only watch SIGINT and SIGHUP.
  final _terminateSignals = system.isDesktop && !system.isWindows
      ? ProcessSignal.sigterm.watch()
      : null;

  @override
  void initState() {
    super.initState();
    _session = ref.read(nailuSessionProvider);
    _session.addListener(_sessionChanged);
    SystemNavigator.setFrameworkHandlesBack(true);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      unawaited(window?.show());
      _sessionChanged();
      _initLink();
      if (!safeModeBuild) {
        unawaited(app?.initShortcuts());
      }
    });
  }

  void _sessionChanged() {
    if (!mounted) return;
    if (_session.phase != NailuPhase.signedIn) {
      _autoUpdateProfilesTaskTimer?.cancel();
      if (_ready) {
        unawaited(ref.read(setupActionProvider.notifier).setRunning(false));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          globalState.navigatorKey.currentState?.popUntil(
            (route) => route.isFirst,
          );
        });
      }
      setState(() => _ready = false);
    } else if (!_ready && !_attaching) {
      unawaited(_attachAccount());
    }
  }

  Future<void> _attachAccount() async {
    if (_attaching) return;
    _attaching = true;
    if (mounted) setState(() => _attachFailed = false);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _session.phase != NailuPhase.signedIn) return;
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
      await bootstrap.attach();
      var synced = false;
      try {
        synced = await syncNailuProfile(ref, _session);
      } catch (_) {
        // Keep account services reachable when the subscription needs a retry.
      }
      if (!mounted || _session.phase != NailuPhase.signedIn) return;
      if (synced) await bootstrap.initializeAccountStatus();
      _autoUpdateProfilesTaskTimer?.cancel();
      _autoUpdateProfilesTask();
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _attachFailed = true);
    } finally {
      _attaching = false;
    }
  }

  void _initLink() {
    linkManager.initAppLinksListen((url) async {
      if (!_ready || _session.phase != NailuPhase.signedIn) return;
      unawaited(window?.show());
      final message = currentAppLocalizations.createProfileFromUrlTip(url);
      final parts = message.split(url);
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.addProfile,
        message: TextSpan(
          children: [
            TextSpan(text: parts.first),
            TextSpan(
              text: url,
              style: TextStyle(
                color: context.colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: context.colorScheme.primary,
              ),
            ),
            if (parts.length > 1) TextSpan(text: parts.last),
          ],
        ),
      );
      if (res != true) return;
      unawaited(
        ref.read(profilesActionProvider.notifier).addProfileFromLink(url),
      );
    });
  }

  void _autoUpdateProfilesTask() {
    _autoUpdateProfilesTaskTimer = Timer(const Duration(minutes: 20), () async {
      await ref.read(profilesActionProvider.notifier).autoUpdateProfiles();
      await ref.read(resourcesActionProvider.notifier).autoUpdate();
      if (!mounted) {
        return;
      }
      _autoUpdateProfilesTask();
    });
  }

  Future<void> _handleConnectivityChanged(
    List<ConnectivityResult> results,
  ) async {
    commonPrint.log('connectivityChanged ${results.toString()}');
    unawaited(systemDnsCoordinator?.resync() ?? Future.value());
    unawaited(ref.read(systemActionProvider.notifier).updateLocalIp());
    final hasVpn = results.contains(ConnectivityResult.vpn);
    if (_preHasVpn == hasVpn) {
      ref.read(routeTrackerProvider.notifier).bumpHostEpoch();
    }
    _preHasVpn = hasVpn;
  }

  @override
  Widget build(context) {
    return Consumer(
      builder: (_, ref, child) {
        final locale = ref.watch(
          appSettingProvider.select((state) => state.locale),
        );
        final themeProps = ref.watch(themeSettingProvider);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: globalState.navigatorKey,
          onNavigationNotification: (_) => true,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            AppUiLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          builder: (context, child) {
            return ThemeCrossFade(
              child: buildManagerStack(
                isDesktop: system.isDesktop,
                onConnectivityChanged: _handleConnectivityChanged,
                terminateSignals: _terminateSignals,
                child: RemoteFocusAdapter(
                  enabled: system.isTV,
                  floatingKeyboard: app?.floatingKeyboard,
                  child: NailuAuthGate(session: _session, child: child!),
                ),
              ),
            );
          },
          scrollBehavior: const BaseScrollBehavior(),
          title: appName,
          locale: getLocaleForString(locale),
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          themeMode: themeProps.themeMode,
          theme: watchAppTheme(ref, Brightness.light),
          darkTheme: watchAppTheme(ref, Brightness.dark),
          themeAnimationStyle: AnimationStyle.noAnimation,
          home: KeyboardInsetHold(
            child: _ready
                ? child!
                : Scaffold(
                    body: Center(
                      child: _attachFailed
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  context.appLocalizations.nailuActionFailed,
                                ),
                                TextButton(
                                  onPressed: () => unawaited(_attachAccount()),
                                  child: Text(
                                    context.appLocalizations.nailuSync,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      unawaited(_session.signOut()),
                                  child: Text(
                                    context.appLocalizations.nailuLogout,
                                  ),
                                ),
                              ],
                            )
                          : const CommonCircleLoading(),
                    ),
                  ),
          ),
        );
      },
      child: const NailuShell(),
    );
  }

  @override
  void dispose() {
    _session.removeListener(_sessionChanged);
    linkManager.destroy();
    _autoUpdateProfilesTaskTimer?.cancel();
    super.dispose();
  }
}
