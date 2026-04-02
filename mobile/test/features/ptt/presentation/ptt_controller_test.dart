import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/features/channels/data/channel_repository.dart';
import 'package:walkietalkie_mobile/src/features/ptt/data/media_session_service.dart';
import 'package:walkietalkie_mobile/src/features/ptt/domain/ptt_state.dart';
import 'package:walkietalkie_mobile/src/features/ptt/presentation/ptt_controller.dart';

void main() {
  group('PttController', () {
    test('initialize loads bootstrap and enters listening state', () async {
      final channelRepository = _FakeChannelSessionRepository(
        bootstrap: JoinChannelBootstrap(
          channelId: 'alpha',
          liveKitUrl: 'wss://livekit.example.com',
          liveKitToken: 'lk-token',
          webSocketUrl: 'ws://localhost:8080/v1/ws',
          iceServers: <String>['stun:one'],
          activeSpeaker: 'user-2',
        ),
      );
      final mediaSessionService = _FakeMediaSessionController(
        snapshot: MediaSessionSnapshot(
          bootstrap: channelRepository.bootstrap,
          localAudioReady: true,
          localAudioPermissionDenied: false,
          messages: const Stream<Map<String, dynamic>>.empty(),
          micEnabled: false,
          roomConnected: true,
        ),
      );
      final controller = PttController(
        channelRepository: channelRepository,
        mediaSessionService: mediaSessionService,
      );

      await controller.initialize(targetChannelId: 'alpha', userId: 'user-1');

      expect(controller.state, PttState.listening);
      expect(controller.channelId, 'alpha');
      expect(controller.activeSpeaker, 'user-2');
      expect(controller.channelBusy, true);
      expect(controller.localAudioReady, true);
      expect(controller.roomConnected, true);
    });

    test('requestTalk sends websocket speaker request and marks requesting', () async {
      final controller = await _initializedController();

      await controller.requestTalk();

      expect(controller.state, PttState.requestingTalk);
      expect(controller.mediaSessionService is _FakeMediaSessionController, true);
      final media = controller.mediaSessionService as _FakeMediaSessionController;
      expect(media.sentPayloads.last, <String, dynamic>{
        'type': 'speaker.request',
        'channelId': 'alpha',
      });
    });

    test('speaker granted message enables mic and enters speaking state', () async {
      final setup = await _initializedControllerWithMedia();
      final controller = setup.controller;
      final media = setup.media;

      await controller.requestTalk();
      media.emit(<String, dynamic>{
        'type': 'speaker.granted',
        'channelId': 'alpha',
        'userId': 'user-1',
      });
      await pumpEventQueue();

      expect(controller.state, PttState.speaking);
      expect(controller.activeSpeaker, 'user-1');
      expect(controller.channelBusy, false);
      expect(controller.micEnabled, true);
      expect(media.enableMicCalls, 1);
    });

    test('speaker denied message disables mic and returns to listening', () async {
      final setup = await _initializedControllerWithMedia();
      final controller = setup.controller;
      final media = setup.media;

      await controller.requestTalk();
      media.emit(<String, dynamic>{
        'type': 'speaker.denied',
        'channelId': 'alpha',
        'owner': 'user-2',
      });
      await pumpEventQueue();

      expect(controller.state, PttState.listening);
      expect(controller.activeSpeaker, 'user-2');
      expect(controller.channelBusy, true);
      expect(controller.micEnabled, false);
      expect(media.disableMicCalls, 1);
    });

    test('releaseTalk disables mic and sends release payload', () async {
      final setup = await _initializedControllerWithMedia();
      final controller = setup.controller;
      final media = setup.media;

      await controller.requestTalk();
      media.emit(<String, dynamic>{
        'type': 'speaker.granted',
        'channelId': 'alpha',
        'userId': 'user-1',
      });
      await pumpEventQueue();

      await controller.releaseTalk();

      expect(controller.state, PttState.listening);
      expect(controller.micEnabled, false);
      expect(media.disableMicCalls, greaterThanOrEqualTo(1));
      expect(media.sentPayloads.last, <String, dynamic>{
        'type': 'speaker.release',
        'channelId': 'alpha',
      });
    });

    test('speaker renew timer sends periodic renew while speaking', () async {
      final setup = await _initializedControllerWithMedia(
        speakerRenewInterval: const Duration(milliseconds: 15),
      );
      final controller = setup.controller;
      final media = setup.media;
      await controller.requestTalk();
      media.emit(<String, dynamic>{
        'type': 'speaker.granted',
        'channelId': 'alpha',
        'userId': 'user-1',
      });
      await pumpEventQueue();

      expect(controller.state, PttState.speaking);
      final sentBeforeRenew = media.sentPayloads.length;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(media.sentPayloads.length, greaterThan(sentBeforeRenew));
      expect(
        media.sentPayloads.where((payload) => payload['type'] == 'speaker.renew').isNotEmpty,
        true,
      );
      await controller.dispose();
    });

    test('failed speaker renew returns controller to listening', () async {
      final setup = await _initializedControllerWithMedia(
        speakerRenewInterval: const Duration(milliseconds: 15),
      );
      final controller = setup.controller;
      final media = setup.media;
      await controller.requestTalk();
      media.emit(<String, dynamic>{
        'type': 'speaker.granted',
        'channelId': 'alpha',
        'userId': 'user-1',
      });
      await pumpEventQueue();
      media.emit(<String, dynamic>{
        'type': 'speaker.renewed',
        'channelId': 'alpha',
        'ok': false,
      });
      await pumpEventQueue();

      expect(controller.state, PttState.listening);
      expect(controller.micEnabled, false);
      expect(controller.channelBusy, false);
      expect(media.disableMicCalls, greaterThanOrEqualTo(1));
      await controller.dispose();
    });

    test('room disconnect and reconnect updates state machine', () async {
      final setup = await _initializedControllerWithMedia(
        roomStatePollInterval: const Duration(milliseconds: 20),
      );
      final controller = setup.controller;
      final media = setup.media;

      media.roomConnectedValue = false;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(controller.state, PttState.reconnecting);

      media.roomConnectedValue = true;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(controller.state, PttState.listening);
      await controller.dispose();
    });

    test('dispose tears down media session exactly once', () async {
      final setup = await _initializedControllerWithMedia();
      final controller = setup.controller;
      final media = setup.media;

      await controller.dispose();

      expect(media.disposeCalls, 1);
    });

    test('dispose stops room state timer updates', () async {
      final setup = await _initializedControllerWithMedia(
        roomStatePollInterval: const Duration(milliseconds: 20),
      );
      final controller = setup.controller;
      final media = setup.media;
      await controller.dispose();

      media.roomConnectedValue = false;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(controller.state, PttState.listening);
    });
  });
}

