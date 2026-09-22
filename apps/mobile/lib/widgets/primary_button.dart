import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A full-width button that shows a spinner instead of its label while
/// [busy], and stays disabled while [onPressed] is null — matches the
/// disabled/loading states used throughout apps/web (e.g. `busy?<span
/// className="spinner"/>:'Баталгаажуулах'`).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.accent = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: accent ? accentButtonStyle : null,
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: accent ? AppColors.ink : Colors.white,
              ),
            )
          : Text(label),
    );
  }
}
