import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/formatting.dart';
import '../../l10n/strings.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/primary_button.dart';
import '../public/public_tracking_entry_screen.dart';
import 'otp_verify_screen.dart';

/// Screen 1 in AGENTS.md: phone-number entry with the fixed +976 prefix.
class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _phoneController = TextEditingController();
  String _phone = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _onPhoneChanged(String value) {
    final digits = onlyDigits(value, maxLength: 8);
    final formatted = formatPhoneDisplay(digits);
    _phoneController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    setState(() => _phone = digits);
  }

  Future<void> _continue() async {
    final appState = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await appState.authRepository.requestOtp('+976$_phone');
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => OtpVerifyScreen(localPhone: _phone)));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              color: AppColors.ink,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_shipping_outlined, color: AppColors.accent, size: 36),
                  SizedBox(height: 16),
                  Text(
                    Strings.brandTagline,
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, height: 1.25),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(Strings.phoneHeading, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    const Text(Strings.phoneSubtitle, style: TextStyle(color: AppColors.muted, height: 1.4)),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 76,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.ground,
                            border: Border.all(color: AppColors.lineStrong),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text('+976', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            autofocus: true,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1),
                            decoration: const InputDecoration(hintText: Strings.phoneHint),
                            controller: _phoneController,
                            onChanged: _onPhoneChanged,
                          ),
                        ),
                      ],
                    ),
                    ErrorBanner(message: _error),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: Strings.phoneContinue,
                      busy: _busy,
                      onPressed: _phone.length == 8 ? _continue : null,
                    ),
                    const SizedBox(height: 20),
                    RichText(
                      textAlign: TextAlign.center,
                      text: const TextSpan(
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                        children: [
                          TextSpan(text: Strings.termsPrefix),
                          TextSpan(
                            text: Strings.termsLink,
                            style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: Strings.termsSuffix),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const PublicTrackingEntryScreen())),
                        child: const Text(Strings.menuTrackByLink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
