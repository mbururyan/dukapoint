import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_mark.dart';

/// Wireframe 1. Done once per phone; after that, staff only see the PIN screen.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signIn(_email.text, _password.text);
      // No navigation here: AuthGate is listening to sign-in state and
      // swaps this screen out on its own.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(alignment: Alignment.centerLeft, child: BrandMark()),
                const SizedBox(height: 32),
                const Text('Sign in to your shop', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                  'Once per phone. After this, cashiers switch with their PIN.',
                  style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Shop email'),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter the shop email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: _hidePassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      tooltip: _hidePassword ? 'Show password' : 'Hide password',
                      icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hidePassword = !_hidePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter the password' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 15)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'New shop? ', style: TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: 'Shops are set up and activated by DukaPoint. Call or WhatsApp [YOUR NUMBER].'),
                      ],
                    ),
                    style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}