import 'package:firebase_auth/firebase_auth.dart';

import 'session_service.dart';

/// Thin wrapper around Firebase Auth. One login per shop, not per person.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;

  Stream<User?> get changes => _auth.authStateChanges();

  Future<void> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<void> signOut() async {
    // Clear the session first so no screen briefly shows the old shop's
    // data while the sign-out goes through.
    await SessionService.instance.clear();
    await _auth.signOut();
  }

  /// Plain-language messages for the errors a shop owner will actually hit.
  static String messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'Email or password is wrong.';
      case 'network-request-failed':
        return 'No internet. The first sign-in on a phone needs a connection.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a few minutes and try again.';
      case 'user-disabled':
        return 'This shop login has been disabled. Contact DukaPoint.';
      default:
        return 'Sign-in failed (${e.code}).';
    }
  }
}