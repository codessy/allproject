import '../../../core/networking/api_base_url.dart';
import '../../../core/networking/api_client.dart';

abstract class ChannelSessionRepository {
  Future<JoinChannelBootstrap> joinChannel(String channelId);
}

class ChannelSummary {
  ChannelSummary({
    required this.id,
    required this.name,
    required this.type,
    required this.ownerUserId,
    required this.role,
  });

  final String id;
  final String name;
  final String type;
  final String ownerUserId;
  final String role;
}

class ChannelMember {
  ChannelMember({
    required this.channelId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  final String channelId;
  final String userId;
  final String role;
  final DateTime? joinedAt;
}

class ChannelInvite {
  ChannelInvite({
    required this.id,
    required this.channelId,
    required this.createdBy,
    required this.maxUses,
    required this.usedCount,
    required this.expiresAt,
    required this.createdAt,
    required this.revokedBy,
    required this.revokedAt,
  });

  final String id;
  final String channelId;
  final String createdBy;
  final int maxUses;
  final int usedCount;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final String? revokedBy;
  final DateTime? revokedAt;
}

class CreateInviteResult {
  CreateInviteResult({
    required this.invite,
    required this.inviteToken,
    required this.pushQueued,
  });

  final ChannelInvite invite;
  final String inviteToken;
  final bool pushQueued;
}

class ChannelAuditEvent {
  ChannelAuditEvent({
    required this.id,
    required this.actorUserId,
    required this.action,
    required this.resourceType,
    required this.resourceId,
    required this.metadata,
    required this.createdAt,
  });

  final String id;
  final String actorUserId;
  final String action;
  final String resourceType;
  final String resourceId;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
}

class JoinChannelBootstrap {
  JoinChannelBootstrap({
    required this.channelId,
    required this.liveKitUrl,
    required this.liveKitToken,
    required this.webSocketUrl,
    required this.iceServers,
    required this.activeSpeaker,
  });

  final String channelId;
  final String liveKitUrl;
  final String liveKitToken;
  final String webSocketUrl;
  final List<String> iceServers;
  final String? activeSpeaker;
}

class ChannelRepository implements ChannelSessionRepository {
  ChannelRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ChannelSummary>> listChannels() async {
    final data = await _apiClient.get('/v1/channels');
    final items = (data['channels'] as List<dynamic>? ?? <dynamic>[]);
    return items.map((item) {
      final json = item as Map<String, dynamic>;
      return ChannelSummary(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? '',
        ownerUserId: json['ownerUserId'] as String? ?? '',
        role: json['role'] as String? ?? '',
      );
    }).toList();
  }

  @override
  Future<JoinChannelBootstrap> joinChannel(String channelId) async {
    final data = await _apiClient.post('/v1/channels/$channelId/join');
    final ice = (data['iceServers'] as List<dynamic>? ?? <dynamic>[])
        .map((item) => rewriteDevLocalEndpoints(item.toString()))
        .toList();
    return JoinChannelBootstrap(
      channelId: data['channelId'] as String? ?? '',
      liveKitUrl: rewriteDevLocalEndpoints(data['livekitUrl'] as String? ?? ''),
      liveKitToken: data['livekitToken'] as String? ?? '',
      webSocketUrl: rewriteDevLocalEndpoints(data['webSocketUrl'] as String? ?? ''),
      iceServers: ice,
      activeSpeaker: data['activeSpeaker'] as String?,
    );
  }

  Future<String> acceptInvite(String inviteToken) async {
    final data = await _apiClient.post('/v1/invites/$inviteToken/accept');
    return data['channelId'] as String? ?? '';
  }

  Future<ChannelSummary> updateChannel(
    String channelId, {
    String? name,
    String? type,
  }) async {
    final data = await _apiClient.patch(
      '/v1/channels/$channelId',
      data: <String, dynamic>{
        if (name != null) 'name': name,
        if (type != null) 'type': type,
      },
    );
    return _channelFromJson(data['channel'] as Map<String, dynamic>? ?? {});
  }

  Future<List<ChannelMember>> listMembers(String channelId) async {
    final data = await _apiClient.get('/v1/channels/$channelId/members');
    final items = data['members'] as List<dynamic>? ?? <dynamic>[];
    return items.map((item) {
      final json = item as Map<String, dynamic>;
      return ChannelMember(
        channelId: json['channelId'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        role: json['role'] as String? ?? '',
        joinedAt: _parseDate(json['joinedAt']),
      );
    }).toList();
  }

  Future<ChannelMember> updateMemberRole(
    String channelId,
    String userId,
    String role,
  ) async {
    final data = await _apiClient.put(
      '/v1/channels/$channelId/members/$userId',
      data: <String, dynamic>{'role': role},
    );
    final json = data['member'] as Map<String, dynamic>? ?? {};
    return ChannelMember(
      channelId: json['channelId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      role: json['role'] as String? ?? '',
      joinedAt: _parseDate(json['joinedAt']),
    );
  }

  Future<void> removeMember(String channelId, String userId) async {
    await _apiClient.delete('/v1/channels/$channelId/members/$userId');
  }

  Future<List<ChannelInvite>> listInvites(String channelId) async {
    final data = await _apiClient.get('/v1/channels/$channelId/invites');
    final items = data['invites'] as List<dynamic>? ?? <dynamic>[];
    return items.map((item) => _inviteFromJson(item as Map<String, dynamic>)).toList();
  }

  Future<CreateInviteResult> createInvite(
    String channelId, {
    int maxUses = 10,
    int expiresInHours = 24,
  }) async {
    final data = await _apiClient.post(
      '/v1/channels/$channelId/invites',
      data: <String, dynamic>{
        'maxUses': maxUses,
        'expiresInHours': expiresInHours,
      },
    );
    return CreateInviteResult(
      invite: _inviteFromJson(data['invite'] as Map<String, dynamic>? ?? {}),
      inviteToken: data['inviteToken'] as String? ?? '',
      pushQueued: data['pushQueued'] as bool? ?? false,
    );
  }

  Future<ChannelInvite> revokeInvite(String channelId, String inviteId) async {
    final data = await _apiClient.post('/v1/channels/$channelId/invites/$inviteId/revoke');
    return _inviteFromJson(data['invite'] as Map<String, dynamic>? ?? {});
  }

  Future<List<ChannelAuditEvent>> listAuditEvents(String channelId) async {
    final data = await _apiClient.get('/v1/channels/$channelId/audit-events');
    final items = data['events'] as List<dynamic>? ?? <dynamic>[];
    return items.map((item) {
      final json = item as Map<String, dynamic>;
      return ChannelAuditEvent(
        id: json['id'] as String? ?? '',
        actorUserId: json['actorUserId'] as String? ?? '',
        action: json['action'] as String? ?? '',
        resourceType: json['resourceType'] as String? ?? '',
        resourceId: json['resourceId'] as String? ?? '',
        metadata: (json['metadata'] as Map<String, dynamic>? ?? <String, dynamic>{}),
        createdAt: _parseDate(json['createdAt']),
      );
    }).toList();
  }

  ChannelSummary _channelFromJson(Map<String, dynamic> json) {
    return ChannelSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      ownerUserId: json['ownerUserId'] as String? ?? '',
      role: json['role'] as String? ?? '',
    );
  }

  ChannelInvite _inviteFromJson(Map<String, dynamic> json) {
    return ChannelInvite(
      id: json['id'] as String? ?? '',
      channelId: json['channelId'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      maxUses: json['maxUses'] as int? ?? 0,
      usedCount: json['usedCount'] as int? ?? 0,
      expiresAt: _parseDate(json['expiresAt']),
      createdAt: _parseDate(json['createdAt']),
      revokedBy: json['revokedBy'] as String?,
      revokedAt: _parseDate(json['revokedAt']),
    );
  }

  DateTime? _parseDate(dynamic value) {
    final raw = value as String?;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
