import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/networking/api_error_message.dart';
import '../data/auth_repository.dart';
import '../../channels/presentation/channel_list_screen.dart';
import '../../channels/presentation/invite_accept_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.initialInviteToken,
    this.login,
    this.register,
    this.syncRegisteredDevice,
  });

  final String? initialInviteToken;
  final Future<AuthSession> Function({
    required String email,
    required String password,
  })? login;
  final Future<AuthSession> Function({
    required String email,
    required String displayName,
    required String password,
  })? register;
  final Future<void> Function()? syncRegisteredDevice;

  Future<AuthSession> Function({
    required String email,
    required String password,
  }) get resolvedLogin => login ?? AppScope.authRepository.login;

  Future<AuthSession> Function({
    required String email,
    required String displayName,
    required String password,
  }) get resolvedRegister => register ?? AppScope.authRepository.register;

  Future<void> Function() get resolvedSyncRegisteredDevice =>
      syncRegisteredDevice ?? AppScope.syncRegisteredDevice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController(text: 'demo@example.com');
  final displayNameController = TextEditingController(text: 'Yeni Kullanici');
  final passwordController = TextEditingController(text: 'password');
  bool registerMode = false;
  bool loading = false;
  String? error;

  Future<void> _submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    final displayName = displayNameController.text.trim();
    if (email.isEmpty) {
      setState(() => error = 'E-posta zorunlu.');
      return;
    }
    if (password.isEmpty) {
      setState(() => error = 'Sifre zorunlu.');
      return;
    }
    if (registerMode && displayName.isEmpty) {
      setState(() => error = 'Gorunen ad bos olamaz.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      late final AuthSession session;
      if (registerMode) {
        session = await widget.resolvedRegister(
          email: email,
          displayName: displayName,
          password: password,
        );
      } else {
        session = await widget.resolvedLogin(
          email: email,
          password: password,
        );
      }

      await widget.resolvedSyncRegisteredDevice();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => widget.initialInviteToken != null
              ? InviteAcceptScreen(
                  initialInviteToken: widget.initialInviteToken!,
                )
              : ChannelListScreen(
                  currentUserName: session.displayName,
                ),
        ),
      );
    } catch (e) {
      final apiMsg = apiErrorMessageFrom(e);
      setState(() {
        error = apiMsg.isNotEmpty
            ? apiMsg
            : (registerMode
                  ? 'Kayit basarisiz. Email zaten kayitli olabilir.'
                  : 'Giris basarisiz. Backend calisiyor mu kontrol edin.');
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: Text(registerMode ? 'Kayit' : 'Giris')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: emailController,
              onChanged: (_) {
                if (error != null) {
                  setState(() => error = null);
                }
              },
              decoration: const InputDecoration(labelText: 'E-posta'),
            ),
            if (registerMode) ...[
              const SizedBox(height: 16),
              TextField(
                controller: displayNameController,
                onChanged: (_) {
                  if (error != null) {
                    setState(() => error = null);
                  }
                },
                decoration: const InputDecoration(labelText: 'Gorunen ad'),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              onChanged: (_) {
                if (error != null) {
                  setState(() => error = null);
                }
              },
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Sifre'),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: loading ? null : _submit,
              child: Text(
                loading
                    ? 'Bekleyin...'
                    : (registerMode ? 'Kayit Ol' : 'Giris Yap'),
              ),
            ),
            TextButton(
              onPressed: loading
                  ? null
                  : () {
                      setState(() {
                        registerMode = !registerMode;
                        error = null;
                      });
                    },
              child: Text(
                registerMode
                    ? 'Zaten hesabin var mi? Giris yap'
                    : 'Hesabin yok mu? Kayit ol',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    displayNameController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
