import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../auth/presentation/login_screen.dart';
import '../data/channel_repository.dart';
import 'channel_admin_screen.dart';
import 'invite_accept_screen.dart';
import '../../ptt/presentation/channel_room_screen.dart';

class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({
    super.key,
    required this.currentUserName,
    this.listChannels,
    this.logout,
  });

  final String currentUserName;
  final Future<List<ChannelSummary>> Function()? listChannels;
  final Future<void> Function()? logout;

  Future<List<ChannelSummary>> Function() get resolvedListChannels =>
      listChannels ?? AppScope.channelRepository.listChannels;

  Future<void> Function() get resolvedLogout => logout ?? AppScope.authRepository.logout;

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  late Future<List<ChannelSummary>> _channelsFuture;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _channelsFuture = widget.resolvedListChannels();
  }

  Future<void> _reloadChannels() async {
    setState(() {
      _channelsFuture = widget.resolvedListChannels();
    });
    await _channelsFuture;
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await widget.resolvedLogout();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cikis yapilamadi.')));
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text('Kanallar - ${widget.currentUserName}'),
        actions: [
          IconButton(
            tooltip: 'Cikis Yap',
            icon: _loggingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            onPressed: _loggingOut ? null : _logout,
          ),
          IconButton(
            tooltip: 'Davet Kabul Et',
            icon: const Icon(Icons.link),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const InviteAcceptScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<ChannelSummary>>(
        future: _channelsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text('Kanallar yuklenemedi. Backend ve DB durumunu kontrol edin.'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() {
                      _channelsFuture = widget.resolvedListChannels();
                    }),
                    child: const Text('Tekrar dene'),
                  ),
                ],
              ),
            );
          }

          final channels = snapshot.data ?? <ChannelSummary>[];
          return RefreshIndicator(
            onRefresh: _reloadChannels,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: channels.isEmpty ? 1 : channels.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (channels.isEmpty) {
                  return const ListTile(
                    title: Text('Henuz kanal bulunmuyor.'),
                    subtitle: Text('Yenilemek icin asagi cekin.'),
                  );
                }
                final channel = channels[index];
                final canManage = channel.role == 'owner' || channel.role == 'admin';
                return ListTile(
                  title: Text(channel.name),
                  subtitle: Text('${channel.type} · rol: ${channel.role.isEmpty ? '-' : channel.role}'),
                  trailing: canManage
                      ? IconButton(
                          tooltip: 'Kanali Yonet',
                          icon: const Icon(Icons.settings),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChannelAdminScreen(channel: channel),
                              ),
                            );
                          },
                        )
                      : null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChannelRoomScreen(
                          channelId: channel.id,
                          channelName: channel.name,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
