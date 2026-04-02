import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../deeplink/invite_link_parser.dart';

class PushMessagePayload {
  PushMessagePayload({
    required this.data,
    this.notificationBody,
  });

  final Map<String, dynamic> data;
  final String? notificationBody;
}

abstract class MessagingClient {
  Future<NotificationSettings> requestPermission();
  Future<String?> getToken();
  Future<PushMessagePayload?> getInitialMessage();
  Stream<PushMessagePayload> get onMessageOpenedApp;
  Stream<PushMessagePayload> get onMessage;
  Stream<String> get onTokenRefresh;
}

abstract class PushBootstrapper {
  Future<void> initialize();
  MessagingClient messagingClient();
}

class FirebasePushBootstrapper implements PushBootstrapper {
  @override
  Future<void> initialize() => Firebase.initializeApp();

  @override
  MessagingClient messagingClient() => FirebaseMessagingClient(FirebaseMessaging.instance);
}

class FirebaseMessagingClient implements MessagingClient {
  FirebaseMessagingClient(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<PushMessagePayload?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _payloadFromRemoteMessage(message);
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<PushMessagePayload> get onMessage =>
      FirebaseMessaging.onMessage.map(_payloadFromRemoteMessage);

  @override
  Stream<PushMessagePayload> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(_payloadFromRemoteMessage);

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<NotificationSettings> requestPermission() {
    return _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true,
    );
  }

  PushMessagePayload _payloadFromRemoteMessage(RemoteMessage message) {
    return PushMessagePayload(
      data: message.data,
      notificationBody: message.notification?.body,
    );
  }
}

class PushNotificationService {
  PushNotificationService({PushBootstrapper? bootstrapper})
    : _bootstrapper = bootstrapper ?? FirebasePushBootstrapper();

  final ValueNotifier<String?> inviteTokenListenable = ValueNotifier<String?>(null);
  final ValueNotifier<String?> pushTokenListenable = ValueNotifier<String?>(null);
  final PushBootstrapper _bootstrapper;

  MessagingClient? _messaging;
  String? _pushToken;
  bool _initialized = false;
  Future<String?>? _initializingFuture;

  String? get pushToken => _pushToken;

  Future<String?> initialize() async {
    if (_initialized) {
      return inviteTokenListenable.value;
    }
    final ongoing = _initializingFuture;
    if (ongoing != null) {
      return ongoing;
    }

    final initializeFuture = _initializeInternal();
    _initializingFuture = initializeFuture;
    try {
      return await initializeFuture;
    } finally {
      _initializingFuture = null;
    }
  }

  Future<String?> _initializeInternal() async {
    if (_initialized) {
      return inviteTokenListenable.value;
    }

    try {
      await _bootstrapper.initialize();
      _messaging = _bootstrapper.messagingClient();

      final settings = await _messaging!.requestPermission();

      if (settings.authorizationStatus != AuthorizationStatus.denied) {
        _pushToken = await _messaging!.getToken();
        pushTokenListenable.value = _pushToken;
      }

      _messaging!.onMessageOpenedApp.listen(_handleRemoteMessage);
      _messaging!.onMessage.listen(_handleForegroundMessage);
      _messaging!.onTokenRefresh.listen((token) {
        _pushToken = token;
        pushTokenListenable.value = token;
      });

      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        _handleRemoteMessage(initialMessage);
      }
      _initialized = true;
    } catch (_) {
      _initialized = false;
      // Native Firebase setup may not exist yet in local/dev environments.
    }

    return inviteTokenListenable.value;
  }

  Future<String?> refreshToken() async {
    if (_messaging == null) {
      return _pushToken;
    }
    _pushToken = await _messaging!.getToken();
    pushTokenListenable.value = _pushToken;
    return _pushToken;
  }

  String? consumeInviteToken() {
    final token = inviteTokenListenable.value;
    inviteTokenListenable.value = null;
    return token;
  }

  void _handleForegroundMessage(PushMessagePayload message) {
    _storeInviteToken(_extractInviteToken(message));
  }

  void _handleRemoteMessage(PushMessagePayload message) {
    _storeInviteToken(_extractInviteToken(message));
  }

  void _storeInviteToken(String? token) {
    if (token == null || token.isEmpty) {
      return;
    }
    inviteTokenListenable.value = token;
  }

  String? _extractInviteToken(PushMessagePayload message) {
    final rawToken =
        message.data['inviteToken'] ??
        message.data['token'] ??
        message.data['link'] ??
        message.notificationBody;

    if (rawToken is! String) {
      return null;
    }
    return InviteLinkParser.extractInviteToken(rawToken);
  }
}
