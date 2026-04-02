import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/app_bootstrap_screen.dart';
import 'package:walkietalkie_mobile/src/app_entry.dart';
import 'package:walkietalkie_mobile/src/core/networking/api_client.dart';
import 'package:walkietalkie_mobile/src/features/auth/data/auth_repository.dart';

void main() {
  group('AppBootstrapScreen', () {
    testWidgets('shows loading indicator while restoreSession is pending', (tester) async {
      final restoreCompleter = Completer<AuthSession?>();
      final authRepository = _FakeAuthRepository(
        restoreResult: null,
        restoreCompleter: restoreCompleter,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppBootstrapScreen(
            entry: const AppEntry(),
            authRepository: authRepository,
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Giris'), findsNothing);

      restoreCompleter.complete(null);
      await tester.pumpAndSettle();

      expect(find.text('Giris'), findsOneWidget);
    });

    testWidgets('shows login screen when session is unavailable', (tester) async {
      final authRepository = _FakeAuthRepository(restoreResult: null);

      await tester.pumpWidget(
        MaterialApp(
          home: AppBootstrapScreen(
            entry: const AppEntry(),
            authRepository: authRepository,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Giris'), findsOneWidget);
      expect(find.textContaining('Kanallar -'), findsNothing);
    });

    testWidgets('shows channel list when session exists without invite token', (tester) async {
      final authRepository = _FakeAuthRepository(
        restoreResult: AuthSession(
          userId: 'user-1',
          email: 'demo@example.com',
          displayName: 'Demo User',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
        ),
      );
      var syncCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBootstrapScreen(
            entry: const AppEntry(),
            authRepository: authRepository,
            syncRegisteredDevice: () async {
              syncCalls += 1;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Kanallar - Demo User'), findsOneWidget);
      expect(syncCalls, 1);
    });

    testWidgets('shows invite accept screen when session exists and launch invite is present', (
      tester,
    ) async {
      final authRepository = _FakeAuthRepository(
        restoreResult: AuthSession(
          userId: 'user-1',
          email: 'demo@example.com',
          displayName: 'Demo User',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppBootstrapScreen(
            entry: const AppEntry(initialInviteToken: 'invite-token-123'),
            authRepository: authRepository,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Davet Kabul'), findsOneWidget);
      expect(find.text('Kanallar - Demo User'), findsNothing);
    });

    testWidgets('sync runs only once while same session stays active', (tester) async {
      final session = AuthSession(
        userId: 'user-1',
        email: 'demo@example.com',
        displayName: 'Demo User',
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
      );
      final authRepository = _FakeAuthRepository(restoreResult: session);
      var syncCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBootstrapScreen(
            entry: const AppEntry(),
            authRepository: authRepository,
            syncRegisteredDevice: () async {
              syncCalls += 1;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(syncCalls, 1);

      authRepository.emitSession(session);
      await tester.pump();
      expect(syncCalls, 1);
    });

    testWidgets('sync is scheduled again after logout and login cycle', (tester) async {
      final session = AuthSession(
        userId: 'user-1',
        email: 'demo@example.com',
        displayName: 'Demo User',
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
      );
      final authRepository = _FakeAuthRepository(restoreResult: session);
      var syncCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBootstrapScreen(
            entry: const AppEntry(),
            authRepository: authRepository,
            syncRegisteredDevice: () async {
              syncCalls += 1;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(syncCalls, 1);

      authRepository.emitSession(null);
      await tester.pumpAndSettle();
      expect(find.text('Giris'), findsOneWidget);

      authRepository.emitSession(session);
      await tester.pumpAndSettle();
      expect(syncCalls, 2);
      expect(find.text('Kanallar - Demo User'), findsOneWidget);
    });

    testWidgets('sync failure does not break channel list rendering', (tester) async {
      final authRepository = _FakeAuthRepository(
        restoreResult: AuthSession(
          userId: 'user-1',
          email: 'demo@example.com',
          displayName: 'Demo User',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppBootstrapScreen(
            entry: const AppEntry(),
            authRepository: authRepository,
            syncRegisteredDevice: () async {
              throw Exception('device sync failed');
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Kanallar - Demo User'), findsOneWidget);
    });
  });
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({required this.restoreResult, this.restoreCompleter})
    : super(ApiClient(), sessionStore: _NoopSessionStore()) {
    sessionListenable.value = restoreResult;
  }

  final AuthSession? restoreResult;
  final Completer<AuthSession?>? restoreCompleter;

  void emitSession(AuthSession? value) {
    sessionListenable.value = value;
  }

  @override
  Future<AuthSession?> restoreSession() async {
    if (restoreCompleter != null) {
      final restored = await restoreCompleter!.future;
      sessionListenable.value = restored;
      return restored;
    }
    sessionListenable.value = restoreResult;
    return restoreResult;
  }
}

class _NoopSessionStore implements AuthSessionStore {
  @override
  Future<String?> getString(String key) async => null;

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> setString(String key, String value) async {}
}
