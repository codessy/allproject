import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/core/push/push_notification_service.dart';

void main() {
  group('PushNotificationService', () {
    test('initialize stores push token and initial invite token', () async {
      final bootstrapper = _FakePushBootstrapper(
        messaging: _FakeMessagingClient(
          token: 'push-token-1',
          initialMessage: PushMessagePayload(
            data: <String, dynamic>{'inviteToken': 'invite-token-123'},
          ),
        ),
      );
      final service = PushNotificationService(bootstrapper: bootstrapper);

      final initialInviteToken = await service.initialize();

      expect(initialInviteToken, 'invite-token-123');
      expect(service.pushToken, 'push-token-1');
      expect(service.pushTokenListenable.value, 'push-token-1');
      expect(service.inviteTokenListenable.value, 'invite-token-123');
      expect(bootstrapper.initializeCalls, 1);
    });

    test('consumeInviteToken returns token and clears notifier', () async {
      final service = PushNotificationService(
        bootstrapper: _FakePushBootstrapper(
          messaging: _FakeMessagingClient(
            initialMessage: PushMessagePayload(
              data: <String, dynamic>{'inviteToken': 'invite-token-123'},
            ),
          ),
        ),
      );
      await service.initialize();

      final token = service.consumeInviteToken();

      expect(token, 'invite-token-123');
      expect(service.inviteTokenListenable.value, isNull);
    });

    test('refreshToken updates push token notifier', () async {
      final messaging = _FakeMessagingClient(token: 'push-token-1');
      final service = PushNotificationService(
        bootstrapper: _FakePushBootstrapper(messaging: messaging),
      );
      await service.initialize();

      messaging.token = 'push-token-2';
      final refreshedToken = await service.refreshToken();

      expect(refreshedToken, 'push-token-2');
      expect(service.pushToken, 'push-token-2');
      expect(service.pushTokenListenable.value, 'push-token-2');
    });

    test('foreground and opened-app messages extract invite token variants', () async {
      final messaging = _FakeMessagingClient(token: 'push-token-1');
      final service = PushNotificationService(
        bootstrapper: _FakePushBootstrapper(messaging: messaging),
      );
      await service.initialize();

      messaging.emitForeground(
        PushMessagePayload(
          data: <String, dynamic>{'link': 'walkietalkie://invite/open?invite=query-token'},
        ),
      );
      await pumpEventQueue();
      expect(service.consumeInviteToken(), 'query-token');

      messaging.emitOpened(
        PushMessagePayload(
          data: <String, dynamic>{},
          notificationBody: 'https://example.com/invites/path-token',
        ),
      );
      await pumpEventQueue();
      expect(service.consumeInviteToken(), 'path-token');
    });

    test('token refresh stream updates internal token state', () async {
      final messaging = _FakeMessagingClient(token: 'push-token-1');
      final service = PushNotificationService(
        bootstrapper: _FakePushBootstrapper(messaging: messaging),
      );
      await service.initialize();

      messaging.emitTokenRefresh('push-token-2');
      await pumpEventQueue();

      expect(service.pushToken, 'push-token-2');
      expect(service.pushTokenListenable.value, 'push-token-2');
    });

    test('initialize is idempotent and bootstrap runs once', () async {
      final bootstrapper = _FakePushBootstrapper(
        messaging: _FakeMessagingClient(token: 'push-token-1'),
      );
      final service = PushNotificationService(bootstrapper: bootstrapper);

      await service.initialize();
      await service.initialize();

      expect(bootstrapper.initializeCalls, 1);
    });

    test('denied permission skips push token retrieval', () async {
      final messaging = _FakeMessagingClient(
        token: 'push-token-1',
        authorizationStatus: AuthorizationStatus.denied,
      );
      final service = PushNotificationService(
        bootstrapper: _FakePushBootstrapper(messaging: messaging),
      );

      await service.initialize();

      expect(service.pushToken, isNull);
      expect(service.pushTokenListenable.value, isNull);
      expect(messaging.getTokenCalls, 0);
    });

    test('initialize retries after bootstrap failure', () async {
      final bootstrapper = _FakePushBootstrapper(
        messaging: _FakeMessagingClient(token: 'push-token-2'),
        failInitializeCalls: 1,
      );
      final service = PushNotificationService(bootstrapper: bootstrapper);

      await service.initialize();
      expect(service.pushToken, isNull);

      await service.initialize();
      expect(service.pushToken, 'push-token-2');
      expect(bootstrapper.initializeCalls, 2);
    });

    test('concurrent initialize calls share a single bootstrap run', () async {
      final bootstrapper = _FakePushBootstrapper(
        messaging: _FakeMessagingClient(token: 'push-token-1'),
        initializeDelay: const Duration(milliseconds: 30),
      );
      final service = PushNotificationService(bootstrapper: bootstrapper);

      final results = await Future.wait<String?>([
        service.initialize(),
        service.initialize(),
      ]);

      expect(results[0], isNull);
      expect(results[1], isNull);
      expect(bootstrapper.initializeCalls, 1);
    });
  });
}

