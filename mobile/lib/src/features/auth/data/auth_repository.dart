import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/networking/api_client.dart';

abstract class AuthSessionStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class SharedPreferencesAuthSessionStore implements AuthSessionStore {
  Future<SharedPreferences> _instance() => SharedPreferences.getInstance();

  @override
  Future<String?> getString(String key) async {
    final prefs = await _instance();
    return prefs.getString(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    final prefs = await _instance();
    await prefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    final prefs = await _instance();
    await prefs.remove(key);
  }
}

class AuthSession {
  AuthSession({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final String email;
  final String displayName;
  final String accessToken;
  final String refreshToken;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      userId: json['userId'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
    );
  }
}

class AuthRepository {
  AuthRepository(this._apiClient, {AuthSessionStore? sessionStore})
    : _sessionStore = sessionStore ?? SharedPreferencesAuthSessionStore();

  static const String _userIdKey = 'auth.userId';
  static const String _emailKey = 'auth.email';
  static const String _displayNameKey = 'auth.displayName';
  static const String _accessTokenKey = 'auth.accessToken';
  static const String _refreshTokenKey = 'auth.refreshToken';

  final ApiClient _apiClient;
  final AuthSessionStore _sessionStore;
  String? _refreshToken;
  final ValueNotifier<AuthSession?> sessionListenable =
      ValueNotifier<AuthSession?>(null);

  AuthSession? get currentSession => sessionListenable.value;

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final data = await _apiClient.post(
      '/v1/auth/login',
      data: <String, dynamic>{
        'email': email,
        'password': password,
      },
    );
    final session = _sessionFromAuthPayload(data);
    await _setSession(session);
    return session;
  }

  Future<AuthSession> register({
    required String email,
    required String displayName,
    required String password,
  }) async {
    final data = await _apiClient.post(
      '/v1/auth/register',
      data: <String, dynamic>{
        'email': email,
        'displayName': displayName,
        'password': password,
      },
    );
    final session = _sessionFromAuthPayload(data);
    await _setSession(session);
    return session;
  }

  AuthSession _sessionFromAuthPayload(Map<String, dynamic> data) {
    final user = data['user'] as Map<String, dynamic>;
    final accessToken = data['accessToken'] as String? ?? '';
    final refreshToken = data['refreshToken'] as String? ?? '';
    return AuthSession(
      userId: user['id'] as String? ?? '',
      email: user['email'] as String? ?? '',
      displayName: user['displayName'] as String? ?? '',
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<AuthSession?> restoreSession() async {
    final accessToken = await _sessionStore.getString(_accessTokenKey);
    final refreshToken = await _sessionStore.getString(_refreshTokenKey);
    if (accessToken == null || refreshToken == null) {
      return null;
    }

    final savedSession = AuthSession.fromJson(<String, dynamic>{
      'userId': await _sessionStore.getString(_userIdKey),
      'email': await _sessionStore.getString(_emailKey),
      'displayName': await _sessionStore.getString(_displayNameKey),
      'accessToken': accessToken,
      'refreshToken': refreshToken,
    });

    _apiClient.setAccessToken(accessToken);
    _refreshToken = refreshToken;
    sessionListenable.value = savedSession;

    try {
      final data = await _apiClient.get('/v1/me');
      final user = data['user'] as Map<String, dynamic>;
      final refreshedSession = AuthSession(
        userId: user['id'] as String? ?? savedSession.userId,
        email: user['email'] as String? ?? savedSession.email,
        displayName: user['displayName'] as String? ?? savedSession.displayName,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      await _setSession(refreshedSession);
      return refreshedSession;
    } catch (_) {
      try {
        return await refreshSession();
      } catch (_) {
        await clearSession();
        return null;
      }
    }
  }

  Future<AuthSession> refreshSession() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('No refresh token available');
    }

    final data = await _apiClient.post(
      '/v1/auth/refresh',
      data: <String, dynamic>{'refreshToken': refreshToken},
    );
    final user = data['user'] as Map<String, dynamic>;
    final accessToken = data['accessToken'] as String? ?? '';
    final rotatedRefreshToken = data['refreshToken'] as String? ?? refreshToken;
    final session = AuthSession(
      userId: user['id'] as String? ?? '',
      email: user['email'] as String? ?? '',
      displayName: user['displayName'] as String? ?? '',
      accessToken: accessToken,
      refreshToken: rotatedRefreshToken,
    );
    await _setSession(session);
    return session;
  }

  Future<void> clearSession() async {
    await _sessionStore.remove(_userIdKey);
    await _sessionStore.remove(_emailKey);
    await _sessionStore.remove(_displayNameKey);
    await _sessionStore.remove(_accessTokenKey);
    await _sessionStore.remove(_refreshTokenKey);
    sessionListenable.value = null;
    _refreshToken = null;
    _apiClient.setAccessToken(null);
  }

  Future<void> logout({bool allDevices = false}) async {
    try {
      await _apiClient.post(
        '/v1/auth/logout',
        data: <String, dynamic>{
          'refreshToken': _refreshToken,
          'allDevices': allDevices,
        },
      );
    } catch (_) {
      // Best-effort remote logout; always clear local session below.
    } finally {
      await clearSession();
    }
  }

  Future<void> _setSession(AuthSession session) async {
    await _sessionStore.setString(_userIdKey, session.userId);
    await _sessionStore.setString(_emailKey, session.email);
    await _sessionStore.setString(_displayNameKey, session.displayName);
    await _sessionStore.setString(_accessTokenKey, session.accessToken);
    await _sessionStore.setString(_refreshTokenKey, session.refreshToken);
    _apiClient.setAccessToken(session.accessToken);
    _refreshToken = session.refreshToken;
    sessionListenable.value = session;
  }

  Future<bool> tryRefreshSession() async {
    try {
      await refreshSession();
      return true;
    } catch (_) {
      return false;
    }
  }
}
