import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../channels/data/channel_repository.dart';
import '../data/media_session_service.dart';
import '../domain/ptt_state.dart';

class PttController extends ChangeNotifier {
  PttController({
    required this.channelRepository,
    required this.mediaSessionService,
    this.speakerRenewInterval = const Duration(seconds: 1),
    this.roomStatePollInterval = const Duration(seconds: 2),
    this.roomReconnectTimeout = const Duration(seconds: 8),
  });

  final ChannelSessionRepository channelRepository;
  final MediaSessionController mediaSessionService;
  final Duration speakerRenewInterval;
  final Duration roomStatePollInterval;
  final Duration roomReconnectTimeout;

  PttState state = PttState.disconnected;
  String? error;
  String? channelId;
  String? activeSpeaker;
  JoinChannelBootstrap? bootstrap;
  bool channelBusy = false;
  bool localAudioReady = false;
  bool localAudioPermissionDenied = false;
  bool micEnabled = false;
  bool roomConnected = false;
  int reconnectAttempts = 0;
  StreamSubscription<Map<String, dynamic>>? _messagesSub;
  Timer? _renewTimer;
  Timer? _roomStateTimer;
  Timer? _roomReconnectTimeoutTimer;

  Future<void> initialize({
    required String targetChannelId,
    required String userId,
  }) async {
    state = PttState.connecting;
    error = null;
    notifyListeners();

    try {
      final joined = await channelRepository.joinChannel(targetChannelId);
      final session = await mediaSessionService.connect(
        bootstrap: joined,
        userId: userId,
      );

      bootstrap = session.bootstrap;
      channelId = joined.channelId;
      activeSpeaker = joined.activeSpeaker;
      localAudioReady = session.localAudioReady;
      localAudioPermissionDenied = session.localAudioPermissionDenied;
      micEnabled = session.micEnabled;
      roomConnected = session.roomConnected;
      channelBusy = activeSpeaker != null && activeSpeaker!.isNotEmpty;

      _messagesSub?.cancel();
      _messagesSub = session.messages.listen(_onMessage);
      _startRoomStateTimer();

      state = PttState.listening;
      notifyListeners();
    } catch (_) {
      error = 'Kanal oturumu baslatilamadi.';
      state = PttState.disconnected;
      notifyListeners();
    }
  }

  Future<void> requestTalk() async {
    if (channelId == null || state == PttState.requestingTalk || state == PttState.speaking) {
      return;
    }

    state = PttState.requestingTalk;
    notifyListeners();

    mediaSessionService.send(<String, dynamic>{
      'type': 'speaker.request',
      'channelId': channelId,
    });
  }

  Future<void> retryLocalAudioSetup() async {
    final result = await mediaSessionService.prepareLocalAudio();
    localAudioReady = result.ready;
    localAudioPermissionDenied = result.permissionDenied;
    notifyListeners();
  }

  Future<void> releaseTalk() async {
    if (channelId == null) {
      return;
    }

    await mediaSessionService.disableMic();
    micEnabled = false;
    _stopRenewTimer();
    mediaSessionService.send(<String, dynamic>{
      'type': 'speaker.release',
      'channelId': channelId,
    });
    state = PttState.listening;
    notifyListeners();
  }

  Future<void> _onMessage(Map<String, dynamic> message) async {
    final type = message['type'] as String? ?? '';

    if (type == 'speaker.granted') {
      await mediaSessionService.enableMic();
      micEnabled = true;
      roomConnected = mediaSessionService.roomConnected;
      activeSpeaker = message['userId'] as String?;
      channelBusy = false;
      state = PttState.speaking;
      _startRenewTimer();
      notifyListeners();
      return;
    }

    if (type == 'speaker.denied') {
      await mediaSessionService.disableMic();
      micEnabled = false;
      roomConnected = mediaSessionService.roomConnected;
      _stopRenewTimer();
      activeSpeaker = message['owner'] as String?;
      channelBusy = true;
      state = PttState.listening;
      notifyListeners();
      return;
    }

    if (type == 'speaker.changed') {
      await mediaSessionService.disableMic();
      micEnabled = false;
      roomConnected = mediaSessionService.roomConnected;
      _stopRenewTimer();
      activeSpeaker = message['userId'] as String?;
      channelBusy = activeSpeaker != null && activeSpeaker!.isNotEmpty;
      if (state != PttState.requestingTalk) {
        state = PttState.listening;
      }
      notifyListeners();
      return;
    }

    if (type == 'speaker.renewed') {
      final ok = message['ok'] as bool? ?? false;
      if (!ok && state == PttState.speaking) {
        await mediaSessionService.disableMic();
        micEnabled = false;
        roomConnected = mediaSessionService.roomConnected;
        _stopRenewTimer();
        state = PttState.listening;
        channelBusy = false;
        notifyListeners();
      }
    }
  }

  void _startRenewTimer() {
    _renewTimer?.cancel();
    _renewTimer = Timer.periodic(speakerRenewInterval, (_) {
      if (channelId == null || state != PttState.speaking) {
        return;
      }
      mediaSessionService.send(<String, dynamic>{
        'type': 'speaker.renew',
        'channelId': channelId,
      });
    });
  }

  void _stopRenewTimer() {
    _renewTimer?.cancel();
    _renewTimer = null;
  }

  void _startRoomStateTimer() {
    _roomStateTimer?.cancel();
    _roomStateTimer = Timer.periodic(roomStatePollInterval, (_) {
      final connected = mediaSessionService.roomConnected;
      if (connected == roomConnected) {
        return;
      }

      roomConnected = connected;
      if (!connected && state != PttState.disconnected) {
        reconnectAttempts += 1;
        state = PttState.reconnecting;
        _startRoomReconnectTimeout();
      } else if (connected && state == PttState.reconnecting) {
        state = micEnabled ? PttState.speaking : PttState.listening;
        _cancelRoomReconnectTimeout();
      }
      notifyListeners();
    });
  }

  void _startRoomReconnectTimeout() {
    _roomReconnectTimeoutTimer?.cancel();
    _roomReconnectTimeoutTimer = Timer(roomReconnectTimeout, () {
      if (roomConnected || state != PttState.reconnecting) {
        return;
      }
      error = 'Canli ses baglantisi gecikiyor. Ag baglantinizi kontrol edin.';
      notifyListeners();
    });
  }

  void _cancelRoomReconnectTimeout() {
    _roomReconnectTimeoutTimer?.cancel();
    _roomReconnectTimeoutTimer = null;
    if (state != PttState.reconnecting) {
      error = null;
    }
  }

  void _stopRoomStateTimer() {
    _roomStateTimer?.cancel();
    _roomStateTimer = null;
    _cancelRoomReconnectTimeout();
  }

  @override
  Future<void> dispose() async {
    _stopRenewTimer();
    _stopRoomStateTimer();
    await _messagesSub?.cancel();
    await mediaSessionService.dispose();
    super.dispose();
  }
}
