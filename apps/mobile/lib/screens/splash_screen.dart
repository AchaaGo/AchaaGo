import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/loading_view.dart';
import 'login/phone_entry_screen.dart';
import 'shared/role_gate_screen.dart';

/// Restores a stored session (if any) before deciding whether to land on
/// the login flow or the signed-in role gate.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final appState = AppScope.of(context);
    await appState.bootstrap();
    if (!mounted) return;
    final target = appState.status == AuthStatus.signedIn
        ? const RoleGateScreen()
        : const PhoneEntryScreen();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => target));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: AppColors.ink, body: LoadingView(dark: true));
  }
}
