import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/nailu/catalog.dart';
import 'package:fl_clash/nailu/session.dart';
import 'package:fl_clash/nailu/shell.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _Session extends NailuSession {
  @override
  Future<List<NailuPlan>> plans() async => [
    const NailuPlan({
      'id': 1,
      'name': '奈鹿畅游',
      'month_price': 900,
      'transfer_enable': 1000,
    }),
  ];
}

void main() {
  testWidgets(
    'compact three-tab shell keeps modes, TUN and account reachable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = _Session()
        ..phase = NailuPhase.signedIn
        ..syncStatus = NailuSyncStatus.ready
        ..account = {'email': 'test@example.invalid'}
        ..subscription = {
          'plan': {'name': '奈鹿畅游'},
          'transfer_enable': 107374182400,
          'u': 1073741824,
          'expired_at': null,
        };
      addTearDown(session.dispose);
      final container = ProviderContainer(
        overrides: [
          nailuSessionProvider.overrideWithValue(session),
          profilesProvider.overrideWith(TestProfiles.new),
        ],
      );
      globalState.container = container;
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(locale: Locale('zh', 'CN'), child: NailuShell()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('首页'), findsWidgets);
      await tester.ensureVisible(find.text('全局'));
      await tester.tap(find.text('全局'));
      await tester.pumpAndSettle();
      expect(container.read(patchClashConfigProvider).mode, Mode.global);
      final tun = find.widgetWithText(SwitchListTile, 'TUN 虚拟网卡');
      await tester.ensureVisible(tun);
      await tester.tap(tun);
      await tester.pumpAndSettle();
      expect(container.read(patchClashConfigProvider).tun.enable, true);
      await tester.tap(find.text('套餐'));
      await tester.pumpAndSettle();
      expect(find.text('奈鹿畅游'), findsOneWidget);
      await tester.tap(find.text('个人中心').last);
      await tester.pumpAndSettle();
      expect(find.text('t***@example.invalid'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
}
