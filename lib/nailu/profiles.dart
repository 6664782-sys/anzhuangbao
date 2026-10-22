import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'session.dart';

Future<bool> syncNailuProfile(WidgetRef ref, NailuSession session) async {
  await session.refresh();
  if (session.phase != NailuPhase.signedIn) return false;
  final source = session.subscription;
  if (source == null) return false;
  final quota = (source['transfer_enable'] as num?)?.toInt() ?? 0;
  final expires = (source['expired_at'] as num?)?.toInt();
  if (quota <= 0 ||
      (expires != null &&
          expires * 1000 <= DateTime.now().millisecondsSinceEpoch)) {
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
  if (session.phase != NailuPhase.signedIn) return false;
  ref.read(profilesActionProvider.notifier).putProfile(updated);
  await session.bindManagedProfile(updated.id);
  if (session.phase != NailuPhase.signedIn) return false;
  ref.read(currentProfileIdProvider.notifier).value = updated.id;
  ref.read(setupActionProvider.notifier).applyProfileDebounce(silence: true);
  return true;
}
