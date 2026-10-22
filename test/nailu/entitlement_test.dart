import 'package:fl_clash/nailu/profiles.dart';
import 'package:fl_clash/nailu/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 23);
  test('long-term subscriptions accept both null and zero expiry', () {
    for (final expiry in [null, 0]) {
      expect(
        nailuEntitlement({'transfer_enable': 1000, 'expired_at': expiry}, now),
        NailuSyncStatus.ready,
      );
    }
  });
  test('distinguishes no plan, expired and exhausted subscriptions', () {
    expect(nailuEntitlement({}, now), NailuSyncStatus.noPlan);
    expect(
      nailuEntitlement({'transfer_enable': 1000, 'expired_at': 1}, now),
      NailuSyncStatus.expired,
    );
    expect(
      nailuEntitlement({'transfer_enable': 1000, 'u': 400, 'd': 600}, now),
      NailuSyncStatus.exhausted,
    );
    expect(
      nailuEntitlement({'transfer_enable': 1000, 'u': 0, 'd': 999}, now),
      NailuSyncStatus.ready,
    );
  });
}
