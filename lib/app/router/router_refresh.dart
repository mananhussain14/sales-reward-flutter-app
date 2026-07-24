import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a BLoC stream to `GoRouter.refreshListenable`, so a change in the
/// resolved role re-evaluates every redirect.
///
/// Without this, a role that changes mid-session — revoked server-side, or
/// cleared on sign-out — would leave the user sitting inside a shell they no
/// longer belong in until they happened to navigate.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<Object?> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (Object? _) => notifyListeners(),
    );
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
