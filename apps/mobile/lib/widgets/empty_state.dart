import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'primary_button.dart';

/// A centered icon + message, with an optional retry action. Used for
/// empty lists (no services, no assigned order) and, combined with an
/// [ApiException], for error/offline states.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.onRetry,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: 180,
              child: PrimaryButton(label: Strings.retry, onPressed: onRetry),
            ),
          ],
        ],
      ),
    );
  }
}
