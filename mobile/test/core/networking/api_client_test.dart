import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/core/networking/api_client.dart';

void main() {
  group('ApiClient', () {
    test('retries authorized request after successful refresh', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 401,
          data: <String, dynamic>{'error': 'expired'},
        ),
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{'ok': true},
        ),
      ]);
      dio.httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);
      client.setAccessToken('stale-token');
      client.setRefreshHandler(() async {
        client.setAccessToken('fresh-token');
        return true;
      });

      final response = await client.get('/v1/channels');

      expect(response, <String, dynamic>{'ok': true});
      expect(adapter.requests.length, 2);
      expect(
        adapter.requests.first.headers['Authorization'],
        'Bearer stale-token',
      );
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer fresh-token',
      );
      expect(adapter.requests.last.extra['retriedAfterRefresh'], true);
    });

    test('calls unauthorized handler when refresh fails', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 401,
          data: <String, dynamic>{'error': 'expired'},
        ),
      ]);
      dio.httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);
      var unauthorizedCalls = 0;
      client.setRefreshHandler(() async => false);
      client.setUnauthorizedHandler(() async {
        unauthorizedCalls += 1;
      });

      await expectLater(
        client.get('/v1/channels'),
        throwsA(isA<DioException>()),
      );

      expect(unauthorizedCalls, 1);
      expect(adapter.requests.length, 1);
    });

    test('does not attempt refresh for auth endpoints', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 401,
          data: <String, dynamic>{'error': 'invalid credentials'},
        ),
      ]);
      dio.httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);
      var refreshAttempts = 0;
      client.setRefreshHandler(() async {
        refreshAttempts += 1;
        return true;
      });

      await expectLater(
        client.post(
          '/v1/auth/login',
          data: <String, dynamic>{'email': 'demo@example.com', 'password': 'x'},
        ),
        throwsA(isA<DioException>()),
      );

      expect(refreshAttempts, 0);
      expect(adapter.requests.length, 1);
    });

    test('does not attempt refresh for non-401 errors', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 500,
          data: <String, dynamic>{'error': 'server error'},
        ),
      ]);
      dio.httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);
      var refreshAttempts = 0;
      client.setRefreshHandler(() async {
        refreshAttempts += 1;
        return true;
      });

      await expectLater(
        client.get('/v1/channels'),
        throwsA(isA<DioException>()),
      );

      expect(refreshAttempts, 0);
      expect(adapter.requests.length, 1);
    });

    test('calls unauthorized handler when refresh handler throws', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 401,
          data: <String, dynamic>{'error': 'expired'},
        ),
      ]);
      dio.httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);
      var unauthorizedCalls = 0;
      client.setRefreshHandler(() async {
        throw Exception('refresh crashed');
      });
      client.setUnauthorizedHandler(() async {
        unauthorizedCalls += 1;
      });

      await expectLater(
        client.get('/v1/channels'),
        throwsA(isA<DioException>()),
      );

      expect(unauthorizedCalls, 1);
      expect(adapter.requests.length, 1);
    });

    test('skips refresh when no refresh handler is configured', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 401,
          data: <String, dynamic>{'error': 'expired'},
        ),
      ]);
      dio.httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);

      await expectLater(
        client.get('/v1/channels'),
        throwsA(isA<DioException>()),
      );

      expect(adapter.requests.length, 1);
    });

  });
}

class _QueueHttpClientAdapter implements HttpClientAdapter {
  _QueueHttpClientAdapter(this.responses);

  final List<_AdapterResponse> responses;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (responses.isEmpty) {
      throw StateError('No queued adapter response for ${options.path}');
    }

    final response = responses.removeAt(0);
    return ResponseBody.fromString(
      response.jsonBody,
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _AdapterResponse {
  _AdapterResponse({required this.statusCode, required this.data});

  final int statusCode;
  final Map<String, dynamic> data;

  String get jsonBody => jsonEncode(data);
}
