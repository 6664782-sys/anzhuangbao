import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'session.dart';
import 'profiles.dart';
import 'portal_view.dart';
import 'plans_view.dart';
import 'services_view.dart';
import 'subscription_card.dart';
import 'package:fl_clash/views/tools.dart';

class NailuAccountBanner extends ConsumerWidget {
  const NailuAccountBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(nailuSessionProvider);
    final strings = context.appLocalizations;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => ListItem.open(
            leading: const GlyphIcon(AppGlyphs.account),
            title: const Text(NailuConfig.name),
            subtitle: Text(
              session.account?['email'] as String? ?? strings.nailuAccountHint,
            ),
            widget: const NailuAccountView(),
          ),
        ),
      ),
    );
  }
}

class NailuAccountView extends ConsumerStatefulWidget {
  const NailuAccountView({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<NailuAccountView> createState() => _NailuAccountViewState();
}

class _NailuAccountViewState extends ConsumerState<NailuAccountView> {
  late final NailuSession _session;
  bool _working = false;
  bool _hideEmail = true;
  String? _feedback;
  @override
  void initState() {
    super.initState();
    _session = ref.read(nailuSessionProvider);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _feedback = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) _feedback = context.appLocalizations.nailuActionFailed;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _portal(String route, String title) async {
    await showExtend<void>(
      context,
      props: const ExtendProps(forceFull: true),
      builder: (_) => NailuPortalView(route: route, title: title),
    );
    if (mounted && _session.phase == NailuPhase.signedIn) await _sync();
  }

  Future<void> _sync() async {
    await syncNailuProfile(ref, _session);
  }

  Future<void> _plans() => showExtend<void>(
    context,
    props: const ExtendProps(forceFull: true),
    builder: (_) => CommonScaffold(
      title: context.appLocalizations.nailuPlans,
      body: Padding(
        padding: EdgeInsets.only(top: context.appBarInset),
        child: const NailuPlansView(),
      ),
    ),
  );
  Future<void> _logout() async {
    final accepted = await dialogs.showMessage(
      message: TextSpan(text: context.appLocalizations.nailuLogoutConfirm),
    );
    if (accepted != true || !mounted) return;
    final stopped = await ref
        .read(setupActionProvider.notifier)
        .setRunning(false);
    if (!stopped) throw StateError('Could not stop the active connection');
    final id = _session.managedProfileId;
    if (id != null) {
      await ref.read(profilesActionProvider.notifier).deleteProfile(id);
      await _session.bindManagedProfile(null);
    }
    await _session.signOut();
  }

  Widget _service(String title, Glyph glyph, String route) => ListItem(
    leading: GlyphIcon(glyph),
    title: Text(title),
    trailing: const GlyphIcon(AppGlyphs.chevronForward),
    onTap: _working ? null : () => unawaited(_run(() => _portal(route, title))),
  );
  @override
  Widget build(BuildContext context) {
    final s = context.appLocalizations;
    final body = ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final email = _session.account?['email'] as String? ?? '';
        final at = email.indexOf('@');
        final shownEmail = _hideEmail && at > 0
            ? '${email.substring(0, 1)}***${email.substring(at)}'
            : email;
        final balance = (_session.account?['balance'] as num?) ?? 0;
        return RefreshIndicator(
          onRefresh: () => _run(_sync),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              widget.embedded ? 8 : context.appBarInset + 16,
              20,
              28,
            ),
            children: [
              Card(
                child: ListItem(
                  leading: const GlyphIcon(AppGlyphs.account),
                  title: Text(shownEmail),
                  subtitle: Text(
                    '${s.nailuBalance}: ¥${(balance / 100).toStringAsFixed(2)}',
                  ),
                  trailing: IconButton(
                    tooltip: s.nailuEmailPrivacy,
                    onPressed: () => setState(() => _hideEmail = !_hideEmail),
                    icon: GlyphIcon(
                      _hideEmail ? AppGlyphs.eye : AppGlyphs.eyeOff,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              NailuSubscriptionCard(
                onPlans: () => unawaited(_plans()),
                onRefresh: () => unawaited(_run(_sync)),
              ),
              const SizedBox(height: 12),
              Text(s.nailuMyServices, style: AppTextStyle.headline.of(context)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    _service(s.nailuOrders, AppGlyphs.requests, 'orders'),
                    _service(s.nailuTraffic, AppGlyphs.speed, 'traffic'),
                    _service(s.nailuSupport, AppGlyphs.tools, 'tickets'),
                    _service(s.nailuInvite, AppGlyphs.link, 'invite'),
                    _service(s.nailuGuide, AppGlyphs.profiles, 'help'),
                    _service(
                      s.nailuDiagnostics,
                      AppGlyphs.verified,
                      'diagnostics',
                    ),
                    ListItem.open(
                      leading: const GlyphIcon(AppGlyphs.send),
                      title: Text(s.nailuServices),
                      widget: const NailuServicesView(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    for (final field in ['remind_expire', 'remind_traffic'])
                      SwitchListTile(
                        title: Text(
                          field == 'remind_expire'
                              ? s.nailuExpireReminder
                              : s.nailuTrafficReminder,
                        ),
                        subtitle: Text(s.nailuReminderHint),
                        value: _session.account?[field] == 1,
                        onChanged: _working
                            ? null
                            : (value) => unawaited(
                                _run(
                                  () => _session.updateReminder(field, value),
                                ),
                              ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListItem.open(
                  leading: const GlyphIcon(AppGlyphs.tools),
                  title: Text(s.nailuTools),
                  widget: const ToolsView(),
                  forceFull: true,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                s.nailuAccountSettings,
                style: AppTextStyle.headline.of(context),
              ),
              Card(
                child: Column(
                  children: [
                    _service(s.nailuSecurity, AppGlyphs.verified, 'profile'),
                    _service(
                      s.nailuWebAccount,
                      AppGlyphs.openExternal,
                      'profile',
                    ),
                    _service(s.nailuDevices, AppGlyphs.devices, 'devices'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _working ? null : () => unawaited(_run(_logout)),
                child: Text(s.nailuLogout),
              ),
              if (_working)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
              if (_feedback != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_feedback!),
                ),
            ],
          ),
        );
      },
    );
    return widget.embedded
        ? body
        : CommonScaffold(title: s.nailuAccount, body: body);
  }
}
