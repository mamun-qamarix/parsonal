import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_globals.dart';
import 'core/security/app_lock_guard.dart';
import 'core/theme/app_theme.dart';
import 'providers/session_provider.dart';
import 'screens/auth/biometric_unlock_screen.dart';
import 'screens/auth/decoy_home_screen.dart';
import 'screens/auth/face_verify_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/onboarding/welcome_screen.dart';

void main() {
  runApp(const CoupleVaultApp());
}

class CoupleVaultApp extends StatelessWidget {
  const CoupleVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SessionProvider()..bootstrap()),
      ],
      child: MaterialApp(
        title: "পার্সোনাল",
        scaffoldMessengerKey: scaffoldMessengerKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        // Tap anywhere outside a text field to dismiss the keyboard --
        // otherwise an open keyboard can cover a button below it, and taps
        // meant for that button silently land on the keyboard instead.
        builder: (context, child) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        ),
        home: const AppLockGuard(child: AuthGate()),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    switch (session.state) {
      case SessionState.unknown:
        return const _Splash();
      case SessionState.needsSetup:
        return const WelcomeScreen();
      case SessionState.locked:
        return const LoginScreen();
      case SessionState.needsBiometric:
        return const BiometricUnlockScreen();
      case SessionState.needsFaceVerify:
        return const FaceVerifyScreen();
      case SessionState.authenticated:
        return const HomeShell();
      case SessionState.decoy:
        return const DecoyHomeScreen();
    }
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Icon(Icons.favorite, size: 56, color: AppColors.halalGreen)),
    );
  }
}
