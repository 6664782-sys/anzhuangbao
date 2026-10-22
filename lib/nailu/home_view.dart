import 'dart:async';
import 'dart:math' as math;
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/widgets/proxy_groups.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'profiles.dart';
import 'session.dart';
import 'subscription_card.dart';

class NailuHomeView extends ConsumerStatefulWidget {
  const NailuHomeView({super.key, required this.onPlans});
  final VoidCallback onPlans;
  @override
  ConsumerState<NailuHomeView> createState() => _NailuHomeViewState();
}

class _NailuHomeViewState extends ConsumerState<NailuHomeView> {
  bool _transition = false;
  Future<void> _sync() async {
    try {
      await syncNailuProfile(ref, ref.read(nailuSessionProvider));
    } catch (_) {
      if (mounted) {
        dialogs.showNotifier(
          context.appLocalizations.nailuSyncFailed,
          level: MessageLevel.error,
        );
      }
    }
  }

  Future<void> _connect() async {
    if (_transition) return;
    setState(() => _transition = true);
    try {
      final running = ref.read(isStartProvider);
      final session = ref.read(nailuSessionProvider);
      if (!running &&
          (session.syncStatus != NailuSyncStatus.ready ||
              ref.read(currentProfileProvider) == null)) {
        await _sync();
        if (!mounted || session.syncStatus != NailuSyncStatus.ready) return;
      }
      if (!mounted) return;
      await ref
          .read(setupActionProvider.notifier)
          .setRunning(
            !running,
            initialize: !running && !ref.read(initProvider),
          );
    } catch (_) {
      if (mounted) {
        dialogs.showNotifier(
          context.appLocalizations.nailuActionFailed,
          level: MessageLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _transition = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.appLocalizations;
    final session = ref.watch(nailuSessionProvider);
    final running = ref.watch(isStartProvider);
    final traffic = ref.watch(trafficsProvider).list.safeLast(const Traffic());
    final mode = ref.watch(
      patchClashConfigProvider.select((value) => value.mode),
    );
    final tun = ref.watch(
      patchClashConfigProvider.select((value) => value.tun.enable),
    );
    final vpn = ref.watch(vpnSettingProvider.select((value) => value.enable));
    final proxy = ref.watch(
      networkSettingProvider.select((value) => value.systemProxy),
    );
    final selected = ref.watch(selectedMapProvider);
    final group = ref.watch(currentGroupsStateProvider).value.firstOrNull;
    final node = group == null
        ? s.nailuSelectNode
        : selected[group.name] ?? group.name;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => RefreshIndicator(
        onRefresh: _sync,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          Text(
                            s.nailuHeroTitle,
                            style: AppTextStyle.headline.of(context),
                          ),
                        ],
                      ),
                    ),
                    ExcludeSemantics(
                      child: SvgPicture.asset(
                        'assets/images/nailu-giraffe.svg',
                        width: 60,
                        height: 60,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Speed(title: s.upload, value: traffic.up),
                _Speed(title: s.download, value: traffic.down),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: SizedBox.square(
                dimension: 124,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: AppShape.circle,
                    padding: const EdgeInsets.all(16),
                    elevation: running ? 6 : 0,
                  ),
                  onPressed:
                      _transition ||
                          session.syncStatus == NailuSyncStatus.syncing
                      ? null
                      : () => unawaited(_connect()),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 8,
                    children: [
                      if (_transition ||
                          session.syncStatus == NailuSyncStatus.syncing)
                        const CommonCircleLoading()
                      else
                        const GlyphIcon(AppGlyphs.power, size: 34),
                      Text(
                        _transition
                            ? s.nailuConnecting
                            : running
                            ? s.nailuDisconnect
                            : s.nailuConnect,
                        style: AppTextStyle.headline
                            .of(context)
                            .copyWith(color: context.colorScheme.onPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                running ? s.nailuConnected : s.nailuDisconnected,
                style: AppTextStyle.title3.of(context, emphasized: true),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                nailuSyncLabel(context, session.syncStatus),
                style: AppTextStyle.footnote.of(context),
              ),
            ),
            if (session.syncStatus != NailuSyncStatus.ready &&
                session.syncStatus != NailuSyncStatus.syncing)
              TextButton(
                onPressed: () => unawaited(_sync()),
                child: Text(s.nailuSync),
              ),
            const SizedBox(height: 12),
            Card(
              child: ListItem(
                leading: const GlyphIcon(AppGlyphs.proxies),
                title: Text(s.nailuSelectNode),
                subtitle: Text(
                  node,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () => unawaited(showProxiesSheet(context)),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<Mode>(
              selectedIcon: const GlyphIcon(AppGlyphs.check, size: 16),
              segments: [
                for (final item in Mode.values)
                  ButtonSegment(value: item, label: Text(item.label)),
              ],
              selected: {mode},
              onSelectionChanged: (items) => ref
                  .read(setupActionProvider.notifier)
                  .changeMode(items.single),
            ),
            const SizedBox(height: 10),
            NailuSubscriptionCard(
              compact: true,
              onPlans: widget.onPlans,
              onRefresh: () => unawaited(_sync()),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(
                      system.isAndroid ? s.nailuVpnMode : s.nailuTunMode,
                    ),
                    secondary: const GlyphIcon(AppGlyphs.vpn),
                    value: system.isAndroid ? vpn : tun,
                    onChanged: (value) => system.isAndroid
                        ? ref
                              .read(vpnSettingProvider.notifier)
                              .update((state) => state.copyWith(enable: value))
                        : ref
                              .read(patchClashConfigProvider.notifier)
                              .update(
                                (state) => state.copyWith.tun(enable: value),
                              ),
                  ),
                  if (system.isDesktop)
                    SwitchListTile(
                      title: Text(s.systemProxy),
                      secondary: const GlyphIcon(AppGlyphs.shuffle),
                      value: proxy,
                      onChanged: (value) => ref
                          .read(networkSettingProvider.notifier)
                          .update(
                            (state) => state.copyWith(systemProxy: value),
                          ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => unawaited(
                showExtend<void>(context, builder: (_) => const ToolsView()),
              ),
              icon: const GlyphIcon(AppGlyphs.tools),
              label: Text(s.nailuTools),
            ),
          ],
        ),
      ),
    );
  }
}

class _Speed extends StatelessWidget {
  const _Speed({required this.title, required this.value});
  final String title;
  final num value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      Text(title, style: AppTextStyle.caption1.of(context)),
      Text(
        '${(math.max(0, value) / 1024).toStringAsFixed(1)} KB/s',
        style: AppTextStyle.subheadline.of(context, emphasized: true),
      ),
    ],
  );
}
