import '../../../../core/errors/failure.dart';
import '../entities/app_role.dart';

/// The outcome of asking the backend "which experience is this caller in?".
sealed class PortalContextResult {
  const PortalContextResult();
}

/// The caller holds a supported role.
final class PortalContextResolved extends PortalContextResult {
  const PortalContextResolved(this.role);

  final ResolvedRole role;
}

/// The caller has a verified identity but qualifies for no supported
/// experience — `kind = 'none'`.
///
/// Distinct from a [PortalContextFailed] carrying [DeniedFailure]: this is a
/// successful read whose answer is "nothing", not a refused read.
final class PortalContextNone extends PortalContextResult {
  const PortalContextNone();
}

/// The read did not produce an answer. Fail closed: never treat this as a role.
final class PortalContextFailed extends PortalContextResult {
  const PortalContextFailed(this.failure);

  final Failure failure;
}

/// Resolves the caller's portal context from the backend.
///
/// The web application answers this question by probing up to three RPCs and
/// reading whether each threw `42501`. § 4.1 of the architecture recommendation
/// records why that must not be copied to a second client — authorization
/// decided by error handling is fragile across clients — and proposes a single
/// `public.get_my_portal_context()` returning one row:
///
/// ```
/// kind                     text  -- 'vendor'|'owner'|'reader'|'submitter'|'none'
/// retailer_organization_id uuid
/// retailer_name            text
/// ```
///
/// **That RPC does not exist yet.** The only implementation in this repository
/// is [UnimplementedPortalContextRepository], which says so rather than
/// guessing. Implementing this interface against a real RPC is the single change
/// that turns every role shell from a preview into a resolved experience.
///
/// Two rules for any future implementation, both inherited from the web client:
///
/// * **Never cache the result durably.** Roles change server-side; the web
///   client's cache is request-scoped for exactly this reason. Re-resolve on app
///   resume and on any `42501`.
/// * **Never decode the JWT locally to discover a role.** The answer comes from
///   an authenticated call, or it does not come at all.
abstract interface class PortalContextRepository {
  Future<PortalContextResult> resolve();
}
