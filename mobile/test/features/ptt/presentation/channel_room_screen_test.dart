import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/features/channels/data/channel_repository.dart';
import 'package:walkietalkie_mobile/src/features/ptt/domain/ptt_state.dart';
import 'package:walkietalkie_mobile/src/features/ptt/presentation/channel_room_screen.dart';
import 'package:walkietalkie_mobile/src/features/ptt/presentation/ptt_controller.dart';
import 'package:walkietalkie_mobile/src/features/ptt/data/media_session_service.dart';
import 'package:walkietalkie_mobile/src/features/ptt/widgets/ptt_button.dart';
// ignore_for_file: invalid_use_of_protected_member

// ---------------------------------------------------------------------------
// Fake collaborators
// ---------------------------------------------------------------------------

class _FakeChannelRepo implements ChannelSessionRepository {
  final Future<JoinChannelBootstrap> Function() joinFn;

  _FakeChannelRepo({required this.joinFn});

  @override
  Future<JoinChannelBootstrap> joinChannel(String channelId) => joinFn();
}

class _FakeMediaSession implements MediaSessionController {
  final List<Map<String, dynamic>> sent = [];
  bool _room = false;
  String? connectedUserId;

  void setRoom(bool value) => _room = value;

  @override
  Future<MediaSessionSnapshot> connect({
    required JoinChannelBootstrap bootstrap,
    required String userId,
  }) async {
    connectedUserId = userId;
    return MediaSessionSnapshot(
      bootstrap: bootstrap,
      messages: const Stream.empty(),
      localAudioReady: true,
      localAudioPermissionDenied: false,
      micEnabled: false,
      roomConnected: _room,
    );
  }

  @override
  bool get roomConnected => _room;

  @override
  Future<void> enableMic() async {}

  @override
  Future<void> disableMic() async {}

  @override
  Future<LocalAudioState> prepareLocalAudio() async {
    return const LocalAudioState(ready: true, permissionDenied: false);
  }

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

JoinChannelBootstrap _bootstrap({String channelId = 'ch-1'}) =>
    JoinChannelBootstrap(
      channelId: channelId,
      liveKitUrl: 'wss://lk.test',
      liveKitToken: 'tok',
      webSocketUrl: 'wss://ws.test',
      iceServers: const <String>[],
      activeSpeaker: null,
    );

Future<PttController> _makeController({
  Future<JoinChannelBootstrap> Function()? joinFn,
  _FakeMediaSession? media,
}) async {
  final repo = _FakeChannelRepo(joinFn: joinFn ?? () async => _bootstrap());
  final sess = media ?? _FakeMediaSession();
  return PttController(
    channelRepository: repo,
    mediaSessionService: sess,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChannelRoomScreen', () {
    testWidgets('shows connecting indicator while initializing', (tester) async {
      final joinCompleter = Completer<JoinChannelBootstrap>();
      final repo = _FakeChannelRepo(
        joinFn: () => joinCompleter.future,
      );
      final ctrl = PttController(
        channelRepository: repo,
        mediaSessionService: _FakeMediaSession(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Test Kanal',
            controller: ctrl,
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      joinCompleter.complete(_bootstrap());
      await tester.pumpAndSettle();
      ctrl.dispose();
    });

    testWidgets('shows error message when channel join fails', (tester) async {
      final repo = _FakeChannelRepo(
        joinFn: () async => throw Exception('join failed'),
      );
      final ctrl = PttController(
        channelRepository: repo,
        mediaSessionService: _FakeMediaSession(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Test Kanal',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Kanal oturumu baslatilamadi.'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('shows channel name in app bar', (tester) async {
      final ctrl = await _makeController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Alfa Kanali'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('shows listening status label after successful init', (tester) async {
      final ctrl = await _makeController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Dinleme modundasiniz'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('shows livekit url from bootstrap', (tester) async {
      final ctrl = await _makeController(
        joinFn: () async => _bootstrap(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('wss://lk.test'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('reflects state changes pushed from controller', (tester) async {
      final ctrl = await _makeController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Dinleme modundasiniz'), findsOneWidget);

      ctrl.state = PttState.speaking;
      ctrl.notifyListeners();
      await tester.pump();

      expect(find.text('Konusuyorsunuz'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('shows room waiting text when room is not connected', (tester) async {
      final media = _FakeMediaSession()..setRoom(false);
      final ctrl = await _makeController(media: media);

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('LiveKit oda baglantisi bekleniyor'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('shows room ready text when room is connected', (tester) async {
      final media = _FakeMediaSession()..setRoom(true);
      final ctrl = await _makeController(media: media);

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('LiveKit oda baglantisi hazir'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('shows mic ready text from initialized snapshot', (tester) async {
      final ctrl = await _makeController();

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Mikrofon hazir'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('long press sends speaker request and release messages', (tester) async {
      final media = _FakeMediaSession()..setRoom(true);
      final ctrl = await _makeController(media: media);

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(find.byType(PttButton)));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();

      expect(
        media.sent.where((payload) => payload['type'] == 'speaker.request').isNotEmpty,
        true,
      );
      expect(
        media.sent.where((payload) => payload['type'] == 'speaker.release').isNotEmpty,
        true,
      );

      ctrl.dispose();
    });

    testWidgets('busy channel prevents request message from ptt button', (tester) async {
      final media = _FakeMediaSession()..setRoom(true);
      final ctrl = await _makeController(media: media);

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();
      ctrl.channelBusy = true;
      ctrl.notifyListeners();
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(find.byType(PttButton)));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();

      expect(find.text('Kanal Mesgul'), findsOneWidget);
      expect(
        media.sent.where((payload) => payload['type'] == 'speaker.request').isEmpty,
        true,
      );

      ctrl.dispose();
    });

    testWidgets('passes injected userId to controller initialize flow', (tester) async {
      final media = _FakeMediaSession()..setRoom(true);
      final ctrl = await _makeController(media: media);

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
            userId: 'user-42',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(media.connectedUserId, 'user-42');

      ctrl.dispose();
    });

    testWidgets('uses default demo-user when userId is not provided', (tester) async {
      final media = _FakeMediaSession()..setRoom(true);
      final ctrl = await _makeController(media: media);

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelRoomScreen(
            channelId: 'ch-1',
            channelName: 'Alfa Kanali',
            controller: ctrl,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(media.connectedUserId, 'demo-user');

      ctrl.dispose();
    });
  });
}
