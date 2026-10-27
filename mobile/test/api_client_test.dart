import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stanz_bizflow/core/api/api_client.dart';
import 'package:stanz_bizflow/core/api/api_error.dart';
import 'package:stanz_bizflow/core/api/token_store.dart';

/// Minimal in-memory server for exercising the client's auth handling.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions o) handler;
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    calls.add('${o.method} ${o.path} ${o.headers['Authorization'] ?? ''}'.trim());
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  test('expired access token is refreshed once and the request retried', () async {
    final tokens = MemoryTokenStore();
    await tokens.write(access: 'old', refresh: 'r1');
    final adapter = FakeAdapter((o) {
      if (o.path == '/auth/refresh') return json(200, {'access_token': 'new', 'refresh_token': 'r2'});
      return o.headers['Authorization'] == 'Bearer new' ? json(200, {'ok': true}) : json(401, {'error': {}});
    });
    final client = ApiClient(tokens: tokens, baseUrl: 'http://test')..dio.httpClientAdapter = adapter;

    final res = await client.get<Map<String, dynamic>>('/auth/me');
    expect(res['ok'], isTrue);
    expect((await tokens.read())!.refresh, 'r2', reason: 'rotated refresh token must be stored');
    expect(adapter.calls, ['GET /auth/me Bearer old', 'POST /auth/refresh', 'GET /auth/me Bearer new']);
  });

  test('rejected refresh clears tokens and reports session expiry', () async {
    final tokens = MemoryTokenStore();
    await tokens.write(access: 'old', refresh: 'stolen');
    var expired = false;
    final adapter = FakeAdapter(
      (o) => json(401, {
        'error': {'code': 'session_revoked', 'message': 'Your session has ended.'},
      }),
    );
    final client = ApiClient(tokens: tokens, baseUrl: 'http://test')
      ..dio.httpClientAdapter = adapter
      ..onSessionExpired = () => expired = true;

    await expectLater(
      client.get<Object>('/auth/me'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'session_revoked')),
    );
    expect(expired, isTrue);
    expect(await tokens.read(), isNull);
  });

  test('server error envelopes become typed errors with field details', () async {
    final adapter = FakeAdapter(
      (o) => json(422, {
        'error': {
          'code': 'validation_error',
          'message': 'The request contains invalid data.',
          'details': {
            'fields': [
              {'field': 'email', 'message': 'value is not a valid email address'},
            ],
          },
        },
      }),
    );
    final client = ApiClient(tokens: MemoryTokenStore(), baseUrl: 'http://test')..dio.httpClientAdapter = adapter;
    try {
      await client.post<Object>('/auth/register', data: {}, auth: false);
      fail('expected an error');
    } on ApiError catch (e) {
      expect(e.status, 422);
      expect(e.fieldErrors, {'email': 'value is not a valid email address'});
    }
  });
}
