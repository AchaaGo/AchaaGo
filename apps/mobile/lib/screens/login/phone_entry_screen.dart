import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../core/api_exception.dart';
import '../../core/formatting.dart';
import '../../l10n/strings.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/theme_toggle_button.dart';
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
  bool _acceptedTerms = false;
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
    if (_phone.length != 8 || !_acceptedTerms || _busy) return;
    final appState = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await appState.authRepository.requestOtp('+976$_phone');
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OtpVerifyScreen(localPhone: _phone)));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 28),
              decoration: BoxDecoration(
                color: p.inkDeep,
                border: Border(bottom: BorderSide(color: p.accent, width: 4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(Icons.local_shipping_outlined,
                          color: p.accent, size: 36),
                      ThemeToggleButton(color: p.onBrand),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      Strings.brandTagline,
                      style: TextStyle(
                          color: p.onBrand,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          height: 1.25),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-0.5, -1),
                    end: const Alignment(0.5, 1),
                    colors: [p.surface, p.surface, p.entryEnd],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(Strings.phoneHeading,
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(Strings.phoneSubtitle,
                          style: TextStyle(color: p.muted, height: 1.4)),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 76,
                            height: 56,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.mintSoft,
                              border: Border.all(color: p.mint),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text('+976',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, color: p.ink)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              autofocus: true,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1),
                              decoration: InputDecoration(
                                hintText: Strings.phoneHint,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: p.mint),
                                ),
                              ),
                              controller: _phoneController,
                              onChanged: _onPhoneChanged,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: p.accentSoft,
                          border: Border.all(
                              color:
                                  _acceptedTerms ? p.accent : p.termsLine),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                                value: _acceptedTerms,
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(
                                        () => _acceptedTerms = value ?? false)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(Strings.acceptTerms,
                                      style: TextStyle(fontSize: 13)),
                                  TextButton(
                                    onPressed: () => launchUrl(
                                      Uri.parse(AppConfig.apiBaseUrl)
                                          .replace(path: '/terms'),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    child: const Text(Strings.readTerms),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_acceptedTerms)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(Strings.termsRequired,
                              style: TextStyle(color: p.muted, fontSize: 12)),
                        ),
                      ErrorBanner(message: _error),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: Strings.phoneContinue,
                        busy: _busy,
                        onPressed: _phone.length == 8 && _acceptedTerms
                            ? _continue
                            : null,
                      ),
                      const SizedBox(height: 20),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const PublicTrackingEntryScreen())),
                          child: const Text(Strings.menuTrackByLink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
