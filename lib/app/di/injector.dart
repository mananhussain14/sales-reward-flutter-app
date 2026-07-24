import 'package:get_it/get_it.dart';

import '../../features/auth/data/repositories/unimplemented_portal_context_repository.dart';
import '../../features/auth/domain/repositories/portal_context_repository.dart';

/// The service locator.
///
/// Only *shared foundation* dependencies are registered here — the things every
/// role needs one of. Role-specific BLoCs are deliberately absent: each shell
/// constructs its own through a `BlocProvider`, so a shell's lifetime owns its
/// BLoC's lifetime and no role can resolve another role's state object.
final GetIt getIt = GetIt.instance;

/// Registers the shared dependency graph. Safe to call more than once.
Future<void> configureDependencies() async {
  if (getIt.isRegistered<PortalContextRepository>()) {
    return;
  }

  // The only implementation that exists. It reports that
  // `get_my_portal_context()` has not been built rather than guessing a role.
  getIt.registerLazySingleton<PortalContextRepository>(
    () => const UnimplementedPortalContextRepository(),
  );
}

/// Clears the graph. Used by tests so each one starts from a known state.
Future<void> resetDependencies() => getIt.reset();
