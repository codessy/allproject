import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'src/app_entry.dart';
import 'src/app.dart';
import 'src/core/app_scope.dart';
import 'src/core/deeplink/invite_link_parser.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase native config may be missing in local/dev builds.
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final launchInviteToken = args.isNotEmpty
      ? InviteLinkParser.extractInviteToken(args.first)
      : null;
  final initialInviteToken = await AppScope.initialize(
    initialInviteToken: launchInviteToken,
  );

  runApp(
    WalkieTalkieApp(
      entry: AppEntry(initialInviteToken: initialInviteToken),
    ),
  );
}
