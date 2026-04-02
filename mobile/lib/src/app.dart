import 'package:flutter/material.dart';

import 'app_bootstrap_screen.dart';
import 'app_entry.dart';
import 'core/app_scope.dart';

class WalkieTalkieApp extends StatelessWidget {
  const WalkieTalkieApp({
    super.key,
    this.entry = const AppEntry(),
  });

  final AppEntry entry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WalkieTalkie',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppScope.navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: AppBootstrapScreen(entry: entry),
    );
  }
}
