import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Inline error text — matches `<p className="error" role="alert">` in
/// the web app's forms.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Semantics(
        liveRegion: true,
        child: Text(message!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
