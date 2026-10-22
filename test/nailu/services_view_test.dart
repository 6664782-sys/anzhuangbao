import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/nailu/home_header.dart';
import 'package:fl_clash/nailu/services_view.dart';
import 'package:fl_clash/ui/view_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import '../helpers/test_app.dart';

Widget _scope(Widget child) =>
    ViewScope(size: const Size(390, 844), isMobile: true, child: child);

void main() {
  testWidgets('giraffe header fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const TestApp(
        locale: Locale('zh', 'CN'),
        homeBuilder: _scope,
        child: Scaffold(body: Column(children: [NailuHomeHeader()])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppLocalizations.current.nailuServices), findsOneWidget);
    expect(find.text(AppLocalizations.current.nailuHeroTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('services expose store, orders and an unconfigured TG entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TestApp(
        locale: Locale('zh', 'CN'),
        homeBuilder: _scope,
        child: NailuServicesView(),
      ),
    );
    await tester.pumpAndSettle();
    final s = AppLocalizations.current;
    expect(find.text(s.nailuPlans), findsOneWidget);
    expect(find.text(s.nailuOrders), findsOneWidget);
    await tester.scrollUntilVisible(find.text(s.nailuTelegram), 300);
    expect(find.text(s.nailuChannelPending), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
