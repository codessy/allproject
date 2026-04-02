import 'package:dio/dio.dart';

class ApiClient {
  static const String _retryMarkerExtraKey = 'retriedAfterRefresh';
  static const String _retryMarkerHeader = 'x-retried-after-refresh';

  ApiClient({String baseUrl = 'http://localhost:8080', Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl)) {
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onError: (error, handler) async {
          if (!_shouldAttemptRefresh(error)) {
            handler.next(error);
            return;
          }

          final refreshHandler = _refreshHandler;
          if (refreshHandler == null) {
            handler.next(error);
            return;
          }

          try {
            final refreshed = await refreshHandler();
            if (!refreshed) {
              await _unauthorizedHandler?.call();
              handler.next(error);
              return;
            }

            final retryResponse = await _retry(error.requestOptions);
            handler.resolve(retryResponse);
          } catch (_) {
            await _unauthorizedHandler?.call();
            handler.next(error);
          }
        },
      ),
    );
  }

  final Dio _dio;
  String? _accessToken;
  Future<bool> Function()? _refreshHandler;
  Future<void> Function()? _unauthorizedHandler;

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  void setRefreshHandler(Future<bool> Function()? handler) {
    _refreshHandler = handler;
  }

  void setUnauthorizedHandler(Future<void> Function()? handler) {
    _unauthorizedHandler = handler;
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: data,
      options: _options(),
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      path,
      data: data,
      options: _options(),
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      path,
      data: data,
      options: _options(),
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> get(String path) async {
    final response = await _dio.get<Map<String, dynamic>>(
      path,
      options: _options(),
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      path,
      options: _options(),
    );
    return response.data ?? <String, dynamic>{};
  }

  Options _options() {
    return Options(
      headers: _accessToken == null
          ? null
          : <String, String>{'Authorization': 'Bearer $_accessToken'},
    );
  }

  bool _shouldAttemptRefresh(DioException error) {
    if (error.response?.statusCode != 401) {
      return false;
    }

    final path = error.requestOptions.path;
    if (path == '/v1/auth/login' ||
        path == '/v1/auth/register' ||
        path == '/v1/auth/refresh' ||
        path == '/v1/auth/logout') {
      return false;
    }

    if (error.requestOptions.extra[_retryMarkerExtraKey] == true) {
      return false;
    }
    final retriedHeader = error.requestOptions.headers[_retryMarkerHeader];
    if (retriedHeader == 'true') {
      return false;
    }

    return true;
  }

  Future<Response<Map<String, dynamic>>> _retry(RequestOptions requestOptions) {
    final headers = <String, dynamic>{
      ...requestOptions.headers,
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      _retryMarkerHeader: 'true',
    };
    final retried = requestOptions.copyWith(
      headers: headers,
      extra: <String, dynamic>{
        ...requestOptions.extra,
        _retryMarkerExtraKey: true,
      },
    );
    return _dio.fetch<Map<String, dynamic>>(retried);
  }
}
