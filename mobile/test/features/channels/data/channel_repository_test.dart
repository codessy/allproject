import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/core/networking/api_client.dart';
import 'package:walkietalkie_mobile/src/features/channels/data/channel_repository.dart';

void main() {
  group('ChannelRepository', () {
    test('listChannels maps channel summaries including role', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'channels': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'channel-1',
                'name': 'Alpha',
                'type': 'private',
                'ownerUserId': 'owner-1',
                'role': 'admin',
              },
            ],
          },
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      final channels = await repository.listChannels();

      expect(channels, hasLength(1));
      expect(channels.single.id, 'channel-1');
      expect(channels.single.name, 'Alpha');
      expect(channels.single.role, 'admin');
      expect(adapter.requests.single.path, '/v1/channels');
    });

    test('joinChannel maps bootstrap payload', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'channelId': 'channel-1',
            'livekitUrl': 'wss://livekit.example.com',
            'livekitToken': 'lk-token',
            'webSocketUrl': 'ws://localhost:8080/v1/ws',
            'iceServers': <String>['stun:one', 'turn:two'],
            'activeSpeaker': 'user-1',
          },
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      final bootstrap = await repository.joinChannel('channel-1');

      expect(bootstrap.channelId, 'channel-1');
      expect(bootstrap.liveKitUrl, 'wss://livekit.example.com');
      expect(bootstrap.webSocketUrl, 'ws://localhost:8080/v1/ws');
      expect(bootstrap.iceServers, <String>['stun:one', 'turn:two']);
      expect(bootstrap.activeSpeaker, 'user-1');
      expect(adapter.requests.single.path, '/v1/channels/channel-1/join');
      expect(adapter.requests.single.method, 'POST');
    });

    test('createInvite posts parameters and maps response', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 201,
          data: <String, dynamic>{
            'invite': <String, dynamic>{
              'id': 'invite-1',
              'channelId': 'channel-1',
              'createdBy': 'user-1',
              'maxUses': 7,
              'usedCount': 2,
              'expiresAt': '2026-04-01T10:00:00Z',
              'createdAt': '2026-03-31T10:00:00Z',
            },
            'inviteToken': 'invite-token',
            'pushQueued': true,
          },
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      final result = await repository.createInvite(
        'channel-1',
        maxUses: 7,
        expiresInHours: 48,
      );

      expect(result.invite.id, 'invite-1');
      expect(result.invite.maxUses, 7);
      expect(result.invite.usedCount, 2);
      expect(result.inviteToken, 'invite-token');
      expect(result.pushQueued, true);
      expect(
        adapter.requests.single.data,
        <String, dynamic>{'maxUses': 7, 'expiresInHours': 48},
      );
    });

    test('listAuditEvents maps metadata and timestamps', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'events': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'evt-1',
                'actorUserId': 'user-1',
                'action': 'invite.created',
                'resourceType': 'channel_invite',
                'resourceId': 'invite-1',
                'metadata': <String, dynamic>{'channelId': 'channel-1'},
                'createdAt': '2026-04-01T10:00:00Z',
              },
            ],
          },
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      final events = await repository.listAuditEvents('channel-1');

      expect(events, hasLength(1));
      expect(events.single.action, 'invite.created');
      expect(events.single.metadata['channelId'], 'channel-1');
      expect(events.single.createdAt, DateTime.parse('2026-04-01T10:00:00Z'));
    });

    test('acceptInvite posts to invite endpoint and returns channel id', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{'channelId': 'channel-42'},
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      final channelId = await repository.acceptInvite('invite-token-abc');

      expect(channelId, 'channel-42');
      expect(adapter.requests.single.path, '/v1/invites/invite-token-abc/accept');
      expect(adapter.requests.single.method, 'POST');
    });

    test('updateMemberRole sends role payload and maps returned member', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'member': <String, dynamic>{
              'channelId': 'channel-1',
              'userId': 'user-2',
              'role': 'admin',
              'joinedAt': '2026-04-01T10:00:00Z',
            },
          },
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      final member = await repository.updateMemberRole('channel-1', 'user-2', 'admin');

      expect(member.userId, 'user-2');
      expect(member.role, 'admin');
      expect(member.joinedAt, DateTime.parse('2026-04-01T10:00:00Z'));
      expect(adapter.requests.single.path, '/v1/channels/channel-1/members/user-2');
      expect(adapter.requests.single.method, 'PUT');
      expect(adapter.requests.single.data, <String, dynamic>{'role': 'admin'});
    });

    test('revokeInvite maps revoked invite timestamps', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'invite': <String, dynamic>{
              'id': 'invite-1',
              'channelId': 'channel-1',
              'createdBy': 'owner-1',
              'maxUses': 10,
              'usedCount': 2,
              'expiresAt': '2026-04-10T10:00:00Z',
              'createdAt': '2026-04-01T10:00:00Z',
              'revokedBy': 'owner-1',
              'revokedAt': '2026-04-02T10:00:00Z',
            },
          },
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      final invite = await repository.revokeInvite('channel-1', 'invite-1');

      expect(invite.id, 'invite-1');
      expect(invite.revokedBy, 'owner-1');
      expect(invite.revokedAt, DateTime.parse('2026-04-02T10:00:00Z'));
      expect(adapter.requests.single.path, '/v1/channels/channel-1/invites/invite-1/revoke');
      expect(adapter.requests.single.method, 'POST');
    });

    test('listMembers maps member rows', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'members': <Map<String, dynamic>>[
              <String, dynamic>{
                'channelId': 'channel-1',
                'userId': 'user-2',
                'role': 'member',
                'joinedAt': '2026-04-01T12:00:00Z',
              },
            ],
          },
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      final members = await repository.listMembers('channel-1');

      expect(members, hasLength(1));
      expect(members.single.userId, 'user-2');
      expect(members.single.joinedAt, DateTime.parse('2026-04-01T12:00:00Z'));
      expect(adapter.requests.single.path, '/v1/channels/channel-1/members');
    });

    test('removeMember calls delete endpoint', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{'removed': true},
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      await repository.removeMember('channel-1', 'user-2');

      expect(adapter.requests.single.path, '/v1/channels/channel-1/members/user-2');
      expect(adapter.requests.single.method, 'DELETE');
    });

    test('updateChannel patches name and type', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'channel': <String, dynamic>{
              'id': 'channel-1',
              'name': 'New Name',
              'type': 'public',
              'ownerUserId': 'owner-1',
              'role': 'owner',
            },
          },
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      final summary = await repository.updateChannel(
        'channel-1',
        name: 'New Name',
        type: 'public',
      );

      expect(summary.name, 'New Name');
      expect(summary.type, 'public');
      expect(adapter.requests.single.path, '/v1/channels/channel-1');
      expect(adapter.requests.single.method, 'PATCH');
      expect(
        adapter.requests.single.data,
        <String, dynamic>{'name': 'New Name', 'type': 'public'},
      );
    });

    test('listInvites handles invalid date values as null', () async {
      final adapter = _QueueHttpClientAdapter([
        _AdapterResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'invites': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'invite-1',
                'channelId': 'channel-1',
                'createdBy': 'owner-1',
                'maxUses': 5,
                'usedCount': 1,
                'expiresAt': 'not-a-date',
                'createdAt': '',
                'revokedBy': null,
                'revokedAt': null,
              },
            ],
          },
        ),
      ]);
      final repository = ChannelRepository(_apiClientWith(adapter));

      final invites = await repository.listInvites('channel-1');

      expect(invites, hasLength(1));
      expect(invites.single.expiresAt, isNull);
      expect(invites.single.createdAt, isNull);
    });
  });
}

ApiClient _apiClientWith(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
  dio.httpClientAdapter = adapter;
  return ApiClient(dio: dio);
}

class _QueueHttpClientAdapter implements HttpClientAdapter {
  _QueueHttpClientAdapter(this.responses);

  final List<_AdapterResponse> responses;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (responses.isEmpty) {
      throw StateError('No queued adapter response for ${options.path}');
    }

    final response = responses.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(response.data),
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _AdapterResponse {
  _AdapterResponse({required this.statusCode, required this.data});

  final int statusCode;
  final Map<String, dynamic> data;
}
