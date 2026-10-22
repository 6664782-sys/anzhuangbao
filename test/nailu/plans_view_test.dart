import 'package:fl_clash/nailu/catalog.dart';
import 'package:fl_clash/nailu/plans_view.dart';
import 'package:fl_clash/nailu/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import '../helpers/test_app.dart';

class _Session extends NailuSession {
  bool fail = false;
  int calls = 0;
  @override
  Future<List<NailuPlan>> plans() async {
    calls++;
    if (fail) throw StateError('offline');
    return [
      const NailuPlan({
        'id': 1,
        'name': 'NaiLu recurring',
        'transfer_enable': 1000,
        'device_limit': 1,
        'speed_limit': 3000,
        'month_price': 900,
        'year_price': 10800,
        'content': '<p>Monthly reset</p>',
      }),
      const NailuPlan({
        'id': 2,
        'name': 'NaiLu one-time',
        'transfer_enable': 5000,
        'device_limit': 2,
        'onetime_price': 13350,
      }),
    ];
  }
}

void main() {
  Future<void> pump(WidgetTester tester, _Session session) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [nailuSessionProvider.overrideWithValue(session)],
        child: const TestApp(
          locale: Locale('zh', 'CN'),
          child: Scaffold(body: NailuPlansView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows real backend price and switches to a single yearly price',
    (tester) async {
      final session = _Session();
      addTearDown(session.dispose);
      await pump(tester, session);
      expect(find.text('¥9.00 / 月付'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('一年 · ¥108.00').last);
      await tester.pumpAndSettle();
      expect(find.text('¥108.00 / 一年'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
  testWidgets('category chips separate recurring and one-time plans', (
    tester,
  ) async {
    final session = _Session();
    addTearDown(session.dispose);
    await pump(tester, session);
    await tester.tap(find.text('一次性').first);
    await tester.pumpAndSettle();
    expect(find.text('NaiLu one-time'), findsOneWidget);
    expect(find.text('NaiLu recurring'), findsNothing);
    await tester.tap(find.text('周期性'));
    await tester.pumpAndSettle();
    expect(find.text('NaiLu recurring'), findsOneWidget);
    expect(find.text('NaiLu one-time'), findsNothing);
  });
  testWidgets(
    'failed load offers a working retry and never shows a blank page',
    (tester) async {
      final session = _Session()..fail = true;
      addTearDown(session.dispose);
      await pump(tester, session);
      expect(find.text('套餐加载失败，请检查网络后重试。'), findsOneWidget);
      session.fail = false;
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(session.calls, 2);
      expect(find.text('NaiLu recurring'), findsOneWidget);
    },
  );
}