Future<PttController> _initializedController() async {
  final setup = await _initializedControllerWithMedia();
  return setup.controller;
}

Future<_ControllerSetup> _initializedControllerWithMedia({
  Duration? speakerRenewInterval,
  Duration? roomStatePollInterval,
}) async {
  final bootstrap = JoinChannelBootstrap(
    channelId: 'alpha',
    liveKitUrl: 'wss://livekit.example.com',
    liveKitToken: 'lk-token',
    webSocketUrl: 'ws://localhost:8080/v1/ws',
    iceServers: <String>['stun:one'],
    activeSpeaker: null,
  );
  final channelRepository = _FakeChannelSessionRepository(bootstrap: bootstrap);
  final media = _FakeMediaSessionController(
    snapshot: MediaSessionSnapshot(
      bootstrap: bootstrap,
      localAudioReady: true,
      localAudioPermissionDenied: false,
      messages: const Stream<Map<String, dynamic>>.empty(),
      micEnabled: false,
      roomConnected: true,
    ),
  );
  final controller = PttController(
    channelRepository: channelRepository,
    mediaSessionService: media,
    speakerRenewInterval: speakerRenewInterval ?? const Duration(seconds: 1),
    roomStatePollInterval: roomStatePollInterval ?? const Duration(seconds: 2),
  );
  await controller.initialize(targetChannelId: 'alpha', userId: 'user-1');
  return _ControllerSetup(controller: controller, media: media);
}

class _ControllerSetup {
  _ControllerSetup({required this.controller, required this.media});

  final PttController controller;
  final _FakeMediaSessionController media;
}

class _FakeChannelSessionRepository implements ChannelSessionRepository {
  _FakeChannelSessionRepository({required this.bootstrap});

  final JoinChannelBootstrap bootstrap;

  @override
  Future<JoinChannelBootstrap> joinChannel(String channelId) async => bootstrap;
}

class _FakeMediaSessionController implements MediaSessionController {
  _FakeMediaSessionController({required MediaSessionSnapshot snapshot})
    : _snapshot = snapshot;

  final StreamController<Map<String, dynamic>> _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  final MediaSessionSnapshot _snapshot;
  final List<Map<String, dynamic>> sentPayloads = <Map<String, dynamic>>[];
  int enableMicCalls = 0;
  int disableMicCalls = 0;
  int disposeCalls = 0;
  bool _roomConnected = true;

  set roomConnectedValue(bool value) {
    _roomConnected = value;
  }

  void emit(Map<String, dynamic> message) {
    _messagesController.add(message);
  }

  @override
  Future<MediaSessionSnapshot> connect({
    required JoinChannelBootstrap bootstrap,
    required String userId,
  }) async {
    _roomConnected = _snapshot.roomConnected;
    return MediaSessionSnapshot(
      bootstrap: _snapshot.bootstrap,
      localAudioReady: _snapshot.localAudioReady,
      localAudioPermissionDenied: _snapshot.localAudioPermissionDenied,
      messages: _messagesController.stream,
      micEnabled: _snapshot.micEnabled,
      roomConnected: _snapshot.roomConnected,
    );
  }

  @override
  Future<void> disableMic() async {
    disableMicCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _messagesController.close();
  }

  @override
  Future<void> enableMic() async {
    enableMicCalls += 1;
  }

  @override
  Future<LocalAudioState> prepareLocalAudio() async {
    return LocalAudioState(
      ready: _snapshot.localAudioReady,
      permissionDenied: _snapshot.localAudioPermissionDenied,
    );
  }

  @override
  bool get roomConnected => _roomConnected;

  @override
  void send(Map<String, dynamic> payload) {
    sentPayloads.add(payload);
  }
}
