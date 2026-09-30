import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Exposes the single [AppState] instance to the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  /// Reads the shared state without subscribing to changes. Use for one-off
  /// work started in initState, where inherited dependencies are not allowed.
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope.read() called with no AppScope ancestor');
    return scope!.notifier!;
  }

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope.of() called with no AppScope ancestor');
    return scope!.notifier!;
  }
}
