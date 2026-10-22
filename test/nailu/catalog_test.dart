import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:fl_clash/nailu/api.dart';
import 'package:fl_clash/nailu/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.payload);
  final dynamic payload;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, 'user/plan/fetch');
    expect(options.headers['Authorization'], 'session');
    return ResponseBody.fromString(
      jsonEncode({'data': payload}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'catalog uses backend cents and all enabled periods without multiplying prices',
    () async {
      final api = NailuApi(
        client: Dio()
          ..httpClientAdapter = _Adapter([
            {
              'id': 10,
              'name': 'NaiLu',
              'month_price': 900,
              'quarter_price': 2700,
              'half_year_price': 5400,
              'year_price': 10800,
              'two_year_price': 21600,
              'three_year_price': 32400,
              'onetime_price': null,
            },
            {'id': 11, 'onetime_price': 3150, 'month_price': null},
          ]),
      )..token = 'session';
      addTearDown(api.close);
      final result = await fetchNailuPlans(api);
      expect(result.length, 2);
      expect(result.first.price('quarter_price'), 2700);
      expect(result.first.periods.length, 6);
      expect(result.last.periodic, false);
      expect(result.last.price('onetime_price'), 3150);
    },
  );
  test(
    'malformed catalog reports a failure instead of an endless loading state',
    () async {
      final api = NailuApi(
        client: Dio()..httpClientAdapter = _Adapter('invalid'),
      )..token = 'session';
      addTearDown(api.close);
      await expectLater(
        fetchNailuPlans(api),
        throwsA(isA<NailuApiException>()),
      );
    },
  );
  test(
    'details become readable plain text and capacity controls availability',
    () {
      const plan = NailuPlan({
        'id': 1,
        'capacity_limit': 0,
        'content': '<p>IEPL &amp; VLESS</p><p>1×<br>4K–8K</p>',
        'year_price': 10800,
      });
      expect(plan.soldOut, true);
      expect(plan.description, 'IEPL & VLESS\n1×\n4K–8K');
      expect(nailuBytes(1073741824), '1.0 GB');
      expect(nailuBytes(1099511627776), '1.0 TB');
    },
  );
}
