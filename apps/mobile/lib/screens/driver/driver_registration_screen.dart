import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../l10n/strings.dart';
import '../../models/service.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/primary_button.dart';
import 'driver_home_screen.dart';

/// `POST /driver/register` (services/api/app/schemas.py `DriverRegistration`).
/// Converts the signed-in customer account into a driver account — the
/// backend only allows this once per account (409 DRIVER_ALREADY_REGISTERED
/// afterwards), and the resulting driver still needs staff approval in the
/// admin panel before going online.
class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({super.key});

  @override
  State<DriverRegistrationScreen> createState() => _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _license = TextEditingController();
  final _plate = TextEditingController();
  final _model = TextEditingController();
  final _capacity = TextEditingController();

  bool _loadingServices = true;
  List<ServiceOption> _services = const [];
  String? _serviceId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  @override
  void dispose() {
    _name.dispose();
    _license.dispose();
    _plate.dispose();
    _model.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    final appState = AppScope.of(context);
    try {
      final services = await appState.customerRepository.services();
      if (!mounted) return;
      setState(() {
        _services = services;
        _serviceId = services.isNotEmpty ? services.first.id : null;
        _loadingServices = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        _loadingServices = false;
      });
    }
  }

  Future<void> _submit() async {
    final appState = AppScope.of(context);
    if (!(_formKey.currentState?.validate() ?? false) || _serviceId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await appState.driverRepository.register(
        name: _name.text.trim(),
        licenseInfo: _license.text.trim(),
        serviceId: _serviceId!,
        plateNumber: _plate.text.trim(),
        model: _model.text.trim(),
        capacityKg: int.parse(_capacity.text.trim()),
      );
      await appState.refreshUser();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.driverRegisterHeading)),
      body: SafeArea(
        child: _loadingServices
            ? const LoadingView()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(Strings.driverRegisterSubtitle, style: TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: Strings.driverNameLabel),
                        validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : Strings.driverNameLabel,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _license,
                        decoration: const InputDecoration(labelText: Strings.driverLicenseLabel),
                        validator: (v) => (v?.trim().length ?? 0) >= 3 ? null : Strings.driverLicenseLabel,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _serviceId,
                        decoration: const InputDecoration(labelText: Strings.driverServiceLabel),
                        items: _services
                            .map((service) => DropdownMenuItem(value: service.id, child: Text(service.nameMn)))
                            .toList(),
                        onChanged: (value) => setState(() => _serviceId = value),
                        validator: (value) => value == null ? Strings.driverServiceLabel : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _plate,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: Strings.driverPlateLabel),
                        validator: (v) => (v?.trim().length ?? 0) >= 4 ? null : Strings.driverPlateLabel,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _model,
                        decoration: const InputDecoration(labelText: Strings.driverModelLabel),
                        validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : Strings.driverModelLabel,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _capacity,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: Strings.driverCapacityLabel),
                        validator: (v) {
                          final value = int.tryParse(v?.trim() ?? '');
                          if (value == null || value < 50 || value > 30000) return Strings.driverCapacityLabel;
                          return null;
                        },
                      ),
                      ErrorBanner(message: _error),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        accent: true,
                        busy: _busy,
                        label: Strings.driverRegisterSubmit,
                        onPressed: _services.isEmpty ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
