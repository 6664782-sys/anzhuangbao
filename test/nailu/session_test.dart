import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/nailu/api.dart';
import 'package:fl_clash/nailu/config.dart';
import 'package:fl_clash/nailu/session.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements NailuTokenStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
  final Future<ResponseBody> Function(RequestOptions) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handle(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

NailuApi _api(Future<ResponseBody> Function(RequestOptions) handle) => NailuApi(
  client: Dio(BaseOptions(baseUrl: NailuConfig.api))
    ..httpClientAdapter = _Adapter(handle),
);

Map<String, dynamic> _authorization() => {
  'data': {
    'verification_uri':
        'https://nailu.pro/#/client-auth?user_code=ABCD-1234-5678',
    'device_code': List.filled(64, 'a').join(),
    'user_code': 'ABCD-1234-5678',
    'expires_in': 600,
    'interval': 5,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'account services use a short-lived backend URL and reject substituted origins',
    () async {
      var destination =
          'https://nailu.pro/#/login?verify=00000000-0000-0000-0000-000000000001&redirect=plans';
      final session = NailuSession(
        store: _Store(),
        api: _api((options) async {
          if (options.path == 'passport/auth/login') {
            return _json({
              'data': {'auth_data': 'native-session'},
            });
          }
          if (options.path == 'user/getQuickLoginUrl') {
            expect(options.headers['Authorization'], 'native-session');
            expect(options.data, {'redirect': 'plans'});
            return _json({'data': destination});
          }
          return _json({'data': <String, dynamic>{}});
        }),
      );
      await expectLater(session.portalUri('plans'), throwsStateError);
      await session.login(
        email: 'a@b.co',
        password: 'pw',
        challenge: 'verified',
      );
      final uri = await session.portalUri('plans');
      expect(uri.queryParameters['nailu_client'], '1');
      expect(uri.fragment, contains('verify='));
      await expectLater(
        session.portalUri('https://attacker.example'),
        throwsStateError,
      );
      destination = 'https://attacker.example/#/login?verify=example';
      await expectLater(session.portalUri('plans'), throwsFormatException);
      session.dispose();
    },
  );

  test(
    'remembered credentials survive logout and can be removed explicitly',
    () async {
      final store = _Store();
      final session = NailuSession(
        store: store,
        api: _api((options) async {
          return _json({
            'data': options.path == 'passport/auth/login'
                ? {'auth_data': 'remembered-session'}
                : <String, dynamic>{},
          });
        }),
      );
      await session.login(
        email: 'remember@nailu.pro',
        password: 'saved-password',
        challenge: 'verified',
        rememberPassword: true,
      );
      expect(await session.rememberedCredentials(), (
        email: 'remember@nailu.pro',
        password: 'saved-password',
      ));
      await session.signOut();
      expect(session.phase, NailuPhase.signedOut);
      expect(store.values.containsKey('nailu.session.v1'), isFalse);
      expect(
        (await session.rememberedCredentials())?.email,
        'remember@nailu.pro',
      );
      await session.forgetCredentials();
      expect(await session.rememberedCredentials(), isNull);
      session.dispose();
    },
  );

  test(
    'native login validates the backend session and never stores the password',
    () async {
      final store = _Store();
      final session = NailuSession(
        store: store,
        api: _api((options) async {
          if (options.path == 'passport/auth/login') {
            expect(options.method, 'POST');
            expect(options.data, {
              'email': 'user@nailu.pro',
              'password': 'secret-password',
              'cf-turnstile-response': 'verified',
            });
            return _json({
              'data': {'auth_data': 'session-token'},
            });
          }
          expect(options.headers['Authorization'], 'session-token');
          return _json({
            'data': options.path == 'user/info'
                ? {'email': 'user@nailu.pro'}
                : {
                    'subscribe_url':
                        'https://nailu.pro/api/v1/client/subscribe?token=example',
                  },
          });
        }),
      );
      await session.login(
        email: ' user@nailu.pro ',
        password: 'secret-password',
        challenge: 'verified',
      );
      expect(session.phase, NailuPhase.signedIn);
      expect(store.values['nailu.session.v1'], 'session-token');
      expect(
        store.values.values.any((value) => value.contains('secret-password')),
        isFalse,
      );
      expect(session.subscriptionUri!.queryParameters['flag'], 'meta');
      session.dispose();
    },
  );

  test('native login cannot submit without the Cloudflare token', () async {
    var calls = 0;
    final session = NailuSession(
      store: _Store(),
      api: _api((_) async {
        calls++;
        return _json({'data': {}});
      }),
    );
    await expectLater(
      session.login(email: 'a@b.co', password: 'pw', challenge: ''),
      throwsA(isA<NailuApiException>()),
    );
    expect(calls, 0);
    session.dispose();
  });

  test('rejected credentials never unlock or persist a session', () async {
    final store = _Store();
    final session = NailuSession(
      store: store,
      api: _api((_) async => _json({'message': 'Rejected'}, status: 422)),
    );
    await expectLater(
      session.login(email: 'a@b.co', password: 'wrong', challenge: 'verified'),
      throwsA(isA<NailuApiException>()),
    );
    expect(session.phase, NailuPhase.signedOut);
    expect(store.values, isEmpty);
    expect(session.busy, isFalse);
    session.dispose();
  });

  test('only trusted HTTPS subscription origins receive the meta flag', () {
    final uri = NailuConfig.subscriptionUri(
      'https://cn1.nailu.club/api/v1/client/subscribe?token=example&flag=clash',
    );
    expect(uri.queryParameters['flag'], 'meta');
    expect(uri.queryParameters['token'], 'example');
    for (final source in [
      'http://nailu.pro/api/v1/client/subscribe',
      'https://nailu.pro.attacker.test/',
      'https://name@nailu.pro/',
      'https://nailu.pro:8443/',
    ]) {
      expect(() => NailuConfig.subscriptionUri(source), throwsFormatException);
    }
  });

  test('restoring a revoked session removes local credentials', () async {
    final store = _Store()..values['nailu.session.v1'] = 'revoked';
    final session = NailuSession(
      store: store,
      api: _api((options) async {
        expect(options.headers['Authorization'], 'revoked');
        return _json({'message': 'Expired'}, status: 403);
      }),
    );
    await session.restore();
    expect(session.phase, NailuPhase.signedOut);
    expect(store.values.containsKey('nailu.session.v1'), isFalse);
    expect(session.subscription, isNull);
    session.dispose();
  });

  test(
    'offline restore retains credentials but requires login verification',
    () async {
      final store = _Store()..values['nailu.session.v1'] = 'existing';
      final session = NailuSession(
        store: store,
        api: _api((options) async => _json({}, status: 503)),
      );
      await session.restore();
      expect(session.phase, NailuPhase.signedOut);
      expect(store.values['nailu.session.v1'], 'existing');
      expect(session.error, isNotNull);
      session.dispose();
    },
  );

  test('rejects a substituted browser authorization origin', () async {
    final result = _authorization();
    (result['data'] as Map)['verification_uri'] = 'https://attacker.test/';
    final session = NailuSession(
      store: _Store(),
      api: _api((_) async => _json(result)),
    );
    await expectLater(session.begin('windows'), throwsFormatException);
    expect(session.phase, NailuPhase.signedOut);
    session.dispose();
  });

  test('cancelling before approval prevents polling and login', () async {
    var calls = 0;
    final store = _Store();
    final session = NailuSession(
      store: store,
      api: _api((_) async {
        calls++;
        return _json(_authorization());
      }),
    );
    await session.begin('windows');
    expect(session.phase, NailuPhase.authorizing);
    session.cancelAuthorization();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(session.phase, NailuPhase.signedOut);
    expect(store.values.containsKey('nailu.session.v1'), isFalse);
    session.dispose();
  });

  test(
    'late authorization response cannot log in after cancellation',
    () async {
      final pending = Completer<ResponseBody>();
      final polling = Completer<void>();
      final store = _Store();
      final session = NailuSession(
        store: store,
        pollInterval: const Duration(milliseconds: 1),
        api: _api((options) async {
          if (options.path.endsWith('/start')) return _json(_authorization());
          polling.complete();
          return pending.future;
        }),
      );
      await session.begin('android');
      await polling.future;
      session.cancelAuthorization();
      pending.complete(
        _json({
          'data': {'status': 'approved', 'auth_data': 'late'},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, NailuPhase.signedOut);
      expect(store.values.containsKey('nailu.session.v1'), isFalse);
      session.dispose();
    },
  );

  test('logout clears local token even when server revocation fails', () async {
    final store = _Store()..values['nailu.session.v1'] = 'invalid-test-token';
    final session = NailuSession(
      store: store,
      api: _api((_) async => _json({'data': {}})),
    );
    await session.restore();
    await session.signOut();
    expect(session.phase, NailuPhase.signedOut);
    expect(session.account, isNull);
    expect(store.values.containsKey('nailu.session.v1'), isFalse);
    session.dispose();
  });

  test(
    'approved device login saves the session and loads its subscription',
    () async {
      final store = _Store();
      final loaded = Completer<void>();
      final session = NailuSession(
        store: store,
        pollInterval: const Duration(milliseconds: 1),
        api: _api((options) async {
          if (options.path.endsWith('/start')) return _json(_authorization());
          if (options.path.endsWith('/poll')) {
            return _json({
              'data': {'status': 'approved', 'auth_data': 'native-session'},
            });
          }
          expect(options.headers['Authorization'], 'native-session');
          if (options.path.endsWith('/info')) {
            return _json({
              'data': {'email': 'test@example.invalid'},
            });
          }
          return _json({
            'data': {
              'subscribe_url':
                  'https://nailu.pro/api/v1/client/subscribe?token=example',
              'transfer_enable': 107374182400,
            },
          });
        }),
      );
      session.addListener(() {
        if (session.account != null &&
            session.subscription != null &&
            !loaded.isCompleted) {
          loaded.complete();
        }
      });
      await session.begin('macos');
      await loaded.future.timeout(const Duration(seconds: 2));
      expect(session.phase, NailuPhase.signedIn);
      expect(store.values['nailu.session.v1'], 'native-session');
      expect(session.subscriptionUri?.queryParameters['flag'], 'meta');
      expect(session.authorization, isNull);
      session.dispose();
    },
  );
}
