import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/features/channels/presentation/invite_accept_screen.dart';

void main() {
  group('InviteAcceptScreen', () {
    testWidgets('shows validation error for empty token', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InviteAcceptScreen(),
        ),
      );

      await tester.tap(find.text('Daveti Kabul Et'));
      await tester.pumpAndSettle();

      expect(find.text('Gecerli bir davet baglantisi veya token girin.'), findsOneWidget);
    });

    testWidgets('accepts deep link input and navigates to channel room', (tester) async {
      String? acceptedToken;

      await tester.pumpWidget(
        MaterialApp(
          home: InviteAcceptScreen(
            initialInviteToken: 'walkietalkie://invite/open?invite=invite-token-123',
            acceptInvite: (inviteToken) async {
              acceptedToken = inviteToken;
              return 'channel-1';
            },
          ),
        ),
      );

      await tester.tap(find.text('Daveti Kabul Et'));
      await tester.pumpAndSettle();

      expect(acceptedToken, 'invite-token-123');
      expect(find.text('Invite Channel'), findsOneWidget);
    });

    testWidgets('shows API error when invite fails with dio payload', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InviteAcceptScreen(
            initialInviteToken: 'invite-token-123',
            acceptInvite: (_) async {
              final ro = RequestOptions(path: '/v1/invites/x/accept');
              throw DioException(
                requestOptions: ro,
                response: Response<dynamic>(
                  requestOptions: ro,
                  statusCode: 404,
                  data: <String, dynamic>{'error': 'invite not found'},
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Daveti Kabul Et'));
      await tester.pumpAndSettle();

      expect(find.text('invite not found'), findsOneWidget);
    });

    testWidgets('shows error when invite acceptance fails', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InviteAcceptScreen(
            initialInviteToken: 'invite-token-123',
            acceptInvite: (_) async {
              throw Exception('accept failed');
            },
          ),
        ),
      );

      await tester.tap(find.text('Daveti Kabul Et'));
      await tester.pumpAndSettle();

      expect(find.text('Davet kabul edilemedi.'), findsOneWidget);
    });

    testWidgets('clears shown error when user edits invite input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InviteAcceptScreen(
            initialInviteToken: 'invite-token-123',
            acceptInvite: (_) async {
              throw Exception('accept failed');
            },
          ),
        ),
      );

      await tester.tap(find.text('Daveti Kabul Et'));
      await tester.pumpAndSettle();
      expect(find.text('Davet kabul edilemedi.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'invite-token-abc');
      await tester.pump();

      expect(find.text('Davet kabul edilemedi.'), findsNothing);
    });

    testWidgets('uses loading state while invite accept request is pending', (tester) async {
      final completer = Completer<String>();

      await tester.pumpWidget(
        MaterialApp(
          home: InviteAcceptScreen(
            initialInviteToken: 'invite-token-123',
            acceptInvite: (_) => completer.future,
          ),
        ),
      );

      await tester.tap(find.text('Daveti Kabul Et'));
      await tester.pump();

      expect(find.text('Bekleyin...'), findsOneWidget);

      completer.complete('channel-1');
      await tester.pumpAndSettle();

      expect(find.text('Invite Channel'), findsOneWidget);
    });

    testWidgets('parses and trims whitespace around invite token', (tester) async {
      String? acceptedToken;

      await tester.pumpWidget(
        MaterialApp(
          home: InviteAcceptScreen(
            acceptInvite: (inviteToken) async {
              acceptedToken = inviteToken;
              return 'channel-1';
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '   invite-token-xyz   ');
      await tester.tap(find.text('Daveti Kabul Et'));
      await tester.pumpAndSettle();

      expect(acceptedToken, 'invite-token-xyz');
    });
  });
}