class _FakePushBootstrapper implements PushBootstrapper {
  _FakePushBootstrapper({
    required this.messaging,
    this.failInitializeCalls = 0,
    this.initializeDelay,
  });

  final _FakeMessagingClient messaging;
  int failInitializeCalls;
  final Duration? initializeDelay;
  int initializeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    if (initializeDelay != null) {
      await Future<void>.delayed(initializeDelay!);
    }
    if (failInitializeCalls > 0) {
      failInitializeCalls -= 1;
      throw Exception('bootstrap failed');
    }
  }

  @override
  MessagingClient messagingClient() => messaging;
}

class _FakeMessagingClient implements MessagingClient {
  _FakeMessagingClient({
    this.token,
    this.initialMessage,
    this.authorizationStatus = AuthorizationStatus.authorized,
  });

  String? token;
  final PushMessagePayload? initialMessage;
  final AuthorizationStatus authorizationStatus;
  int getTokenCalls = 0;
  final StreamController<PushMessagePayload> _onMessageController =
      StreamController<PushMessagePayload>.broadcast();
  final StreamController<PushMessagePayload> _onOpenedController =
      StreamController<PushMessagePayload>.broadcast();
  final StreamController<String> _onTokenRefreshController =
      StreamController<String>.broadcast();

  void emitForeground(PushMessagePayload payload) {
    _onMessageController.add(payload);
  }

  void emitOpened(PushMessagePayload payload) {
    _onOpenedController.add(payload);
  }

  void emitTokenRefresh(String token) {
    _onTokenRefreshController.add(token);
  }

  @override
  Future<PushMessagePayload?> getInitialMessage() async => initialMessage;

  @override
  Future<String?> getToken() async {
    getTokenCalls += 1;
    return token;
  }

  @override
  Stream<PushMessagePayload> get onMessage => _onMessageController.stream;

  @override
  Stream<PushMessagePayload> get onMessageOpenedApp => _onOpenedController.stream;

  @override
  Stream<String> get onTokenRefresh => _onTokenRefreshController.stream;

  @override
  Future<NotificationSettings> requestPermission() async {
    return NotificationSettings(
      authorizationStatus: authorizationStatus,
      alert: AppleNotificationSetting.enabled,
      announcement: AppleNotificationSetting.notSupported,
      badge: AppleNotificationSetting.enabled,
      carPlay: AppleNotificationSetting.notSupported,
      lockScreen: AppleNotificationSetting.enabled,
      notificationCenter: AppleNotificationSetting.enabled,
      showPreviews: AppleShowPreviewSetting.always,
      sound: AppleNotificationSetting.enabled,
      timeSensitive: AppleNotificationSetting.notSupported,
      criticalAlert: AppleNotificationSetting.notSupported,
      providesAppNotificationSettings: AppleNotificationSetting.notSupported,
    );
  }
}
