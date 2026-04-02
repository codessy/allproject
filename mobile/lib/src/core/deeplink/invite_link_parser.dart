class InviteLinkParser {
  static String? extractInviteToken(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return trimmed;
    }

    final tokenFromQuery = uri.queryParameters['invite'] ?? uri.queryParameters['token'];
    if (tokenFromQuery != null && tokenFromQuery.isNotEmpty) {
      return tokenFromQuery;
    }

    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      return segments.last;
    }

    return trimmed;
  }
}
