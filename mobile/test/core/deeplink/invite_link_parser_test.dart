import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/core/deeplink/invite_link_parser.dart';

void main() {
  group('InviteLinkParser', () {
    test('returns null for empty input', () {
      expect(InviteLinkParser.extractInviteToken('   '), isNull);
    });

    test('returns plain token when input is not a uri', () {
      expect(InviteLinkParser.extractInviteToken('invite-token-123'), 'invite-token-123');
    });

    test('extracts invite token from query parameter', () {
      expect(
        InviteLinkParser.extractInviteToken(
          'walkietalkie://invite/open?invite=invite-token-123',
        ),
        'invite-token-123',
      );
    });

    test('extracts token query parameter fallback', () {
      expect(
        InviteLinkParser.extractInviteToken(
          'https://example.com/invite?token=invite-token-456',
        ),
        'invite-token-456',
      );
    });

    test('extracts last path segment when query token is absent', () {
      expect(
        InviteLinkParser.extractInviteToken(
          'https://example.com/invites/invite-token-789',
        ),
        'invite-token-789',
      );
    });

    test('prefers query token over path segment', () {
      expect(
        InviteLinkParser.extractInviteToken(
          'https://example.com/invites/path-token?invite=query-token',
        ),
        'query-token',
      );
    });

    test('trims surrounding whitespace before parsing', () {
      expect(
        InviteLinkParser.extractInviteToken(
          '  walkietalkie://invite/open?invite=spaced-token  ',
        ),
        'spaced-token',
      );
    });
  });
}
