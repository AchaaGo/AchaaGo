import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../customer/customer_home_screen.dart';
import '../driver/driver_home_screen.dart';

/// Sends a signed-in user to the customer or driver landing screen.
/// `role` only ever becomes `driver` after `/driver/register` succeeds
/// (services/api/app/main.py `register_driver` sets `user.role = "driver"`
/// permanently), so this is a plain, synchronous branch.
class RoleGateScreen extends StatelessWidget {
  const RoleGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    if (appState.user?.isDriver ?? false) {
      return const DriverHomeScreen();
    }
    return const CustomerHomeScreen();
  }
}
