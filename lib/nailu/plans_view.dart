import 'dart:async';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'catalog.dart';
import 'portal_view.dart';
import 'profiles.dart';
import 'session.dart';

String nailuPeriod(BuildContext context, String key) {
  final s = context.appLocalizations;
  return switch (key) {
    'month_price' => s.nailuMonthly,
    'quarter_price' => s.nailuQuarterly,
    'half_year_price' => s.nailuHalfYear,
    'year_price' => s.nailuYearly,
    'two_year_price' => s.nailuTwoYears,
    'three_year_price' => s.nailuThreeYears,
    _ => s.nailuOneTime,
  };
}

class NailuPlansView extends ConsumerStatefulWidget {
  const NailuPlansView({super.key});
  @override
  ConsumerState<NailuPlansView> createState() => _NailuPlansViewState();
}

class _NailuPlansViewState extends ConsumerState<NailuPlansView> {
  late Future<List<NailuPlan>> _request;
  int _category = 0;
  @override
  void initState() {
    super.initState();
    _request = ref.read(nailuSessionProvider).plans();
  }

  Future<void> _reload() async {
    final request = ref.read(nailuSessionProvider).plans();
    setState(() {
      _request = request;
    });
    await request;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.appLocalizations;
    return FutureBuilder<List<NailuPlan>>(
      future: _request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CommonCircleLoading());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.nailuCatalogError),
                TextButton(
                  onPressed: () =>
                      unawaited(_reload().catchError((Object _) {})),
                  child: Text(s.nailuRetryVerification),
                ),
              ],
            ),
          );
        }
        final plans = snapshot.data!
            .where(
              (p) =>
                  _category == 0 ||
                  (_category == 1
                      ? p.periodic
                      : p.periods.contains('onetime_price')),
            )
            .toList();
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              SegmentedButton<int>(
                selectedIcon: const GlyphIcon(AppGlyphs.check, size: 16),
                segments: [
                  ButtonSegment(value: 0, label: Text(s.nailuAll)),
                  ButtonSegment(value: 1, label: Text(s.nailuPeriodic)),
                  ButtonSegment(value: 2, label: Text(s.nailuOneTime)),
                ],
                selected: {_category},
                onSelectionChanged: (values) =>
                    setState(() => _category = values.single),
              ),
              const SizedBox(height: 16),
              Text(
                s.nailuMonthlyResetHint,
                style: AppTextStyle.footnote.of(context),
              ),
              const SizedBox(height: 16),
              if (plans.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(s.nailuNoCatalog),
                ),
              for (final plan in plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _PlanCard(
                    key: ValueKey(plan.id),
                    plan: plan,
                    oneTimeOnly: _category == 2,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PlanCard extends ConsumerStatefulWidget {
  const _PlanCard({super.key, required this.plan, required this.oneTimeOnly});
  final NailuPlan plan;
  final bool oneTimeOnly;
  @override
  ConsumerState<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<_PlanCard> {
  String? _period;
  bool _opening = false;
  Future<void> _buy(String period) async {
    setState(() => _opening = true);
    try {
      await showExtend<void>(
        context,
        props: const ExtendProps(forceFull: true),
        builder: (_) => NailuPortalView(
          route: 'plans',
          title: context.appLocalizations.nailuPlans,
          planId: widget.plan.id,
          period: period,
        ),
      );
      if (mounted) await syncNailuProfile(ref, ref.read(nailuSessionProvider));
    } catch (_) {
      if (mounted) {
        dialogs.showNotifier(
          context.appLocalizations.nailuActionFailed,
          level: MessageLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final s = context.appLocalizations;
    final periods = p.periods
        .where((key) => !widget.oneTimeOnly || key == 'onetime_price')
        .toList();
    final period = periods.contains(_period) ? _period! : periods.first;
    final oneTime = period == 'onetime_price';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Text(
              p.name,
              style: AppTextStyle.title2.of(context, emphasized: true),
            ),
            Text(
              '¥${(p.price(period) / 100).toStringAsFixed(2)} / ${nailuPeriod(context, period)}',
              style: AppTextStyle.title1
                  .of(context, emphasized: true)
                  .copyWith(color: context.colorScheme.primary),
            ),
            Row(
              children: [
                Expanded(
                  child: _Spec(
                    glyph: AppGlyphs.speed,
                    value: '${p.traffic} GB',
                    label: oneTime
                        ? s.nailuTotalTraffic
                        : s.nailuMonthlyTraffic,
                  ),
                ),
                Expanded(
                  child: _Spec(
                    glyph: AppGlyphs.devices,
                    value: p.devices == null || p.devices == 0
                        ? s.nailuUnlimited
                        : '${p.devices}',
                    label: s.nailuDeviceLimit,
                  ),
                ),
              ],
            ),
            Text(
              '${p.speed == null || p.speed == 0
                  ? s.nailuUnlimited
                  : p.speed! >= 1000
                  ? '${p.speed! / 1000} Gbps'
                  : '${p.speed} Mbps'} · ${s.nailuRateOne}',
              style: AppTextStyle.footnote.of(context),
            ),
            if (p.description.isNotEmpty)
              ExpansionTile(
                trailing: const GlyphIcon(AppGlyphs.chevronDown),
                title: Text(s.nailuPlanDetails),
                tilePadding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(p.description),
                  ),
                ],
              ),
            DropdownButtonFormField<String>(
              icon: const GlyphIcon(AppGlyphs.chevronDown),
              key: ValueKey('${p.id}:$period'),
              initialValue: period,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.nailuBillingPeriod),
              items: [
                for (final key in periods)
                  DropdownMenuItem(
                    value: key,
                    child: Text(
                      '${nailuPeriod(context, key)} · ¥${(p.price(key) / 100).toStringAsFixed(2)}',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _period = value),
            ),
            FilledButton(
              onPressed: _opening || p.soldOut
                  ? null
                  : () => unawaited(_buy(period)),
              child: Text(
                p.soldOut
                    ? s.nailuSoldOut
                    : _opening
                    ? s.nailuOpening
                    : s.nailuChoosePlan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spec extends StatelessWidget {
  const _Spec({required this.glyph, required this.value, required this.label});
  final Glyph glyph;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      spacing: 6,
      children: [
        GlyphIcon(glyph, color: context.colorScheme.primary),
        Text(value, style: AppTextStyle.headline.of(context)),
        Text(label, style: AppTextStyle.caption1.of(context)),
      ],
    ),
  );
}
