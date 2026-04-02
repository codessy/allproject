import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/channels/data/channel_repository.dart';
import '../features/channels/presentation/invite_accept_screen.dart';
import '../features/devices/data/device_repository.dart';
import 'deeplink/runtime_invite_link_service.dart';
import 'networking/api_base_url.dart';
import 'networking/api_client.dart';
import 'push/push_notification_service.dart';
import 'realtime/ws_client.dart';

class AppScope {
  AppScope._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final ApiClient apiClient = ApiClient(baseUrl: resolveApiBaseUrl());
  static final AuthRepository authRepository = _createAuthRepository();
  static final ChannelRepository channelRepository = ChannelRepository(apiClient);
  static final DeviceRepository deviceRepository = DeviceRepository(apiClient);
  static final PushNotificationService pushNotificationService =
      PushNotificationService();
  static final RuntimeInviteLinkService runtimeInviteLinkService =
      RuntimeInviteLinkService();
  static final WsClient wsClient = WsClient();
  static bool _pushListenersAttached = false;
  static bool _runtimeLinkListenersAttached = false;

  static Future<String?> initialize({String? initialInviteToken}) async {
    final runtimeInviteToken = await runtimeInviteLinkService.initialize();
    final pushInviteToken = await pushNotificationService.initialize();
    if (!_pushListenersAttached) {
      pushNotificationService.inviteTokenListenable.addListener(_handlePendingInvite);
      pushNotificationService.pushTokenListenable.addListener(_handlePushTokenRefresh);
      _pushListenersAttached = true;
    }
    if (!_runtimeLinkListenersAttached) {
      runtimeInviteLinkService.inviteTokenListenable.addListener(_handleRuntimeInvite);
      _runtimeLinkListenersAttached = true;
    }
    return initialInviteToken ?? runtimeInviteToken ?? pushInviteToken;
  }

  static AuthRepository _createAuthRepository() {
    final repository = AuthRepository(apiClient);
    apiClient.setRefreshHandler(repository.tryRefreshSession);
    apiClient.setUnauthorizedHandler(() async {
      await repository.clearSession();
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        return;
      }
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
    return repository;
  }

  static Future<void> syncRegisteredDevice() async {
    final session = authRepository.currentSession;
    if (session == null) {
      return;
    }

    final token =
        pushNotificationService.pushToken ??
        await pushNotificationService.refreshToken();
    if (token == null || token.isEmpty) {
      return;
    }

    await deviceRepository.registerDevice(
      DeviceRegistration(
        platform: _platformName(),
        pushToken: token,
        appVersion: '0.1.0',
      ),
    );
  }

  static void _handlePendingInvite() {
    final inviteToken = pushNotificationService.consumeInviteToken();
    if (inviteToken == null || inviteToken.isEmpty) {
      return;
    }
    _routeInviteToken(
      inviteToken,
      requeue: () => pushNotificationService.inviteTokenListenable.value = inviteToken,
    );
  }

  static void _handleRuntimeInvite() {
    final inviteToken = runtimeInviteLinkService.consumeInviteToken();
    if (inviteToken == null || inviteToken.isEmpty) {
      return;
    }
    _routeInviteToken(
      inviteToken,
      requeue: () => runtimeInviteLinkService.inviteTokenListenable.value = inviteToken,
    );
  }

  static void _routeInviteToken(String inviteToken, {required VoidCallback requeue}) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      requeue();
      return;
    }

    if (authRepository.currentSession == null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginScreen(initialInviteToken: inviteToken),
        ),
        (route) => false,
      );
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => InviteAcceptScreen(initialInviteToken: inviteToken),
      ),
    );
  }

  static void _handlePushTokenRefresh() {
    Future<void>.microtask(syncRegisteredDevice).catchError((_) {
      // Device sync is best-effort; ignore transient registration failures.
    });
  }

  static String _platformName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'unknown';
    }
  }
}
