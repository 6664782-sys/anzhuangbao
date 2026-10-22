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
  const NailuAccountView({super.key});

  @override
  ConsumerState<NailuAccountView> createState() => _NailuAccountViewState();
}

class _NailuAccountViewState extends ConsumerState<NailuAccountView> {
  late final NailuSession _session;
  bool _working = false;
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
    final synced = await syncNailuProfile(ref, _session);
    if (mounted) {
      _feedback = synced
          ? context.appLocalizations.nailuSyncComplete
          : context.appLocalizations.nailuNoPlan;
    }
  }

  Future<void> _logout() async {
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

  Widget _button(String label, VoidCallback? action) =>
      FilledButton(onPressed: _working ? null : action, child: Text(label));

  Widget _summary(BuildContext context) {
    final strings = context.appLocalizations;
    final data = _session.subscription ?? const <String, dynamic>{};
    final plan = data['plan'];
    final planName = plan is Map ? plan['name'] as String? : null;
    final total = (data['transfer_enable'] as num?)?.toDouble() ?? 0;
    final used =
        ((data['u'] as num?)?.toDouble() ?? 0) +
        ((data['d'] as num?)?.toDouble() ?? 0);
    final expires = (data['expired_at'] as num?)?.toInt();
    final date = expires == null
        ? strings.nailuLongTerm
        : DateTime.fromMillisecondsSinceEpoch(
            expires * 1000,
          ).toLocal().toIso8601String().split('T').first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text(
              planName ?? strings.nailuNoPlan,
              style: AppTextStyle.title2.of(context, emphasized: true),
            ),
            Text(
              '${strings.nailuTraffic}: ${(used / 1073741824).toStringAsFixed(2)} / ${(total / 1073741824).toStringAsFixed(2)} GB',
            ),
            LinearProgressIndicator(
              value: total > 0 ? (used / total).clamp(0, 1) : 0,
            ),
            Text('${strings.nailuExpires}: $date'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _button(strings.nailuSync, () => unawaited(_run(_sync))),
                _button(
                  strings.nailuPlans,
                  () => unawaited(
                    _run(() => _portal('plans', strings.nailuPlans)),
                  ),
                ),
                _button(
                  strings.nailuSupport,
                  () => unawaited(
                    _run(() => _portal('tickets', strings.nailuSupport)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.appLocalizations;
    return CommonScaffold(
      title: strings.nailuAccount,
      body: ListenableBuilder(
        listenable: _session,
        builder: (context, _) => ListView(
          padding: EdgeInsets.fromLTRB(16, context.appBarInset + 16, 16, 32),
          children: [
            Text(
              NailuConfig.name,
              style: AppTextStyle.largeTitle.of(context, emphasized: true),
            ),
            const SizedBox(height: 12),
            Text(strings.nailuAccountHint),
            const SizedBox(height: 24),
            if (_session.phase == NailuPhase.restoring)
              const Center(child: CommonCircleLoading()),
            if (_session.phase == NailuPhase.signedIn) ...[
              Text(_session.account?['email'] as String? ?? ''),
              const SizedBox(height: 16),
              _summary(context),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _working ? null : () => unawaited(_run(_logout)),
                child: Text(strings.nailuLogout),
              ),
            ],
            if (_working)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_feedback!),
              ),
            if (_session.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(strings.nailuConnectionError),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
