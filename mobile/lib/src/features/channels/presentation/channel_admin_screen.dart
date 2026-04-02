import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_scope.dart';
import '../../../core/networking/api_error_message.dart';
import '../data/channel_repository.dart';

String channelAdminActionLabel(String action) {
  switch (action) {
    case 'invite.created':
      return 'Davet olusturuldu';
    case 'invite.revoked':
      return 'Davet iptal edildi';
    case 'invite.accepted':
      return 'Davet kabul edildi';
    case 'channel.updated':
      return 'Kanal ayarlari guncellendi';
    case 'channel.member.upserted':
      return 'Uye rolu guncellendi';
    case 'channel.member.removed':
      return 'Uye kanaldan cikarildi';
    default:
      return action;
  }
}

String channelAdminMetadataLabel(String key) {
  switch (key) {
    case 'channelId':
      return 'Kanal';
    case 'userId':
      return 'Uye';
    case 'targetUserId':
      return 'Hedef kullanici';
    case 'role':
      return 'Rol';
    case 'name':
      return 'Ad';
    case 'type':
      return 'Tip';
    case 'maxUses':
      return 'Kullanim limiti';
    default:
      return key;
  }
}

String channelAdminRoleLabel(String role) {
  switch (role) {
    case 'owner':
      return 'owner';
    case 'admin':
      return 'admin';
    case 'member':
      return 'member';
    default:
      return role;
  }
}

