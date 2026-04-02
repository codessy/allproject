import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../core/realtime/ws_client.dart';
import '../../channels/data/channel_repository.dart';

abstract class MediaSessionController {
  Future<MediaSessionSnapshot> connect({
    required JoinChannelBootstrap bootstrap,
    required String userId,
  });

  Future<void> enableMic();
  Future<void> disableMic();
  Future<LocalAudioState> prepareLocalAudio();
  bool get roomConnected;
  void send(Map<String, dynamic> payload);
  Future<void> dispose();
}

class LocalAudioState {
  const LocalAudioState({
    required this.ready,
    required this.permissionDenied,
  });

  final bool ready;
  final bool permissionDenied;
}

class MediaSessionSnapshot {
  MediaSessionSnapshot({
    required this.bootstrap,
    required this.localAudioReady,
    required this.localAudioPermissionDenied,
    required this.messages,
    required this.micEnabled,
    required this.roomConnected,
  });

  final JoinChannelBootstrap bootstrap;
  final bool localAudioReady;
  final bool localAudioPermissionDenied;
  final Stream<Map<String, dynamic>> messages;
  final bool micEnabled;
  final bool roomConnected;
}

class MediaSessionService implements MediaSessionController {
  MediaSessionService(this._wsClient);

  final WsClient _wsClient;
  MediaStream? _localStream;
  MediaStreamTrack? _audioTrack;
  lk.Room? _room;
  bool _localAudioPermissionDenied = false;

  @override
  Future<MediaSessionSnapshot> connect({
    required JoinChannelBootstrap bootstrap,
    required String userId,
  }) async {
    _wsClient.connect('${bootstrap.webSocketUrl}?userId=$userId');
    _wsClient.send(<String, dynamic>{
      'type': 'channel.subscribe',
      'channelId': bootstrap.channelId,
    });

    // Try to prepare local audio early so hold-to-talk can enable it instantly.
    // If media permission is denied, continue with control-plane + room session.
    await prepareLocalAudio();

    _room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: false,
        dynacast: false,
        defaultAudioPublishOptions: lk.AudioPublishOptions(
          dtx: true,
        ),
      ),
    );
    try {
      await _room!.connect(
        bootstrap.liveKitUrl,
        bootstrap.liveKitToken,
      );
      await _room!.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {
      // Keep the control-plane session alive even if the LiveKit room is temporarily unavailable.
    }

    return MediaSessionSnapshot(
      bootstrap: bootstrap,
      localAudioReady: _audioTrack != null,
      localAudioPermissionDenied: _localAudioPermissionDenied,
      messages: _wsClient.messages,
      micEnabled: false,
      roomConnected: _room?.connectionState == lk.ConnectionState.connected,
    );
  }

  @override
  Future<void> enableMic() async {
    _audioTrack?.enabled = true;
    await _room?.localParticipant?.setMicrophoneEnabled(true);
  }

  @override
  Future<void> disableMic() async {
    _audioTrack?.enabled = false;
    await _room?.localParticipant?.setMicrophoneEnabled(false);
  }

  @override
  Future<LocalAudioState> prepareLocalAudio() async {
    try {
      await _localStream?.dispose();
      _localStream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      final tracks = _localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
      if (tracks.isNotEmpty) {
        _audioTrack = tracks.first;
        _audioTrack?.enabled = false;
      } else {
        _audioTrack = null;
      }

      _localAudioPermissionDenied = false;
      return LocalAudioState(
        ready: _audioTrack != null,
        permissionDenied: false,
      );
    } catch (_) {
      _localStream = null;
      _audioTrack = null;
      _localAudioPermissionDenied = true;
      return const LocalAudioState(
        ready: false,
        permissionDenied: true,
      );
    }
  }

  @override
  bool get roomConnected => _room?.connectionState == lk.ConnectionState.connected;

  @override
  void send(Map<String, dynamic> payload) {
    _wsClient.send(payload);
  }

  @override
  Future<void> dispose() async {
    await _room?.dispose();
    await _audioTrack?.stop();
    await _localStream?.dispose();
    await _wsClient.dispose();
  }
}
