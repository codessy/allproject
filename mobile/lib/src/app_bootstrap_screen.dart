import 'package:flutter/material.dart';

import 'app_entry.dart';
import 'core/app_scope.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/channels/presentation/channel_list_screen.dart';
import 'features/channels/presentation/invite_accept_screen.dart';

class AppBootstrapScreen extends StatefulWidget {
  const AppBootstrapScreen({
    super.key,
    required this.entry,
    this.authRepository,
    this.syncRegisteredDevice,
  });

  final AppEntry entry;
  final AuthRepository? authRepository;
  final Future<void> Function()? syncRegisteredDevice;

  AuthRepository get resolvedAuthRepository => authRepository ?? AppScope.authRepository;

  Future<void> Function() get resolvedSyncRegisteredDevice =>
      syncRegisteredDevice ?? AppScope.syncRegisteredDevice;

  @override
  State<AppBootstrapScreen> createState() => _AppBootstrapScreenState();
}

class _AppBootstrapScreenState extends State<AppBootstrapScreen> {
  late final Future<AuthSession?> _sessionFuture;
  bool _deviceSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    _sessionFuture = widget.resolvedAuthRepository.restoreSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthSession?>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return ValueListenableBuilder<AuthSession?>(
          valueListenable: widget.resolvedAuthRepository.sessionListenable,
          builder: (context, session, _) {
            if (session == null) {
              _deviceSyncScheduled = false;
              return LoginScreen(
                initialInviteToken: widget.entry.initialInviteToken,
              );
            }

            if (!_deviceSyncScheduled) {
              _deviceSyncScheduled = true;
              Future<void>.microtask(widget.resolvedSyncRegisteredDevice).catchError((_) {
                // Device registration is best-effort and must not break bootstrap flow.
              });
            }

            if (widget.entry.initialInviteToken != null) {
              return InviteAcceptScreen(
                initialInviteToken: widget.entry.initialInviteToken,
              );
            }

            return ChannelListScreen(currentUserName: session.displayName);
          },
        );
      },
    );
  }
}
