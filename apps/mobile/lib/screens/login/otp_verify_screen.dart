import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../core/api_exception.dart';
import '../../core/formatting.dart';
import '../../l10n/strings.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/primary_button.dart';
import '../shared/role_gate_screen.dart';

/// Screen 2 in AGENTS.md. A complete 4-digit code submits itself (iOS also
/// offers it from Messages). The shortcut code AppConfig.devOtpCode and its
/// hint exist only while the server runs SMS_PROVIDER=console, same as the
/// web login.
class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({super.key, required this.localPhone});

  final String localPhone;

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _codeController = TextEditingController();
  String _code = '';
  bool _busy = false;
  bool _devOtp = false;
  String? _error;
  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    AppScope.read(context).authRepository.devOtpEnabled().then((enabled) {
      if (mounted && enabled) setState(() => _devOtp = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _resend() async {
    final appState = AppScope.of(context);
    setState(() => _error = null);
    try {
      await appState.authRepository.requestOtp('+976${widget.localPhone}');
      _startCountdown();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _verify() async {
    final appState = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await appState.authRepository.verifyOtp('+976${widget.localPhone}', _code);
      appState.completeLogin(result.user);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleGateScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onCodeChanged(String value) {
    final digits = onlyDigits(value, maxLength: 4);
    if (digits != value) {
      _codeController.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }
    setState(() => _code = digits);
    if (digits.length == 4 && !_busy) _verify();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(Strings.otpHeading, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                Strings.otpSubtitle(formatPhoneDisplay(widget.localPhone)),
                style: const TextStyle(color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 4,
                autofillHints: const [AutofillHints.oneTimeCode],
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 18),
                decoration: const InputDecoration(counterText: '', hintText: '····'),
                onChanged: _onCodeChanged,
              ),
              if (_devOtp)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(Strings.otpDevHint, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
              ErrorBanner(message: _error),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _secondsLeft > 0 || _busy ? null : _resend,
                  child: Text(_secondsLeft > 0 ? Strings.otpResendCountdown(_secondsLeft) : Strings.otpResend),
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: Strings.otpVerify, busy: _busy, onPressed: _code.length == 4 || (_devOtp && _code == AppConfig.devOtpCode) ? _verify : null),
            ],
          ),
        ),
      ),
    );
  }
}
