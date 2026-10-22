import 'package:dio/dio.dart';

import 'config.dart';

class NailuApiException implements Exception {
  const NailuApiException(this.message, {this.unauthorized = false});

  final String message;
  final bool unauthorized;

  @override
  String toString() => message;
}

class NailuApi {
  NailuApi({Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              baseUrl: NailuConfig.api,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 12),
              followRedirects: false,
              headers: {
                'Accept': 'application/json',
                'Cache-Control': 'no-store',
                'User-Agent': 'NaiLu/0.3.0',
              },
            ),
          );

  final Dio _client;
  String? token;

  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, dynamic>? data,
    bool authenticated = false,
  }) async {
    final payload = await value(path, data: data, authenticated: authenticated);
    if (payload is! Map) {
      throw const NailuApiException('Invalid server response');
    }
    return Map<String, dynamic>.from(payload);
  }

  Future<dynamic> value(
    String path, {
    Map<String, dynamic>? data,
    bool authenticated = false,
  }) async {
    try {
      final response = await _client.request<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(
          method: data == null ? 'GET' : 'POST',
          headers: {if (authenticated && token != null) 'Authorization': token},
        ),
      );
      if (response.data?.containsKey('data') != true) {
        throw const NailuApiException('Invalid server response');
      }
      return response.data!['data'];
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final payload = error.response?.data;
      final message = payload is Map ? payload['message'] : null;
      throw NailuApiException(
        message is String && message.length < 300
            ? message
            : 'Cannot connect to NaiLu. Please try again.',
        unauthorized: status == 401 || status == 403,
      );
    }
  }

  void close() => _client.close(force: true);
}
