import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'config.dart';

enum NailuPhase { restoring, signedOut, authorizing, signedIn }

abstract interface class NailuTokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class NailuSecureStore implements NailuTokenStore {
  const NailuSecureStore();
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class NailuSession extends ChangeNotifier {
  NailuSession({
    NailuApi? api,
    NailuTokenStore? store,
    Duration pollInterval = const Duration(seconds: 5),
  }) : _api = api ?? NailuApi(),
       _store = store ?? const NailuSecureStore(),
       _pollInterval = pollInterval;

  static const _tokenKey = 'nailu.session.v1';
  static const _deviceKey = 'nailu.device.v1';
  static const _profileKey = 'nailu.profile.v1';
  static const _emailKey = 'nailu.remembered.email.v1';
  static const _passwordKey = 'nailu.remembered.password.v1';
  final NailuApi _api;
  final NailuTokenStore _store;
  final Duration _pollInterval;
  NailuPhase phase = NailuPhase.restoring;
  Map<String, dynamic>? account;
  Map<String, dynamic>? subscription;
  Map<String, dynamic>? authorization;
  String? error;
  bool busy = false;
  int? managedProfileId;
  int _epoch = 0;
  bool _disposed = false;
  Timer? _pollTimer;
  Completer<void>? _pollWaiter;
  Future<void> _tokenWrites = Future<void>.value();

  Future<void> _persistToken(String? token, int epoch) {
    final operation = _tokenWrites.then((_) async {
      if (_disposed || epoch != _epoch) return;
      if (token == null) {
        await _store.delete(_tokenKey);
      } else {
        await _store.write(_tokenKey, token);
        if (_disposed || epoch != _epoch) await _store.delete(_tokenKey);
      }
    });
    _tokenWrites = operation.catchError((Object _) {});
    return operation;
  }

  Future<({String email, String password})?> rememberedCredentials() async {
    final email = await _store.read(_emailKey);
    final password = await _store.read(_passwordKey);
    return email != null && password != null
        ? (email: email, password: password)
        : null;
  }

  Future<void> forgetCredentials() {
    final operation = _tokenWrites.then((_) async {
      await _store.delete(_emailKey);
      await _store.delete(_passwordKey);
    });
    _tokenWrites = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _rememberCredentials(String email, String password, int epoch) {
    final operation = _tokenWrites.then((_) async {
      if (_disposed || epoch != _epoch) return;
      await _store.write(_emailKey, email);
      await _store.write(_passwordKey, password);
      if (_disposed || epoch != _epoch) {
        await _store.delete(_emailKey);
        await _store.delete(_passwordKey);
      }
    });
    _tokenWrites = operation.catchError((Object _) {});
    return operation;
  }

  void _interruptPolling() {
    _pollTimer?.cancel();
    final waiter = _pollWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> bindManagedProfile(int? id) async {
    if (id == null) {
      await _store.delete(_profileKey);
    } else {
      await _store.write(_profileKey, id.toString());
    }
    managedProfileId = id;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    final epoch = ++_epoch;
    try {
      final token = await _store.read(_tokenKey);
      final profileId = await _store.read(_profileKey);
      if (_disposed || epoch != _epoch) return;
      managedProfileId = int.tryParse(profileId ?? '');
      _api.token = token;
      if (token == null) {
        phase = NailuPhase.signedOut;
      } else {
        await refresh();
        if (!_disposed && epoch == _epoch && _api.token != null) {
          phase = NailuPhase.signedIn;
        }
      }
    } catch (failure) {
      if (!_disposed && epoch == _epoch) {
        error = failure.toString();
        phase = NailuPhase.signedOut;
      }
    } finally {
      if (!_disposed && epoch == _epoch) _emit();
    }
  }

  Future<void> login({
    required String email,
    required String password,
    required String challenge,
    bool rememberPassword = false,
  }) async {
    if (busy) throw StateError('Login already pending');
    if (email.trim().isEmpty || password.isEmpty || challenge.isEmpty) {
      throw const NailuApiException(
        'Email, password and verification required',
      );
    }
    final epoch = ++_epoch;
    _interruptPolling();
    busy = true;
    error = null;
    _emit();
    try {
      final result = await _api.call(
        'passport/auth/login',
        data: {
          'email': email.trim(),
          'password': password,
          'cf-turnstile-response': challenge,
        },
      );
      final token = result['auth_data'];
      if (token is! String || token.isEmpty) {
        throw const NailuApiException('Invalid login response');
      }
      if (_disposed || epoch != _epoch) return;
      _api.token = token;
      await refresh();
      if (_disposed || epoch != _epoch) return;
      await _persistToken(token, epoch);
      if (_disposed || epoch != _epoch) return;
      if (rememberPassword) {
        await _rememberCredentials(email.trim(), password, epoch);
      } else {
        await forgetCredentials();
      }
      if (_disposed || epoch != _epoch) return;
      authorization = null;
      phase = NailuPhase.signedIn;
    } catch (failure) {
      if (!_disposed && epoch == _epoch) {
        _api.token = null;
        account = null;
        subscription = null;
        phase = NailuPhase.signedOut;
        error = failure.toString();
      }
      rethrow;
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        _emit();
      }
    }
  }

  Future<Uri> begin(String platform) async {
    if (busy) throw StateError('Authorization already pending');
    final epoch = ++_epoch;
    busy = true;
    error = null;
    _emit();
    try {
      var device = await _store.read(_deviceKey);
      device ??= List.generate(
        32,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await _store.write(_deviceKey, device);
      final result = await _api.call(
        'guest/nailu/client/start',
        data: {'platform': platform, 'client_id': device},
      );
      final uri = Uri.parse(result['verification_uri'] as String);
      if (uri.origin != NailuConfig.origin || uri.userInfo.isNotEmpty) {
        throw const FormatException('Invalid authorization origin');
      }
      if (result['expires_in'] is! int ||
          (result['expires_in'] as int) <= 0 ||
          (result['expires_in'] as int) > 600 ||
          result['device_code'] is! String ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(result['device_code'] as String)) {
        throw const FormatException('Invalid authorization response');
      }
      if (_disposed || epoch != _epoch) {
        throw StateError('Authorization cancelled');
      }
      authorization = result;
      phase = NailuPhase.authorizing;
      unawaited(_poll(result, epoch));
      return uri;
    } catch (failure) {
      if (!_disposed && epoch == _epoch) {
        error = failure.toString();
        phase = NailuPhase.signedOut;
      }
      rethrow;
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> _poll(Map<String, dynamic> request, int epoch) async {
    final deadline = DateTime.now().add(
      Duration(seconds: request['expires_in'] as int),
    );
    while (!_disposed && epoch == _epoch && DateTime.now().isBefore(deadline)) {
      final waiter = _pollWaiter = Completer<void>();
      _pollTimer = Timer(_pollInterval, waiter.complete);
      await waiter.future;
      if (_disposed || epoch != _epoch) return;
      try {
        final result = await _api.call(
          'guest/nailu/client/poll',
          data: {'device_code': request['device_code']},
        );
        if (_disposed || epoch != _epoch) return;
        if (result['status'] == 'pending') continue;
        if (result['status'] != 'approved' || result['auth_data'] is! String) {
          break;
        }
        final token = result['auth_data'] as String;
        await _persistToken(token, epoch);
        if (_disposed || epoch != _epoch) return;
        _api.token = token;
        authorization = null;
        phase = NailuPhase.signedIn;
        await refresh();
        _emit();
        return;
      } catch (failure) {
        if (_disposed || epoch != _epoch) return;
        error = failure.toString();
        _emit();
      }
    }
    if (!_disposed && epoch == _epoch) {
      phase = NailuPhase.signedOut;
      authorization = null;
      error = 'Authorization expired. Please start again.';
      _emit();
    }
  }

  Future<void> refresh() async {
    if (_api.token == null) return;
    final epoch = _epoch;
    try {
      final result = await Future.wait([
        _api.call('user/info', authenticated: true),
        _api.call('user/getSubscribe', authenticated: true),
      ]);
      if (_disposed || epoch != _epoch) return;
      account = result[0];
      subscription = result[1];
      error = null;
    } on NailuApiException catch (failure) {
      if (_disposed || epoch != _epoch) return;
      error = failure.message;
      if (failure.unauthorized) {
        await _persistToken(null, epoch);
        if (_disposed || epoch != _epoch) return;
        _api.token = null;
        account = null;
        subscription = null;
        phase = NailuPhase.signedOut;
      }
      rethrow;
    } finally {
      if (!_disposed && epoch == _epoch) _emit();
    }
  }

  Uri? get subscriptionUri {
    final source = subscription?['subscribe_url'];
    return source is String && source.isNotEmpty
        ? NailuConfig.subscriptionUri(source)
        : null;
  }

  Future<Uri> portalUri(String route) async {
    const routes = {
      'plans',
      'orders',
      'profile',
      'tickets',
      'notices',
      'invite',
      'gift',
      'help',
      'devices',
      'traffic',
      'nodes',
      'diagnostics',
    };
    if (phase != NailuPhase.signedIn || !routes.contains(route)) {
      throw StateError('A signed-in NaiLu account is required');
    }
    final epoch = _epoch;
    final result = await _api.value(
      'user/getQuickLoginUrl',
      data: {'redirect': route},
      authenticated: true,
    );
    if (result is! String || epoch != _epoch || phase != NailuPhase.signedIn) {
      throw const NailuApiException('Cannot open account services');
    }
    final uri = Uri.parse(result);
    if (uri.scheme != 'https' ||
        uri.origin != NailuConfig.origin ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw const FormatException('Invalid account portal origin');
    }
    return uri.replace(queryParameters: {'nailu_client': '1'});
  }

  Future<void> signOut() async {
    final epoch = ++_epoch;
    busy = true;
    _interruptPolling();
    final token = _api.token;
    try {
      if (token != null) {
        final payload =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(base64Url.normalize(token.split('.')[1])),
                  ),
                )
                as Map<String, dynamic>;
        await _api.call(
          'user/removeActiveSession',
          data: {'session_id': payload['session']},
          authenticated: true,
        );
      }
    } catch (_) {
      error = 'Server session revocation was not confirmed.';
    } finally {
      await _persistToken(null, epoch);
      _api.token = null;
      account = null;
      subscription = null;
      authorization = null;
      phase = NailuPhase.signedOut;
      busy = false;
      _emit();
    }
  }

  void cancelAuthorization() {
    ++_epoch;
    _interruptPolling();
    authorization = null;
    phase = NailuPhase.signedOut;
    busy = false;
    error = null;
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _interruptPolling();
    _api.close();
    super.dispose();
  }
}

final nailuSessionProvider = Provider<NailuSession>((ref) {
  final session = NailuSession();
  ref.onDispose(session.dispose);
  unawaited(session.restore());
  return session;
});
