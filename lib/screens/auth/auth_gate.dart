import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../shell/main_shell.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_mark.dart';
import 'pin_screen.dart';
import 'sign_in_screen.dart';

/// Decides which screen the phone shows, in this order:
///   not signed in        -> SignInScreen
///   signed in, loading   -> LoadingScreen
///   shop problem         -> error message + sign out
///   nobody on shift      -> PinScreen
///   someone on shift     -> MainShell (the app)
///
/// Screens never navigate to each other for these jumps; they change the
/// auth or session state and this widget redraws. That's why there are
/// no Navigator.push calls in sign-in or PIN.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.changes,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const LoadingScreen();
        final user = snap.data;
        if (user == null) return const SignInScreen();
        // Keyed by uid so a different shop login gets a fresh session load.
        return _SessionLoader(key: ValueKey(user.uid), uid: user.uid);
      },
    );
  }
}

class _SessionLoader extends StatefulWidget {
  const _SessionLoader({super.key, required this.uid});

  final String uid;

  @override
  State<_SessionLoader> createState() => _SessionLoaderState();
}

class _SessionLoaderState extends State<_SessionLoader> {
  late final Future<String?> _load;

  @override
  void initState() {
    super.initState();
    // Started once here, not in build(), or every rebuild would reload the shop.
    _load = SessionService.instance.load(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _load,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingScreen();
        final problem = snap.hasError ? 'Could not load the shop: ${snap.error}' : snap.data;
        if (problem != null) return _ProblemScreen(message: problem);

        return ListenableBuilder(
          listenable: SessionService.instance,
          builder: (context, _) =>
              SessionService.instance.current == null ? const PinScreen() : const MainShell(),
        );
      },
    );
  }
}

class _ProblemScreen extends StatelessWidget {
  const _ProblemScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Align(alignment: Alignment.centerLeft, child: BrandMark()),
              const SizedBox(height: 32),
              Text(message, style: const TextStyle(fontSize: 18, height: 1.5)),
              const Spacer(),
              OutlinedButton(
                onPressed: () => AuthService.instance.signOut(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: AppColors.ink,
                ),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}