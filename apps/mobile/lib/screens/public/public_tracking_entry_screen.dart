import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import 'public_tracking_screen.dart';

String extractTrackingToken(String input) {
  final trimmed = input.trim();
  const marker = '/t/';
  final index = trimmed.lastIndexOf(marker);
  var token = index >= 0 ? trimmed.substring(index + marker.length) : trimmed;
  final queryIndex = token.indexOf('?');
  if (queryIndex >= 0) token = token.substring(0, queryIndex);
  return token.replaceAll('/', '');
}

/// Entry point for `GET /t/{token}` — the customer pastes the shareable
/// tracking link (or just its token) without needing to log in.
class PublicTrackingEntryScreen extends StatefulWidget {
  const PublicTrackingEntryScreen({super.key});

  @override
  State<PublicTrackingEntryScreen> createState() => _PublicTrackingEntryScreenState();
}

class _PublicTrackingEntryScreenState extends State<PublicTrackingEntryScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    final token = extractTrackingToken(_controller.text);
    if (token.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublicTrackingScreen(token: token)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.publicTrackingHeading)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(Strings.publicTrackingHint, style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(hintText: '/t/xxxxxxxxxxxx'),
                onSubmitted: (_) => _open(),
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: Strings.publicTrackingOpen, onPressed: _open),
            ],
          ),
        ),
      ),
    );
  }
}
