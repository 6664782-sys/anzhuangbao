import 'dart:math' as math;
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'catalog.dart';
import 'session.dart';

String nailuSyncLabel(BuildContext context, NailuSyncStatus status) {
  final s = context.appLocalizations;
  return switch (status) {
    NailuSyncStatus.idle => s.nailuSyncPending,
    NailuSyncStatus.syncing => s.nailuSyncing,
    NailuSyncStatus.ready => s.nailuSyncComplete,
    NailuSyncStatus.noPlan => s.nailuNoPlan,
    NailuSyncStatus.expired => s.nailuPlanExpired,
    NailuSyncStatus.exhausted => s.nailuTrafficExhausted,
    NailuSyncStatus.failed => s.nailuSyncFailed,
  };
}

class NailuSubscriptionCard extends ConsumerWidget {
  const NailuSubscriptionCard({
    super.key,
    required this.onPlans,
    required this.onRefresh,
    this.compact = false,
  });
  final VoidCallback onPlans;
  final VoidCallback onRefresh;
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(nailuSessionProvider);
    final s = context.appLocalizations;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final data = session.subscription ?? const <String, dynamic>{};
        final plan = data['plan'];
        final name = plan is Map ? plan['name'] as String? : null;
        final total = (data['transfer_enable'] as num?) ?? 0;
        final used = ((data['u'] as num?) ?? 0) + ((data['d'] as num?) ?? 0);
        final expiry = (data['expired_at'] as num?)?.toInt();
        final expiryLabel = expiry == null || expiry == 0
            ? s.nailuLongTerm
            : DateTime.fromMillisecondsSinceEpoch(
                expiry * 1000,
              ).toLocal().toIso8601String().split('T').first;
        return Card(
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: compact ? 8 : 12,
              children: [
                Text(
                  name ?? s.nailuNoPlan,
                  style: AppTextStyle.headline.of(context),
                ),
                if (name != null) ...[
                  Text(
                    '${s.nailuExpires}: $expiryLabel',
                    style: AppTextStyle.caption1.of(context),
                  ),
                  Text(
                    '${s.nailuRemaining}: ${nailuBytes(math.max(0, total - used))} / ${nailuBytes(total)}',
                    style: AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  LinearProgressIndicator(
                    value: total > 0
                        ? (used / total).clamp(0, 1).toDouble()
                        : 0,
                  ),
                ],
                FilledButton(onPressed: onPlans, child: Text(s.nailuPlans)),
                if (!compact)
                  TextButton(
                    onPressed: session.syncStatus == NailuSyncStatus.syncing
                        ? null
                        : onRefresh,
                    child: Text(s.nailuSync),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
