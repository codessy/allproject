import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/networking/api_error_message.dart';
import '../../../core/deeplink/invite_link_parser.dart';
import '../../ptt/presentation/channel_room_screen.dart';

class InviteAcceptScreen extends StatefulWidget {
  const InviteAcceptScreen({
    super.key,
    this.initialInviteToken,
    this.acceptInvite,
  });

  final String? initialInviteToken;
  final Future<String> Function(String inviteToken)? acceptInvite;

  Future<String> Function(String inviteToken) get resolvedAcceptInvite =>
      acceptInvite ?? AppScope.channelRepository.acceptInvite;

  @override
  State<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends State<InviteAcceptScreen> {
  late final TextEditingController controller;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialInviteToken ?? '');
  }

  Future<void> _acceptInvite() async {
    final parsedToken = InviteLinkParser.extractInviteToken(controller.text);
    if (parsedToken == null || parsedToken.isEmpty) {
      setState(() => error = 'Gecerli bir davet baglantisi veya token girin.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final channelId = await widget.resolvedAcceptInvite(parsedToken);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChannelRoomScreen(
            channelId: channelId,
            channelName: 'Invite Channel',
          ),
        ),
      );
    } catch (e) {
      final apiMsg = apiErrorMessageFrom(e);
      setState(() {
        error = apiMsg.isNotEmpty ? apiMsg : 'Davet kabul edilemedi.';
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Davet Kabul')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Davet tokeni veya baglantisi girin'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              onChanged: (_) {
                if (error != null) {
                  setState(() => error = null);
                }
              },
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'walkietalkie://invite/<token> veya token',
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: loading ? null : _acceptInvite,
              child: Text(loading ? 'Bekleyin...' : 'Daveti Kabul Et'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
