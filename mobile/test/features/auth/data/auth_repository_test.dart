import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/core/networking/api_client.dart';
import 'package:walkietalkie_mobile/src/features/auth/data/auth_repository.dart';

void main() {
  group('AuthRepository', () {
    test('register stores session like login', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 201,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-2',
              'email': 'new@example.com',
              'displayName': 'New User',
            },
            'accessToken': 'access-new',
            'refreshToken': 'refresh-new',
          },
        ),
      ]);
      final store = _InMemoryAuthSessionStore();
      final repository = AuthRepository(
        _apiClientWith(adapter),
        sessionStore: store,
      );

      final session = await repository.register(
        email: 'new@example.com',
        displayName: 'New User',
        password: 'secret123',
      );

      expect(session.userId, 'user-2');
      expect(repository.currentSession?.accessToken, 'access-new');
      expect(adapter.requests.single.path, '/v1/auth/register');
      expect(
        adapter.requests.single.data,
        <String, dynamic>{
          'email': 'new@example.com',
          'displayName': 'New User',
          'password': 'secret123',
        },
      );
    });

    test('login stores session and exposes currentSession', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
          },
        ),
      ]);
      final store = _InMemoryAuthSessionStore();
      final repository = AuthRepository(
        _apiClientWith(adapter),
        sessionStore: store,
      );

      final session = await repository.login(
        email: 'demo@example.com',
        password: 'password',
      );

      expect(session.userId, 'user-1');
      expect(repository.currentSession?.accessToken, 'access-1');
      expect(await store.getString('auth.refreshToken'), 'refresh-1');
      expect(adapter.requests.single.path, '/v1/auth/login');
    });

    test('restoreSession returns null when persisted session is missing', () async {
      final repository = AuthRepository(
        _apiClientWith(_QueueHttpClientAdapter([])),
        sessionStore: _InMemoryAuthSessionStore(),
      );

      final session = await repository.restoreSession();

      expect(session, isNull);
      expect(repository.currentSession, isNull);
    });

    test('restoreSession refreshes profile when me succeeds', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'fresh@example.com',
              'displayName': 'Fresh Demo',
            },
          },
        ),
      ]);
      final store = _InMemoryAuthSessionStore(
        values: <String, String>{
          'auth.userId': 'user-1',
          'auth.email': 'stale@example.com',
          'auth.displayName': 'Stale Demo',
          'auth.accessToken': 'access-1',
          'auth.refreshToken': 'refresh-1',
        },
      );
      final repository = AuthRepository(
        _apiClientWith(adapter),
        sessionStore: store,
      );

      final session = await repository.restoreSession();

      expect(session, isNotNull);
      expect(session?.email, 'fresh@example.com');
      expect(session?.displayName, 'Fresh Demo');
      expect(repository.currentSession?.email, 'fresh@example.com');
      expect(adapter.requests.single.path, '/v1/me');
    });

    test('restoreSession falls back to refresh and clears on failure', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 401,
          data: <String, dynamic>{'error': 'expired'},
        ),
        _AdapterResponse(
          statusCode: 401,
          data: <String, dynamic>{'error': 'refresh failed'},
        ),
      ]);
      final store = _InMemoryAuthSessionStore(
        values: <String, String>{
          'auth.userId': 'user-1',
          'auth.email': 'demo@example.com',
          'auth.displayName': 'Demo',
          'auth.accessToken': 'access-1',
          'auth.refreshToken': 'refresh-1',
        },
      );
      final repository = AuthRepository(
        _apiClientWith(adapter),
        sessionStore: store,
      );

      final session = await repository.restoreSession();

      expect(session, isNull);
      expect(repository.currentSession, isNull);
      expect(await store.getString('auth.accessToken'), isNull);
      expect(adapter.requests.map((request) => request.path), [
        '/v1/me',
        '/v1/auth/refresh',
      ]);
    });

    test('refreshSession rotates tokens and updates persisted state', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
          },
        ),
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
          },
        ),
      ]);
      final store = _InMemoryAuthSessionStore(
        values: <String, String>{
          'auth.userId': 'user-1',
          'auth.email': 'demo@example.com',
          'auth.displayName': 'Demo',
          'auth.accessToken': 'access-1',
          'auth.refreshToken': 'refresh-1',
        },
      );
      final repository = AuthRepository(
        _apiClientWith(adapter),
        sessionStore: store,
      );
      await repository.restoreSession();

      final session = await repository.refreshSession();

      expect(session.accessToken, 'access-2');
      expect(session.refreshToken, 'refresh-2');
      expect(await store.getString('auth.accessToken'), 'access-2');
      expect(await store.getString('auth.refreshToken'), 'refresh-2');
    });

    test('logout clears persisted session even when request succeeds', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
          },
        ),
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{'loggedOut': true},
        ),
      ]);
      final store = _InMemoryAuthSessionStore(
        values: <String, String>{
          'auth.userId': 'user-1',
          'auth.email': 'demo@example.com',
          'auth.displayName': 'Demo',
          'auth.accessToken': 'access-1',
          'auth.refreshToken': 'refresh-1',
        },
      );
      final repository = AuthRepository(
        _apiClientWith(adapter),
        sessionStore: store,
      );
      await repository.restoreSession();

      await repository.logout(allDevices: true);

      expect(repository.currentSession, isNull);
      expect(await store.getString('auth.refreshToken'), isNull);
      expect(adapter.requests.last.path, '/v1/auth/logout');
      expect(
        adapter.requests.last.data,
        <String, dynamic>{'refreshToken': 'refresh-1', 'allDevices': true},
      );
    });

    test('logout clears local session even when api request fails', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
          },
        ),
        _AdapterResponse(
          statusCode: 500,
          data: <String, dynamic>{'error': 'server error'},
        ),
      ]);
      final store = _InMemoryAuthSessionStore(
        values: <String, String>{
          'auth.userId': 'user-1',
          'auth.email': 'demo@example.com',
          'auth.displayName': 'Demo',
          'auth.accessToken': 'access-1',
          'auth.refreshToken': 'refresh-1',
        },
      );
      final repository = AuthRepository(
        _apiClientWith(adapter),
        sessionStore: store,
      );
      await repository.restoreSession();

      await repository.logout();

      expect(repository.currentSession, isNull);
      expect(await store.getString('auth.accessToken'), isNull);
      expect(adapter.requests.last.path, '/v1/auth/logout');
    });

    test('refreshSession updates session on repeated calls', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
          },
        ),
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
          },
        ),
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
            'accessToken': 'access-3',
            'refreshToken': 'refresh-3',
          },
        ),
      ]);
      final store = _InMemoryAuthSessionStore(
        values: <String, String>{
          'auth.userId': 'user-1',
          'auth.email': 'demo@example.com',
          'auth.displayName': 'Demo',
          'auth.accessToken': 'access-1',
          'auth.refreshToken': 'refresh-1',
        },
      );
      final repository = AuthRepository(
        _apiClientWith(adapter),
        sessionStore: store,
      );
      await repository.restoreSession();

      final first = await repository.refreshSession();
      final second = await repository.refreshSession();

      expect(first.accessToken, 'access-2');
      expect(second.accessToken, 'access-3');
      expect(
        adapter.requests.where((request) => request.path == '/v1/auth/refresh').length,
        2,
      );
    });

    test('tryRefreshSession returns false when refresh fails', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
          },
        ),
        _AdapterResponse(
          statusCode: 401,
          data: <String, dynamic>{'error': 'refresh failed'},
        ),
      ]);
      final store = _InMemoryAuthSessionStore(
        values: <String, String>{
          'auth.userId': 'user-1',
          'auth.email': 'demo@example.com',
          'auth.displayName': 'Demo',
          'auth.accessToken': 'access-1',
          'auth.refreshToken': 'refresh-1',
        },
      );
      final repository = AuthRepository(
        _apiClientWith(adapter),
        sessionStore: store,
      );
      await repository.restoreSession();

      final refreshed = await repository.tryRefreshSession();

      expect(refreshed, false);
    });

    test('tryRefreshSession returns true when refresh succeeds', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
          },
        ),
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'demo@example.com',
              'displayName': 'Demo',
            },
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
          },
        ),
      ]);
      final store = _InMemoryAuthSessionStore(
        values: <String, String>{
          'auth.userId': 'user-1',
          'auth.email': 'demo@example.com',
          'auth.displayName': 'Demo',
          'auth.accessToken': 'access-1',
          'auth.refreshToken': 'refresh-1',
        },
      );
      final repository = AuthRepository(
        _apiClientWith(adapter),
        sessionStore: store,
      );
      await repository.restoreSession();

      final refreshed = await repository.tryRefreshSession();

      expect(refreshed, true);
      expect(repository.currentSession?.accessToken, 'access-2');
    });

    test('refreshSession throws when refresh token is unavailable', () async {
      final repository = AuthRepository(
        _apiClientWith(_QueueHttpClientAdapter([])),
        sessionStore: _InMemoryAuthSessionStore(),
      );

      await expectLater(
        repository.refreshSession(),
        throwsA(isA<StateError>()),
      );
    });
  });
}

ApiClient _apiClientWith(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
  dio.httpClientAdapter = adapter;
  return ApiClient(dio: dio);
}

class _InMemoryAuthSessionStore implements AuthSessionStore {
  _InMemoryAuthSessionStore({Map<String, String>? values})
    : _values = values ?? <String, String>{};

  final Map<String, String> _values;

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }
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
