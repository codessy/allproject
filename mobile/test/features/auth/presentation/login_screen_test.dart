import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/features/auth/data/auth_repository.dart';
import 'package:walkietalkie_mobile/src/features/auth/presentation/login_screen.dart';

void main() {
  group('LoginScreen', () {
    testWidgets('shows validation error when email is empty', (tester) async {
      var loginCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            login: ({required email, required password}) async {
              loginCalls += 1;
              return AuthSession(
                userId: 'user-1',
                email: email,
                displayName: 'Demo',
                accessToken: 'a',
                refreshToken: 'r',
              );
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, '');
      await tester.tap(find.text('Giris Yap'));
      await tester.pumpAndSettle();

      expect(find.text('E-posta zorunlu.'), findsOneWidget);
      expect(loginCalls, 0);
    });

    testWidgets('shows validation error when password is empty', (tester) async {
      var loginCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            login: ({required email, required password}) async {
              loginCalls += 1;
              return AuthSession(
                userId: 'user-1',
                email: email,
                displayName: 'Demo',
                accessToken: 'a',
                refreshToken: 'r',
              );
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.tap(find.text('Giris Yap'));
      await tester.pumpAndSettle();

      expect(find.text('Sifre zorunlu.'), findsOneWidget);
      expect(loginCalls, 0);
    });

    testWidgets('clears shown error when user edits email field', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            login: ({required email, required password}) async {
              throw Exception('login failed');
            },
          ),
        ),
      );

      await tester.tap(find.text('Giris Yap'));
      await tester.pumpAndSettle();
      expect(find.text('Giris basarisiz. Backend calisiyor mu kontrol edin.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'new@example.com');
      await tester.pump();

      expect(find.text('Giris basarisiz. Backend calisiyor mu kontrol edin.'), findsNothing);
    });

    testWidgets('shows validation error when displayName is empty in register mode', (tester) async {
      var registerCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            register: ({required email, required displayName, required password}) async {
              registerCalls += 1;
              return AuthSession(
                userId: 'user-1',
                email: email,
                displayName: displayName,
                accessToken: 'a',
                refreshToken: 'r',
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Hesabin yok mu? Kayit ol'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.tap(find.text('Kayit Ol'));
      await tester.pumpAndSettle();

      expect(find.text('Gorunen ad bos olamaz.'), findsOneWidget);
      expect(registerCalls, 0);
    });

    testWidgets('shows API error message when login returns dio payload', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            login: ({required email, required password}) async {
              final ro = RequestOptions(path: '/v1/auth/login');
              throw DioException(
                requestOptions: ro,
                response: Response<dynamic>(
                  requestOptions: ro,
                  statusCode: 401,
                  data: <String, dynamic>{'error': 'invalid credentials'},
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Giris Yap'));
      await tester.pumpAndSettle();

      expect(find.text('invalid credentials'), findsOneWidget);
    });

    testWidgets('shows error when login fails', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            login: ({required email, required password}) async {
              throw Exception('login failed');
            },
          ),
        ),
      );

      await tester.tap(find.text('Giris Yap'));
      await tester.pumpAndSettle();

      expect(find.text('Giris basarisiz. Backend calisiyor mu kontrol edin.'), findsOneWidget);
    });

    testWidgets('navigates to channel list after successful login', (tester) async {
      var syncCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            login: ({required email, required password}) async {
              return AuthSession(
                userId: 'user-1',
                email: email,
                displayName: 'Demo User',
                accessToken: 'access-1',
                refreshToken: 'refresh-1',
              );
            },
            syncRegisteredDevice: () async {
              syncCalls += 1;
            },
          ),
        ),
      );

      await tester.tap(find.text('Giris Yap'));
      await tester.pumpAndSettle();

      expect(syncCalls, 1);
      expect(find.text('Kanallar - Demo User'), findsOneWidget);
    });

    testWidgets('navigates to invite screen when invite token is provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            initialInviteToken: 'invite-token-123',
            login: ({required email, required password}) async {
              return AuthSession(
                userId: 'user-1',
                email: email,
                displayName: 'Demo User',
                accessToken: 'access-1',
                refreshToken: 'refresh-1',
              );
            },
            syncRegisteredDevice: () async {},
          ),
        ),
      );

      await tester.tap(find.text('Giris Yap'));
      await tester.pumpAndSettle();

      expect(find.text('Davet Kabul'), findsOneWidget);
    });

    testWidgets('trims email before calling login callback', (tester) async {
      var capturedEmail = '';

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            login: ({required email, required password}) async {
              capturedEmail = email;
              return AuthSession(
                userId: 'user-1',
                email: email,
                displayName: 'Demo User',
                accessToken: 'access-1',
                refreshToken: 'refresh-1',
              );
            },
            syncRegisteredDevice: () async {},
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, '  demo@example.com  ');
      await tester.tap(find.text('Giris Yap'));
      await tester.pumpAndSettle();

      expect(capturedEmail, 'demo@example.com');
    });

    testWidgets('register mode navigates to channel list on success', (tester) async {
      var syncCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            register: ({
              required email,
              required displayName,
              required password,
            }) async {
              return AuthSession(
                userId: 'user-2',
                email: email,
                displayName: displayName,
                accessToken: 'access-2',
                refreshToken: 'refresh-2',
              );
            },
            syncRegisteredDevice: () async {
              syncCalls += 1;
            },
          ),
        ),
      );

      await tester.tap(find.text('Hesabin yok mu? Kayit ol'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kayit Ol'));
      await tester.pumpAndSettle();

      expect(syncCalls, 1);
      expect(find.text('Kanallar - Yeni Kullanici'), findsOneWidget);
    });

    testWidgets('shows API error message when register returns dio payload', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            register: ({
              required email,
              required displayName,
              required password,
            }) async {
              final ro = RequestOptions(path: '/v1/auth/register');
              throw DioException(
                requestOptions: ro,
                response: Response<dynamic>(
                  requestOptions: ro,
                  statusCode: 409,
                  data: <String, dynamic>{'error': 'user could not be created'},
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Hesabin yok mu? Kayit ol'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kayit Ol'));
      await tester.pumpAndSettle();

      expect(find.text('user could not be created'), findsOneWidget);
    });

    testWidgets('shows error when register fails', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            register: ({
              required email,
              required displayName,
              required password,
            }) async {
              throw Exception('conflict');
            },
          ),
        ),
      );

      await tester.tap(find.text('Hesabin yok mu? Kayit ol'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kayit Ol'));
      await tester.pumpAndSettle();

      expect(find.text('Kayit basarisiz. Email zaten kayitli olabilir.'), findsOneWidget);
    });

    testWidgets('disables submit button while login is in progress', (tester) async {
      final completer = Completer<AuthSession>();

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            login: ({required email, required password}) => completer.future,
            syncRegisteredDevice: () async {},
          ),
        ),
      );

      await tester.tap(find.text('Giris Yap'));
      await tester.pump();

      expect(find.text('Bekleyin...'), findsOneWidget);

      completer.complete(
        AuthSession(
          userId: 'user-1',
          email: 'demo@example.com',
          displayName: 'Demo User',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kanallar - Demo User'), findsOneWidget);
    });
  });
}
