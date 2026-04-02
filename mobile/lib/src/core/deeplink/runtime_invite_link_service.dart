import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'invite_link_parser.dart';

abstract class AppLinkSource {
  Future<Uri?> getInitialAppLink();
  Stream<Uri> get uriLinkStream;
}

class DefaultAppLinkSource implements AppLinkSource {
  DefaultAppLinkSource([AppLinks? appLinks]) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> getInitialAppLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get uriLinkStream => _appLinks.uriLinkStream;
}

class RuntimeInviteLinkService {
  RuntimeInviteLinkService({
    AppLinkSource? linkSource,
  }) : _linkSource = linkSource ?? DefaultAppLinkSource();

  final AppLinkSource _linkSource;
  final ValueNotifier<String?> inviteTokenListenable = ValueNotifier<String?>(null);

  Future<String?>? _initializeFuture;
  StreamSubscription<Uri>? _uriSub;

  Future<String?> initialize() {
    if (_initializeFuture != null) {
      return _initializeFuture!;
    }
    _initializeFuture = _initializeInternal();
    return _initializeFuture!;
  }

  String? consumeInviteToken() {
    final token = inviteTokenListenable.value;
    inviteTokenListenable.value = null;
    return token;
  }

  Future<String?> _initializeInternal() async {
    try {
      final initialUri = await _linkSource.getInitialAppLink();
      _setTokenFromUri(initialUri);
      _uriSub?.cancel();
      _uriSub = _linkSource.uriLinkStream.listen(
        _setTokenFromUri,
        onError: (_) {},
      );
      return inviteTokenListenable.value;
    } finally {
      _initializeFuture = null;
    }
  }

  void _setTokenFromUri(Uri? uri) {
    if (uri == null) {
      return;
    }
    final token = InviteLinkParser.extractInviteToken(uri.toString());
    if (token == null || token.isEmpty) {
      return;
    }
    inviteTokenListenable.value = token;
  }
}
