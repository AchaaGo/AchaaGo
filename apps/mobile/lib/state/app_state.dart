import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/session_store.dart';
import '../models/user.dart';
import '../repositories/auth_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/driver_repository.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// App-wide session state: who is signed in, and the shared repositories
/// every screen needs. Kept deliberately small (no external state
/// management package) since a handful of screens don't need much more
/// than "who is the user" shared across the tree.
class AppState extends ChangeNotifier {
  AppState({ApiClient? api, SessionStore? sessionStore})
      : sessionStore = sessionStore ?? SessionStore(),
        api = api ?? ApiClient() {
    this.api.onSessionExpired = _handleSessionExpired;
    authRepository = AuthRepository(this.api, this.sessionStore);
    customerRepository = CustomerRepository(this.api);
    driverRepository = DriverRepository(this.api);
  }

  final SessionStore sessionStore;
  final ApiClient api;
  late final AuthRepository authRepository;
  late final CustomerRepository customerRepository;
  late final DriverRepository driverRepository;

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;

  /// Runs once at startup: is there a stored session, and is it still
  /// valid against the backend (`GET /auth/me`)?
  Future<void> bootstrap() async {
    if (!await authRepository.hasStoredSession()) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    try {
      user = await authRepository.me();
      status = AuthStatus.signedIn;
    } catch (_) {
      await sessionStore.clear();
      status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  void completeLogin(AppUser signedInUser) {
    user = signedInUser;
    status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    user = await authRepository.me();
    notifyListeners();
  }

  Future<void> logout() async {
    await authRepository.logout();
    user = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> _handleSessionExpired() async {
    await sessionStore.clear();
    user = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}
