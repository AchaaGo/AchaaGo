import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/splash_screen.dart';
import 'state/app_scope.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

class AchaaGoApp extends StatefulWidget {
  const AchaaGoApp({super.key});

  @override
  State<AchaaGoApp> createState() => _AchaaGoAppState();
}

class _AchaaGoAppState extends State<AchaaGoApp> {
  final AppState _appState = AppState();
  final ThemeData _lightTheme = buildAppTheme(Brightness.light);
  final ThemeData _darkTheme = buildAppTheme(Brightness.dark);

  @override
  void initState() {
    super.initState();
    _appState.loadThemeMode();
  }

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _appState,
      child: ListenableBuilder(
        listenable: _appState,
        builder: (context, _) => MaterialApp(
          title: AppConfig.brandName,
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: _appState.themeMode,
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
