import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/features/channels/data/channel_repository.dart';
import 'package:walkietalkie_mobile/src/features/channels/presentation/channel_list_screen.dart';
import 'package:walkietalkie_mobile/src/features/ptt/presentation/channel_room_screen.dart';

void main() {
  group('ChannelListScreen', () {
    testWidgets('shows loading then error message when channels fail to load', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async => throw Exception('load failed'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();

      expect(
        find.text('Kanallar yuklenemedi. Backend ve DB durumunu kontrol edin.'),
        findsOneWidget,
      );
    });

    testWidgets('shows channel rows and management action for admin', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async => <ChannelSummary>[
              ChannelSummary(
                id: 'channel-1',
                name: 'Alpha',
                type: 'private',
                ownerUserId: 'owner-1',
                role: 'admin',
              ),
              ChannelSummary(
                id: 'channel-2',
                name: 'Bravo',
                type: 'public',
                ownerUserId: 'owner-2',
                role: 'member',
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.byTooltip('Kanali Yonet'), findsOneWidget);
      expect(find.text('private · rol: admin'), findsOneWidget);
      expect(find.text('public · rol: member'), findsOneWidget);
    });

    testWidgets('shows empty list without crashing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async => <ChannelSummary>[],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Henuz kanal bulunmuyor.'), findsOneWidget);
      expect(find.text('Yenilemek icin asagi cekin.'), findsOneWidget);
      expect(find.text('Kanallar - Demo User'), findsOneWidget);
    });

    testWidgets('logout navigates back to login screen', (tester) async {
      var logoutCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async => <ChannelSummary>[],
            logout: () async {
              logoutCalls += 1;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cikis Yap'));
      await tester.pumpAndSettle();

      expect(logoutCalls, 1);
      expect(find.text('Giris'), findsOneWidget);
    });

    testWidgets('channel tap navigates to room screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async => <ChannelSummary>[
              ChannelSummary(
                id: 'channel-1',
                name: 'Alpha',
                type: 'private',
                ownerUserId: 'owner-1',
                role: 'member',
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(find.byType(ChannelRoomScreen), findsOneWidget);
    });

    testWidgets('invite action navigates to invite accept screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async => <ChannelSummary>[],
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Davet Kabul Et'));
      await tester.pumpAndSettle();

      expect(find.text('Davet Kabul'), findsOneWidget);
    });

    testWidgets('shows placeholder role when channel role is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async => <ChannelSummary>[
              ChannelSummary(
                id: 'channel-1',
                name: 'Alpha',
                type: 'private',
                ownerUserId: 'owner-1',
                role: '',
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('private · rol: -'), findsOneWidget);
    });

    testWidgets('owner role also sees management action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async => <ChannelSummary>[
              ChannelSummary(
                id: 'channel-1',
                name: 'Alpha',
                type: 'private',
                ownerUserId: 'owner-1',
                role: 'owner',
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byTooltip('Kanali Yonet'), findsOneWidget);
    });

    testWidgets('logout failure shows error and stays on channel screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async => <ChannelSummary>[],
            logout: () async {
              throw Exception('logout failed');
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cikis Yap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Cikis yapilamadi.'), findsOneWidget);
      expect(find.text('Kanallar - Demo User'), findsOneWidget);
    });

    testWidgets('logout shows progress indicator while request is pending', (tester) async {
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async => <ChannelSummary>[],
            logout: () => completer.future,
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cikis Yap'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.text('Giris'), findsOneWidget);
    });

    testWidgets('retry button reloads channels after load error', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: () async {
              calls += 1;
              if (calls == 1) {
                throw Exception('load failed');
              }
              return <ChannelSummary>[
                ChannelSummary(
                  id: 'channel-1',
                  name: 'Alpha',
                  type: 'private',
                  ownerUserId: 'owner-1',
                  role: 'member',
                ),
              ];
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('pull to refresh calls listChannels again', (tester) async {
      var calls = 0;
      Future<List<ChannelSummary>> load() async {
        calls += 1;
        return <ChannelSummary>[
          ChannelSummary(
            id: 'channel-1',
            name: 'Alpha',
            type: 'private',
            ownerUserId: 'owner-1',
            role: 'member',
          ),
        ];
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelListScreen(
            currentUserName: 'Demo User',
            listChannels: load,
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(calls, 1);

      await tester.fling(find.byType(ListView), const Offset(0, 400), 3000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(calls, greaterThanOrEqualTo(2));
    });
  });
}
