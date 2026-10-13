import 'package:flutter/material.dart';

import 'screens/auth/auth_gate.dart';
import 'theme/app_theme.dart';

class DukaPointApp extends StatelessWidget {
  const DukaPointApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DukaPoint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}