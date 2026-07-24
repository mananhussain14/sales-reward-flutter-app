import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/datasources/portal_context_data_source.dart';
import '../../features/auth/data/repositories/supabase_auth_repository.dart';
import '../../features/auth/data/repositories/supabase_portal_context_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/repositories/portal_context_repository.dart';

/// The service locator.
///
/// Only *shared foundation* dependencies live here — the things every role needs
/// one of. Role-specific shell BLoCs are deliberately absent: each shell
/// constructs its own through a `BlocProvider`.
///
/// The presentation layer resolves the two repository **interfaces** from here
/// and never the Supabase-backed classes by name, and never
/// `Supabase.instance.client`. This file is the one seam where the concrete
/// implementations are chosen, which is what keeps "how we authenticate" a
/// swappable detail.
final GetIt getIt = GetIt.instance;

/// Registers the shared dependency graph against the live Supabase client.
///
/// Safe to call more than once.
Future<void> configureDependencies() async {
  if (getIt.isRegistered<AuthRepository>()) {
    return;
  }

  final SupabaseClient client = Supabase.instance.client;

  getIt.registerLazySingleton<AuthRepository>(
    () => SupabaseAuthRepository(client.auth),
  );

  getIt.registerLazySingleton<PortalContextRepository>(
    () => SupabasePortalContextRepository(
      PortalContextDataSource(supabasePortalContextInvoker(client)),
    ),
  );
}

/// Registers a supplied dependency graph, for tests and previews that stand up
/// no Supabase client.
///
/// Both repositories are required so a test can never accidentally fall through
/// to the live client.
void registerTestDependencies({
  required AuthRepository authRepository,
  required PortalContextRepository portalContextRepository,
}) {
  getIt.registerLazySingleton<AuthRepository>(() => authRepository);
  getIt.registerLazySingleton<PortalContextRepository>(
    () => portalContextRepository,
  );
}

/// Clears the graph. Used by tests so each one starts from a known state.
Future<void> resetDependencies() => getIt.reset();
