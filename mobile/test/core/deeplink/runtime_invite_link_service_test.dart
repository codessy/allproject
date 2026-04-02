import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/core/deeplink/runtime_invite_link_service.dart';

void main() {
  group('RuntimeInviteLinkService', () {
    test('initialize extracts invite token from initial link', () async {
      final source = _FakeAppLinkSource(
        initialUri: Uri.parse('walkietalkie://invite/open?invite=initial-token'),
      );
      final service = RuntimeInviteLinkService(linkSource: source);

      final token = await service.initialize();

      expect(token, 'initial-token');
      expect(service.inviteTokenListenable.value, 'initial-token');
    });

    test('streamed link updates token notifier', () async {
      final source = _FakeAppLinkSource();
      final service = RuntimeInviteLinkService(linkSource: source);
      await service.initialize();

      source.emit(Uri.parse('walkietalkie://invite/open?invite=stream-token'));
      await pumpEventQueue();

      expect(service.inviteTokenListenable.value, 'stream-token');
    });

    test('consumeInviteToken clears stored token', () async {
      final source = _FakeAppLinkSource(
        initialUri: Uri.parse('walkietalkie://invite/open?invite=consume-token'),
      );
      final service = RuntimeInviteLinkService(linkSource: source);
      await service.initialize();

      final token = service.consumeInviteToken();

      expect(token, 'consume-token');
      expect(service.inviteTokenListenable.value, isNull);
    });

    test('initialize is idempotent for concurrent calls', () async {
      final source = _FakeAppLinkSource(
        initialUri: Uri.parse('walkietalkie://invite/open?invite=same-token'),
        initialDelay: const Duration(milliseconds: 20),
      );
      final service = RuntimeInviteLinkService(linkSource: source);

      final results = await Future.wait<String?>([
        service.initialize(),
        service.initialize(),
      ]);

      expect(results[0], 'same-token');
      expect(results[1], 'same-token');
      expect(source.initialCalls, 1);
    });

    test('initialize can retry after failure', () async {
      final source = _FakeAppLinkSource(
        initialUri: Uri.parse('walkietalkie://invite/open?invite=retry-token'),
        failInitialCalls: 1,
      );
      final service = RuntimeInviteLinkService(linkSource: source);

      await expectLater(service.initialize(), throwsException);
      final token = await service.initialize();

      expect(token, 'retry-token');
      expect(source.initialCalls, 2);
    });
  });
}

class _FakeAppLinkSource implements AppLinkSource {
  _FakeAppLinkSource({
    this.initialUri,
    this.failInitialCalls = 0,
    this.initialDelay,
  });

  final Uri? initialUri;
  int failInitialCalls;
  final Duration? initialDelay;
  int initialCalls = 0;
  final StreamController<Uri> _uriController = StreamController<Uri>.broadcast();

  void emit(Uri uri) {
    _uriController.add(uri);
  }

  @override
  Future<Uri?> getInitialAppLink() async {
    initialCalls += 1;
    if (initialDelay != null) {
      await Future<void>.delayed(initialDelay!);
    }
    if (failInitialCalls > 0) {
      failInitialCalls -= 1;
      throw Exception('initial link read failed');
    }
    return initialUri;
  }

  @override
  Stream<Uri> get uriLinkStream => _uriController.stream;
}
