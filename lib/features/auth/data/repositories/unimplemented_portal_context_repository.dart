import '../../../../core/errors/failure.dart';
import '../../domain/repositories/portal_context_repository.dart';

/// The only [PortalContextRepository] in this milestone.
///
/// It always reports [NotImplementedFailure], because the backend RPC it would
/// call — `public.get_my_portal_context()` — **does not exist**. The feature
/// matrix lists it as backend work item #1, "High — phase 1", still unbuilt at
/// the contract commit this repository is written against.
///
/// This class is deliberately not a stub that returns a plausible role. A stub
/// would let every screen downstream be written as though role resolution
/// worked, and the day the real RPC landed nobody would know which behaviour had
/// ever been verified. Failing honestly keeps the gap visible in the UI, in the
/// tests, and in this file's existence.
///
/// Replacing it is a self-contained change: implement [resolve] against the RPC,
/// map errors through `mapSupabaseError`, and register the new class in the
/// injector. Nothing else in the app needs to change.
final class UnimplementedPortalContextRepository
    implements PortalContextRepository {
  const UnimplementedPortalContextRepository();

  /// The missing backend object, named once so the developer-facing copy and
  /// the tests agree on it.
  static const String missingCapability = 'get_my_portal_context()';

  @override
  Future<PortalContextResult> resolve() async {
    return const PortalContextFailed(
      NotImplementedFailure(capability: missingCapability),
    );
  }
}
