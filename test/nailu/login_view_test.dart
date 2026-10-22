import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/nailu/auth_gate.dart';
import 'package:fl_clash/nailu/login_view.dart';
import 'package:fl_clash/nailu/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

class _Session extends NailuSession {
  String? email;
  String? password;
  String? challenge;
  bool fail = false;

  @override
  Future<void> login({
    required String email,
    required String password,
    required String challenge,
    bool rememberPassword = false,
  }) async {
    this.email = email;
    this.password = password;
    this.challenge = challenge;
    if (fail) throw StateError('Rejected');
    phase = NailuPhase.signedIn;
    notifyListeners();
  }

  @override
  Future<({String email, String password})?> rememberedCredentials() async =>
      null;

  void expire() {
    phase = NailuPhase.signedOut;
    notifyListeners();
  }
}

void main() {
  testWidgets('requires email, password and verification before signing in', (
    tester,
  ) async {
    final session = _Session()..phase = NailuPhase.signedOut;
    addTearDown(session.dispose);
    ValueChanged<String?>? verify;
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('zh', 'CN'),
        child: NailuLoginView(
          session: session,
          challengeBuilder: (callback) {
            verify = callback;
            return const SizedBox(height: 30);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(
      FilledButton,
      AppLocalizations.current.nailuLogin,
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextFormField).first, 'user@nailu.pro');
    await tester.enterText(find.byType(TextFormField).last, 'test-password');
    verify!('verified-token');
    await tester.pump();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(session.email, 'user@nailu.pro');
    expect(session.password, 'test-password');
    expect(session.challenge, 'verified-token');
    final password = tester.widget<TextFormField>(
      find.byType(TextFormField).last,
    );
    expect(password.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed login resets verification and remains on the form', (
    tester,
  ) async {
    final session = _Session()
      ..phase = NailuPhase.signedOut
      ..fail = true;
    addTearDown(session.dispose);
    ValueChanged<String?>? verify;
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('zh', 'CN'),
        child: NailuLoginView(
          session: session,
          challengeBuilder: (callback) {
            verify = callback;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'user@nailu.pro');
    await tester.enterText(find.byType(TextFormField).last, 'incorrect');
    verify!('single-use');
    await tester.pump();
    final button = find.widgetWithText(
      FilledButton,
      AppLocalizations.current.nailuLogin,
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(session.phase, NailuPhase.signedOut);
    expect(
      find.text(AppLocalizations.current.nailuLoginFailed),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'auth gate blocks navigation content until signed in and after expiry',
    (tester) async {
      final session = _Session()..phase = NailuPhase.signedOut;
      addTearDown(session.dispose);
      await tester.pumpWidget(
        TestApp(
          child: NailuAuthGate(
            session: session,
            login: const Text('Login required'),
            child: const Text('Private dashboard'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Login required'), findsOneWidget);
      expect(find.text('Private dashboard'), findsNothing);
      await session.login(email: 'a@b.co', password: 'pw', challenge: 'token');
      await tester.pumpAndSettle();
      expect(find.text('Private dashboard'), findsOneWidget);
      session.expire();
      await tester.pumpAndSettle();
      expect(find.text('Private dashboard'), findsNothing);
      expect(find.text('Login required'), findsOneWidget);
    },
  );
}
