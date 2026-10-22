import 'package:fl_clash/nailu/account_view.dart';
import 'package:fl_clash/nailu/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  Future<void> render(WidgetTester tester, NailuSession session) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('zh', 'CN'),
        overrides: [nailuSessionProvider.overrideWithValue(session)],
        child: const NailuAccountView(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('account summary shows quota without displaying credentials', (
    tester,
  ) async {
    final session = NailuSession()
      ..phase = NailuPhase.signedIn
      ..account = {'email': 'test@example.invalid'}
      ..subscription = {
        'transfer_enable': 107374182400,
        'u': 1073741824,
        'd': 1073741824,
        'expired_at': null,
        'plan': {'name': '奈鹿轻享'},
      };
    await render(tester, session);
    expect(find.text('奈鹿轻享'), findsOneWidget);
    expect(find.textContaining('98.0 GB / 100.0 GB'), findsOneWidget);
    expect(find.text('t***@example.invalid'), findsOneWidget);
    expect(find.text('test@example.invalid'), findsNothing);
    await tester.tap(find.byTooltip('显示或隐藏邮箱'));
    await tester.pump();
    expect(find.text('test@example.invalid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
