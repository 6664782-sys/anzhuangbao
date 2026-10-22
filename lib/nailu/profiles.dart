import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'session.dart';

NailuSyncStatus nailuEntitlement(Map<String, dynamic> source, DateTime now) {
  final quota = (source['transfer_enable'] as num?)?.toInt() ?? 0;
  final expires = (source['expired_at'] as num?)?.toInt();
  if (quota <= 0) return NailuSyncStatus.noPlan;
  if (expires != null &&
      expires > 0 &&
      expires * 1000 <= now.millisecondsSinceEpoch) {
    return NailuSyncStatus.expired;
  }
  if (((source['u'] as num?) ?? 0) + ((source['d'] as num?) ?? 0) >= quota) {
    return NailuSyncStatus.exhausted;
  }
  return NailuSyncStatus.ready;
}

Future<bool> syncNailuProfile(WidgetRef ref, NailuSession session) async {
  if (session.syncStatus == NailuSyncStatus.syncing) return false;
  final revision = session.revision;
  bool current() =>
      session.phase == NailuPhase.signedIn && session.revision == revision;
  session.setSyncStatus(NailuSyncStatus.syncing);
  try {
    await session.refresh();
    if (!current()) {
      return false;
    }
    final source = session.subscription;
    if (source == null) throw StateError('Missing subscription details');
    final entitlement = nailuEntitlement(source, DateTime.now());
    if (entitlement != NailuSyncStatus.ready) {
      session.setSyncStatus(entitlement);
      return false;
    }
    final uri = session.subscriptionUri;
    if (uri == null) throw StateError('Missing subscription');
    final profiles = ref.read(profilesProvider);
    final previous = profiles
        .where((profile) => profile.id == session.managedProfileId)
        .firstOrNull;
    final candidate = (previous ?? Profile.normal(label: NailuConfig.name))
        .copyWith(url: uri.toString(), type: ProfileType.url, autoUpdate: true);
    final core = ref.read(coreHandlerProvider);
    final updated = await candidate.update(
      validate: (path, key) => core.validateProfile(path, key),
    );
    if (!current()) return false;
    ref.read(profilesActionProvider.notifier).putProfile(updated);
    await session.bindManagedProfile(updated.id);
    if (!current()) return false;
    ref.read(currentProfileIdProvider.notifier).value = updated.id;
    final applied = await ref
        .read(setupActionProvider.notifier)
        .applyProfile(force: true, silence: true);
    if (!applied) throw StateError('Could not apply subscription');
    if (!current()) return false;
    session.setSyncStatus(NailuSyncStatus.ready);
    return true;
  } catch (_) {
    if (current()) session.setSyncStatus(NailuSyncStatus.failed);
    rethrow;
  }
}
