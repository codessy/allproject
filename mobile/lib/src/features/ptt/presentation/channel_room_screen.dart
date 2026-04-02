import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../domain/ptt_state.dart';
import '../data/media_session_service.dart';
import 'ptt_controller.dart';
import '../widgets/ptt_button.dart';

class ChannelRoomScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  final PttController? controller;
  /// When null, uses [AppScope.authRepository] session user id, then `demo-user`.
  final String? userId;

  const ChannelRoomScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    this.controller,
    this.userId,
  });

  @override
  State<ChannelRoomScreen> createState() => _ChannelRoomScreenState();
}

class _ChannelRoomScreenState extends State<ChannelRoomScreen> {
  late final PttController controller;
  bool _ownsController = false;
  late final String _resolvedUserId;

  @override
  void initState() {
    super.initState();
    _resolvedUserId = widget.userId ??
        AppScope.authRepository.currentSession?.userId ??
        'demo-user';
    if (widget.controller != null) {
      controller = widget.controller!;
    } else {
      _ownsController = true;
      controller = PttController(
        channelRepository: AppScope.channelRepository,
        mediaSessionService: MediaSessionService(AppScope.wsClient),
      );
    }
    controller.addListener(_refresh);

    controller.initialize(
      targetChannelId: widget.channelId,
      userId: _resolvedUserId,
    );
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.channelName)),
      body: Center(
        child: controller.state == PttState.connecting
            ? const CircularProgressIndicator()
            : controller.error != null
                ? Text(controller.error!)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _statusLabel(controller.state),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('LiveKit: ${controller.bootstrap?.liveKitUrl ?? '-'}'),
                      const SizedBox(height: 8),
                      Text(
                        controller.localAudioReady
                            ? 'Mikrofon hazir'
                            : controller.localAudioPermissionDenied
                                ? 'Mikrofon izni gerekli'
                                : 'Mikrofon hazirlaniyor',
                      ),
                      if (controller.localAudioPermissionDenied) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Ses gondermek icin mikrofon izni verin ve tekrar deneyin.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: controller.retryLocalAudioSetup,
                          child: const Text('Mikrofonu Tekrar Dene'),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        controller.roomConnected
                            ? 'LiveKit oda baglantisi hazir'
                            : 'LiveKit oda baglantisi bekleniyor',
                      ),
                      if (controller.state == PttState.reconnecting)
                        Text('Yeniden baglanma denemesi: ${controller.reconnectAttempts}'),
                      if (controller.error != null && controller.state != PttState.disconnected)
                        Text(
                          controller.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.orange),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        controller.micEnabled ? 'Mikrofon acik' : 'Mikrofon kapali',
                      ),
                      const SizedBox(height: 24),
                      PttButton(
                        channelBusy: controller.channelBusy,
                        onPressedDown: () {
                          controller.requestTalk();
                        },
                        onPressedUp: () {
                          controller.releaseTalk();
                        },
                      ),
                    ],
                  ),
      ),
    );
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    if (_ownsController) {
      controller.dispose();
    }
    super.dispose();
  }

  String _statusLabel(PttState state) {
    switch (state) {
      case PttState.connecting:
        return 'Kanala baglaniliyor';
      case PttState.listening:
        return 'Dinleme modundasiniz';
      case PttState.requestingTalk:
        return 'Konusma izni bekleniyor';
      case PttState.speaking:
        return 'Konusuyorsunuz';
      case PttState.reconnecting:
        return 'Yeniden baglaniliyor';
      case PttState.disconnected:
        return 'Baglanti yok';
    }
  }
}
