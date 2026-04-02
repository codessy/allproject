import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/features/channels/data/channel_repository.dart';
import 'package:walkietalkie_mobile/src/features/channels/presentation/channel_admin_screen.dart';

void main() {
  group('ChannelAdminScreen helpers', () {
    test('maps audit action labels', () {
      expect(channelAdminActionLabel('invite.created'), 'Davet olusturuldu');
      expect(channelAdminActionLabel('channel.member.removed'), 'Uye kanaldan cikarildi');
      expect(channelAdminActionLabel('unknown.action'), 'unknown.action');
    });

    test('maps metadata labels', () {
      expect(channelAdminMetadataLabel('channelId'), 'Kanal');
      expect(channelAdminMetadataLabel('targetUserId'), 'Hedef kullanici');
      expect(channelAdminMetadataLabel('customKey'), 'customKey');
    });

    test('maps role labels', () {
      expect(channelAdminRoleLabel('owner'), 'owner');
      expect(channelAdminRoleLabel('admin'), 'admin');
      expect(channelAdminRoleLabel('member'), 'member');
      expect(channelAdminRoleLabel('guest'), 'guest');
    });

    test('formats nullable datetime safely', () {
      expect(channelAdminFormatDateTime(null), '-');
      expect(
        channelAdminFormatDateTime(DateTime.utc(2026, 4, 1, 9, 5)),
        contains('2026-'),
      );
    });

    test('extracts dio error message from response payload', () {
      final requestOptions = RequestOptions(path: '/v1/channels/channel-1');
      final error = DioException(
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 400,
          data: <String, dynamic>{'error': 'invalid role'},
        ),
      );

      expect(channelAdminDioMessage(error), 'invalid role');
    });

    test('falls back when dio error payload has no message', () {
      final requestOptions = RequestOptions(path: '/v1/channels/channel-1');
      final error = DioException(
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 500,
          data: <String, dynamic>{},
        ),
      );

      expect(channelAdminDioMessage(error), 'Islem tamamlanamadi.');
    });
  });

  group('ChannelAdminScreen widget', () {
    testWidgets('shows load error message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'admin',
            ),
            listMembers: (_) async => throw Exception('load failed'),
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Yonetim verileri yuklenemedi.'), findsOneWidget);
    });

    testWidgets('owner sees editable settings and loaded sections', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'owner',
            ),
            listMembers: (_) async => <ChannelMember>[
              ChannelMember(
                channelId: 'channel-1',
                userId: 'user-2',
                role: 'member',
                joinedAt: DateTime.utc(2026, 4, 1, 9, 0),
              ),
            ],
            listInvites: (_) async => <ChannelInvite>[
              ChannelInvite(
                id: 'invite-1',
                channelId: 'channel-1',
                createdBy: 'owner-1',
                maxUses: 5,
                usedCount: 1,
                expiresAt: DateTime.utc(2026, 4, 2, 9, 0),
                createdAt: DateTime.utc(2026, 4, 1, 9, 0),
                revokedBy: null,
                revokedAt: null,
              ),
            ],
            listAuditEvents: (_) async => <ChannelAuditEvent>[
              ChannelAuditEvent(
                id: 'evt-1',
                actorUserId: 'owner-1',
                action: 'invite.created',
                resourceType: 'channel_invite',
                resourceId: 'invite-1',
                metadata: <String, dynamic>{'channelId': 'channel-1'},
                createdAt: DateTime.utc(2026, 4, 1, 9, 0),
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Audit Eventleri'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Alpha Yonetimi'), findsOneWidget);
      expect(find.text('Uyeler'), findsOneWidget);
      expect(find.text('Davetler'), findsOneWidget);
      expect(find.text('Audit Eventleri'), findsOneWidget);
      expect(find.text('user-2'), findsOneWidget);
      expect(find.text('invite-1'), findsOneWidget);
      expect(find.text('Davet olusturuldu'), findsOneWidget);
      expect(find.text('Kanali Guncelle'), findsOneWidget);
      expect(find.text('Davet Olustur'), findsOneWidget);
    });

    testWidgets('admin cannot change channel type but can still save and create invite', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'admin',
            ),
            listMembers: (_) async => <ChannelMember>[],
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
          ),
        ),
      );

      await tester.pumpAndSettle();

      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(dropdown.onChanged, isNull);
      expect(find.text('Kanali Guncelle'), findsOneWidget);
      expect(find.text('Davet Olustur'), findsOneWidget);
    });

    testWidgets('save channel uses injected update callback and shows success', (
      tester,
    ) async {
      String? savedName;
      String? savedType;

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'owner',
            ),
            listMembers: (_) async => <ChannelMember>[],
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            updateChannel: (channelId, {name, type}) async {
              savedName = name;
              savedType = type;
              return ChannelSummary(
                id: channelId,
                name: name ?? 'Alpha',
                type: type ?? 'private',
                ownerUserId: 'owner-1',
                role: 'owner',
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Bravo');
      await tester.tap(find.text('Kanali Guncelle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(savedName, 'Bravo');
      expect(savedType, 'private');
      expect(find.text('Kanal ayarlari guncellendi.'), findsOneWidget);
    });

    testWidgets('save channel shows fallback error on failure', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'owner',
            ),
            listMembers: (_) async => <ChannelMember>[],
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            updateChannel: (channelId, {name, type}) async {
              throw Exception('save failed');
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Kanali Guncelle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Kanal guncellenemedi.'), findsOneWidget);
    });

    testWidgets('create invite uses injected callback and shows token dialog', (
      tester,
    ) async {
      var createInviteCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'owner',
            ),
            listMembers: (_) async => <ChannelMember>[],
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            createInvite: (channelId) async {
              createInviteCalls += 1;
              return CreateInviteResult(
                invite: ChannelInvite(
                  id: 'invite-1',
                  channelId: channelId,
                  createdBy: 'owner-1',
                  maxUses: 10,
                  usedCount: 0,
                  expiresAt: null,
                  createdAt: null,
                  revokedBy: null,
                  revokedAt: null,
                ),
                inviteToken: 'invite-token-123',
                pushQueued: false,
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Davet Olustur'));
      await tester.pumpAndSettle();

      expect(createInviteCalls, 1);
      expect(find.text('Davet Olusturuldu'), findsOneWidget);
      expect(find.text('invite-token-123'), findsOneWidget);
    });

    testWidgets('create invite shows fallback error on failure', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'owner',
            ),
            listMembers: (_) async => <ChannelMember>[],
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            createInvite: (_) async {
              throw Exception('create invite failed');
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Davet Olustur'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Davet olusturulamadi.'), findsOneWidget);
    });

    testWidgets('owner can promote member to admin through injected callback', (
      tester,
    ) async {
      String? updatedUserId;
      String? updatedRole;

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'owner',
            ),
            listMembers: (_) async => <ChannelMember>[
              ChannelMember(
                channelId: 'channel-1',
                userId: 'user-2',
                role: 'member',
                joinedAt: null,
              ),
            ],
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            updateMemberRole: (channelId, userId, role) async {
              updatedUserId = userId;
              updatedRole = role;
              return ChannelMember(
                channelId: channelId,
                userId: userId,
                role: role,
                joinedAt: null,
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('admin yap').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guncelle'));
      await tester.pumpAndSettle();

      expect(updatedUserId, 'user-2');
      expect(updatedRole, 'admin');
    });

    testWidgets('admin can remove member through injected callback', (tester) async {
      String? removedUserId;

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'admin',
            ),
            listMembers: (_) async => <ChannelMember>[
              ChannelMember(
                channelId: 'channel-1',
                userId: 'user-2',
                role: 'member',
                joinedAt: null,
              ),
            ],
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            removeMember: (channelId, userId) async {
              removedUserId = userId;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('kanaldan cikar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cikar'));
      await tester.pumpAndSettle();

      expect(removedUserId, 'user-2');
    });

    testWidgets('admin can revoke invite through injected callback', (tester) async {
      String? revokedInviteId;

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'admin',
            ),
            listMembers: (_) async => <ChannelMember>[],
            listInvites: (_) async => <ChannelInvite>[
              ChannelInvite(
                id: 'invite-99',
                channelId: 'channel-1',
                createdBy: 'owner-1',
                maxUses: 5,
                usedCount: 0,
                expiresAt: null,
                createdAt: DateTime.utc(2026, 4, 1),
                revokedBy: null,
                revokedAt: null,
              ),
            ],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            revokeInvite: (channelId, inviteId) async {
              revokedInviteId = inviteId;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.cancel_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iptal Et'));
      await tester.pumpAndSettle();

      expect(revokedInviteId, 'invite-99');
    });

    testWidgets('revoke invite shows fallback error on failure', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'admin',
            ),
            listMembers: (_) async => <ChannelMember>[],
            listInvites: (_) async => <ChannelInvite>[
              ChannelInvite(
                id: 'invite-99',
                channelId: 'channel-1',
                createdBy: 'owner-1',
                maxUses: 5,
                usedCount: 0,
                expiresAt: null,
                createdAt: DateTime.utc(2026, 4, 1),
                revokedBy: null,
                revokedAt: null,
              ),
            ],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            revokeInvite: (channelId, inviteId) async {
              throw Exception('revoke failed');
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.cancel_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iptal Et'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Davet iptal edilemedi.'), findsOneWidget);
    });

    testWidgets('cancel role change does not call update callback', (tester) async {
      var updateCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'owner',
            ),
            listMembers: (_) async => <ChannelMember>[
              ChannelMember(
                channelId: 'channel-1',
                userId: 'user-2',
                role: 'member',
                joinedAt: null,
              ),
            ],
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            updateMemberRole: (channelId, userId, role) async {
              updateCalls += 1;
              return ChannelMember(
                channelId: channelId,
                userId: userId,
                role: role,
                joinedAt: null,
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('admin yap').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgec'));
      await tester.pumpAndSettle();

      expect(updateCalls, 0);
    });

    testWidgets('cancel member removal does not call remove callback', (tester) async {
      var removeCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'admin',
            ),
            listMembers: (_) async => <ChannelMember>[
              ChannelMember(
                channelId: 'channel-1',
                userId: 'user-2',
                role: 'member',
                joinedAt: null,
              ),
            ],
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            removeMember: (channelId, userId) async {
              removeCalls += 1;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('kanaldan cikar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgec'));
      await tester.pumpAndSettle();

      expect(removeCalls, 0);
    });

    testWidgets('cancel invite revoke does not call revoke callback', (tester) async {
      var revokeCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'admin',
            ),
            listMembers: (_) async => <ChannelMember>[],
            listInvites: (_) async => <ChannelInvite>[
              ChannelInvite(
                id: 'invite-99',
                channelId: 'channel-1',
                createdBy: 'owner-1',
                maxUses: 5,
                usedCount: 0,
                expiresAt: null,
                createdAt: DateTime.utc(2026, 4, 1),
                revokedBy: null,
                revokedAt: null,
              ),
            ],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            revokeInvite: (channelId, inviteId) async {
              revokeCalls += 1;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.cancel_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgec'));
      await tester.pumpAndSettle();

      expect(revokeCalls, 0);
    });

    testWidgets('owner transfer uses dedicated confirm action label', (tester) async {
      var updatedRole = '';

      await tester.pumpWidget(
        MaterialApp(
          home: ChannelAdminScreen(
            channel: ChannelSummary(
              id: 'channel-1',
              name: 'Alpha',
              type: 'private',
              ownerUserId: 'owner-1',
              role: 'owner',
            ),
            listMembers: (_) async => <ChannelMember>[
              ChannelMember(
                channelId: 'channel-1',
                userId: 'user-2',
                role: 'admin',
                joinedAt: null,
              ),
            ],
            listInvites: (_) async => <ChannelInvite>[],
            listAuditEvents: (_) async => <ChannelAuditEvent>[],
            updateMemberRole: (channelId, userId, role) async {
              updatedRole = role;
              return ChannelMember(
                channelId: channelId,
                userId: userId,
                role: role,
                joinedAt: null,
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('owner yap').last);
      await tester.pumpAndSettle();

      expect(find.text('Owner Devri'), findsOneWidget);
      expect(find.text('Devret'), findsOneWidget);

      await tester.tap(find.text('Devret'));
      await tester.pumpAndSettle();

      expect(updatedRole, 'owner');
    });
  });
}
