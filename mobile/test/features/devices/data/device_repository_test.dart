import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/core/networking/api_client.dart';
import 'package:walkietalkie_mobile/src/features/devices/data/device_repository.dart';

void main() {
  test('DeviceRepository registers device payload', () async {
    final adapter = _QueueHttpClientAdapter([
      _AdapterResponse(
        statusCode: 200,
        data: <String, dynamic>{'device': <String, dynamic>{'id': 'device-1'}},
      ),
    ]);
    final repository = DeviceRepository(_apiClientWith(adapter));

    await repository.registerDevice(
      DeviceRegistration(
        platform: 'android',
        pushToken: 'push-token-1',
        appVersion: '0.1.0',
      ),
    );

    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.path, '/v1/devices');
    expect(adapter.requests.single.method, 'POST');
    expect(
      adapter.requests.single.data,
      <String, dynamic>{
        'platform': 'android',
        'pushToken': 'push-token-1',
        'appVersion': '0.1.0',
      },
    );
  });

  test('DeviceRepository surfaces api errors from register endpoint', () async {
    final adapter = _QueueHttpClientAdapter([
      _AdapterResponse(
        statusCode: 401,
        data: <String, dynamic>{'error': 'unauthorized'},
      ),
    ]);
    final repository = DeviceRepository(_apiClientWith(adapter));

    await expectLater(
      repository.registerDevice(
        DeviceRegistration(
          platform: 'android',
          pushToken: 'push-token-1',
          appVersion: '0.1.0',
        ),
      ),
      throwsA(isA<DioException>()),
    );
  });
}

ApiClient _apiClientWith(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
  dio.httpClientAdapter = adapter;
  return ApiClient(dio: dio);
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
      jsonEncode(response.data),
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
}