String channelAdminFormatDateTime(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

String channelAdminDioMessage(DioException error) {
  final msg = apiErrorMessageFrom(error);
  if (msg.isNotEmpty) {
    return msg;
  }
  return 'Islem tamamlanamadi.';
}

class ChannelAdminScreen extends StatefulWidget {
  const ChannelAdminScreen({
    super.key,
    required this.channel,
    this.listMembers,
    this.listInvites,
    this.listAuditEvents,
    this.updateChannel,
    this.createInvite,
    this.updateMemberRole,
    this.removeMember,
    this.revokeInvite,
  });

  final ChannelSummary channel;
  final Future<List<ChannelMember>> Function(String channelId)? listMembers;
  final Future<List<ChannelInvite>> Function(String channelId)? listInvites;
  final Future<List<ChannelAuditEvent>> Function(String channelId)? listAuditEvents;
  final Future<ChannelSummary> Function(
    String channelId, {
    String? name,
    String? type,
  })? updateChannel;
  final Future<CreateInviteResult> Function(String channelId)? createInvite;
  final Future<ChannelMember> Function(
    String channelId,
    String userId,
    String role,
  )? updateMemberRole;
  final Future<void> Function(String channelId, String userId)? removeMember;
  final Future<void> Function(String channelId, String inviteId)? revokeInvite;

  Future<List<ChannelMember>> Function(String channelId) get resolvedListMembers =>
      listMembers ?? AppScope.channelRepository.listMembers;

  Future<List<ChannelInvite>> Function(String channelId) get resolvedListInvites =>
      listInvites ?? AppScope.channelRepository.listInvites;

  Future<List<ChannelAuditEvent>> Function(String channelId) get resolvedListAuditEvents =>
      listAuditEvents ?? AppScope.channelRepository.listAuditEvents;

  Future<ChannelSummary> Function(
    String channelId, {
    String? name,
    String? type,
  }) get resolvedUpdateChannel => updateChannel ?? AppScope.channelRepository.updateChannel;

  Future<CreateInviteResult> Function(String channelId) get resolvedCreateInvite =>
      createInvite ?? AppScope.channelRepository.createInvite;

  Future<ChannelMember> Function(
    String channelId,
    String userId,
    String role,
  ) get resolvedUpdateMemberRole =>
      updateMemberRole ?? AppScope.channelRepository.updateMemberRole;

  Future<void> Function(String channelId, String userId) get resolvedRemoveMember =>
      removeMember ?? AppScope.channelRepository.removeMember;

  Future<void> Function(String channelId, String inviteId) get resolvedRevokeInvite =>
      revokeInvite ?? AppScope.channelRepository.revokeInvite;

  @override
  State<ChannelAdminScreen> createState() => _ChannelAdminScreenState();
}

class _ChannelAdminScreenState extends State<ChannelAdminScreen> {
  late final TextEditingController _nameController;
  late String _selectedType;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<ChannelMember> _members = <ChannelMember>[];
  List<ChannelInvite> _invites = <ChannelInvite>[];
  List<ChannelAuditEvent> _events = <ChannelAuditEvent>[];

  bool get _isOwner => widget.channel.role == 'owner';
  bool get _isAdmin => _isOwner || widget.channel.role == 'admin';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.channel.name);
    _selectedType = widget.channel.type;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.resolvedListMembers(widget.channel.id),
        widget.resolvedListInvites(widget.channel.id),
        widget.resolvedListAuditEvents(widget.channel.id),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _members = results[0] as List<ChannelMember>;
        _invites = results[1] as List<ChannelInvite>;
        _events = results[2] as List<ChannelAuditEvent>;
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = channelAdminDioMessage(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Yonetim verileri yuklenemedi.';
      });
    }
  }

  Future<void> _saveChannel() async {
    setState(() => _saving = true);
    try {
      final updated = await widget.resolvedUpdateChannel(
        widget.channel.id,
        name: _nameController.text.trim(),
        type: _selectedType,
      );
      if (!mounted) {
        return;
      }
      _nameController.text = updated.name;
      _selectedType = updated.type;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kanal ayarlari guncellendi.')),
      );
      setState(() {});
    } on DioException catch (error) {
      _showError(channelAdminDioMessage(error));
    } catch (_) {
      _showError('Kanal guncellenemedi.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _changeRole(ChannelMember member, String role) async {
    final confirmed = await _confirmAction(
      title: role == 'owner' ? 'Owner Devri' : 'Rol Guncelle',
      message: role == 'owner'
          ? '${member.userId} kullanicisi primary owner olacak. Mevcut owner admin seviyesine indirilecek.'
          : '${member.userId} kullanicisinin rolu "$role" olarak guncellenecek.',
      confirmLabel: role == 'owner' ? 'Devret' : 'Guncelle',
    );
    if (!confirmed) {
      return;
    }

    try {
      await widget.resolvedUpdateMemberRole(
        widget.channel.id,
        member.userId,
        role,
      );
      await _load();
    } on DioException catch (error) {
      _showError(channelAdminDioMessage(error));
    } catch (_) {
      _showError('Rol guncellenemedi.');
    }
  }

  Future<void> _removeMember(ChannelMember member) async {
    final confirmed = await _confirmAction(
      title: 'Uyeyi Cikar',
      message:
          '${member.userId} kullanicisi kanaldan cikarilacak. Bu islem geri alinmaz.',
      confirmLabel: 'Cikar',
    );
    if (!confirmed) {
      return;
    }

    try {
      await widget.resolvedRemoveMember(widget.channel.id, member.userId);
      await _load();
    } on DioException catch (error) {
      _showError(channelAdminDioMessage(error));
    } catch (_) {
      _showError('Uye kaldirilamadi.');
    }
  }

  Future<void> _createInvite() async {
    try {
      final result = await widget.resolvedCreateInvite(widget.channel.id);
      await _load();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Davet Olusturuldu'),
            content: SelectableText(result.inviteToken),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: result.inviteToken),
                  );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    _showError('Davet tokeni panoya kopyalandi.');
                  }
                },
                child: const Text('Kopyala'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tamam'),
              ),
            ],
          );
        },
      );
    } on DioException catch (error) {
      _showError(channelAdminDioMessage(error));
    } catch (_) {
      _showError('Davet olusturulamadi.');
    }
  }

  Future<void> _revokeInvite(ChannelInvite invite) async {
    final confirmed = await _confirmAction(
      title: 'Daveti Iptal Et',
      message: '${invite.id} daveti iptal edilecek.',
      confirmLabel: 'Iptal Et',
    );
    if (!confirmed) {
      return;
    }

    try {
      await widget.resolvedRevokeInvite(widget.channel.id, invite.id);
      await _load();
    } on DioException catch (error) {
      _showError(channelAdminDioMessage(error));
    } catch (_) {
      _showError('Davet iptal edilemedi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.channel.name} Yonetimi'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _nameController,
                      enabled: _isAdmin,
                      decoration: const InputDecoration(
                        labelText: 'Kanal adi',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedType,
                      items: const [
                        DropdownMenuItem(value: 'private', child: Text('private')),
                        DropdownMenuItem(value: 'public', child: Text('public')),
                      ],
                      onChanged: !_isOwner
                          ? null
                          : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _selectedType = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Kanal tipi',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: !_isAdmin || _saving ? null : _saveChannel,
                      child: Text(_saving ? 'Kaydediliyor...' : 'Kanali Guncelle'),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('Uyeler', style: Theme.of(context).textTheme.titleLarge),
                        const Spacer(),
                        Text('${_members.length} kayit'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._members.map(_buildMemberTile),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('Davetler', style: Theme.of(context).textTheme.titleLarge),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: _isAdmin ? _createInvite : null,
                          child: const Text('Davet Olustur'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._invites.map(_buildInviteTile),
                    const SizedBox(height: 24),
                    Text(
                      'Audit Eventleri',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    ..._events.map(_buildEventTile),
                  ],
                ),
    );
  }

  Widget _buildMemberTile(ChannelMember member) {
    final menuItems = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'member', child: Text('member yap')),
      if (_isOwner) const PopupMenuItem(value: 'admin', child: Text('admin yap')),
      if (_isOwner) const PopupMenuItem(value: 'owner', child: Text('owner yap')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'remove', child: Text('kanaldan cikar')),
    ];

    return Card(
      child: ListTile(
        title: Text(member.userId),
        subtitle: Text(
          'Rol: ${channelAdminRoleLabel(member.role)}'
          '${member.joinedAt != null ? '\nKatilma: ${channelAdminFormatDateTime(member.joinedAt)}' : ''}',
        ),
        isThreeLine: member.joinedAt != null,
        trailing: !_isAdmin
            ? null
            : PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'remove') {
              _removeMember(member);
              return;
            }
            _changeRole(member, value);
          },
          itemBuilder: (context) => menuItems,
        ),
      ),
    );
  }

  Widget _buildInviteTile(ChannelInvite invite) {
    final status = invite.revokedAt != null
        ? 'Iptal edildi'
        : '${invite.usedCount}/${invite.maxUses} kullanildi';
    return Card(
      child: ListTile(
        title: Text(invite.id),
        subtitle: Text(
          [
            status,
            if (invite.expiresAt != null) 'Son: ${channelAdminFormatDateTime(invite.expiresAt)}',
          ].join('\n'),
        ),
        isThreeLine: invite.expiresAt != null,
        trailing: invite.revokedAt != null
            ? const Icon(Icons.block)
            : IconButton(
                tooltip: 'Iptal et',
                onPressed: _isAdmin ? () => _revokeInvite(invite) : null,
                icon: const Icon(Icons.cancel_outlined),
              ),
      ),
    );
  }

  Widget _buildEventTile(ChannelAuditEvent event) {
    final detail = event.metadata.entries
        .map((entry) => '${channelAdminMetadataLabel(entry.key)}: ${entry.value}')
        .join(' | ');
    return Card(
      child: ListTile(
        title: Text(channelAdminActionLabel(event.action)),
        subtitle: Text(
          [
            if (event.actorUserId.isNotEmpty) 'Kullanici: ${event.actorUserId}',
            if (detail.isNotEmpty) detail,
          ].join('\n'),
        ),
        isThreeLine: detail.isNotEmpty,
        trailing: Text(
          channelAdminFormatDateTime(event.createdAt),
          textAlign: TextAlign.end,
        ),
      ),
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgec'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
