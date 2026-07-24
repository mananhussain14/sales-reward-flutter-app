import '../../../../core/errors/failure.dart';
import '../entities/portal_context.dart';

/// The outcome of asking the backend "which experience is this caller in?".
///
/// Three outcomes, and the distinction between the last two is the whole point:
///
/// * [PortalContextResolved] — a context was read.
/// * [PortalContextDenied] — the backend answered `NONE`. A **decision**.
/// * [PortalContextFailed] — the call did not produce an answer. **Operational.**
///
/// The migration states the rule directly:
///
/// > `exception raised  -> "unavailable"  (operational; keep the session, retry)`
/// > `portal_kind NONE  -> "unauthorized" (a decision; send to access-denied)`
///
/// Collapsing a failure into a denial tells a user they lack access when the
/// database was merely unreachable, which is both wrong and alarming. Collapsing
/// a denial into a failure offers a retry that can never succeed.
sealed class PortalContextResult {
  const PortalContextResult();
}

/// The caller holds a supported experience.
final class PortalContextResolved extends PortalContextResult {
  const PortalContextResolved(this.context);

  final PortalContext context;
}

/// The backend answered `portal_kind: NONE`.
///
/// A successful read whose answer is "nothing" — not a refused read. The
/// context is carried so the caller can still see the version the backend
/// answered with.
final class PortalContextDenied extends PortalContextResult {
  const PortalContextDenied(this.context);

  final PortalContext context;
}

/// The read did not produce an answer: transport failure, a malformed body, or
/// a `context_version` this build does not understand.
///
/// Fail closed — never treat this as a role, and never as a denial.
final class PortalContextFailed extends PortalContextResult {
  const PortalContextFailed(this.failure);

  final Failure failure;
}

/// Resolves the caller's portal context from the backend.
///
/// Backed by exactly one authenticated call to `public.get_my_portal_context()`,
/// which takes **zero arguments**. There is no user id, organization id,
/// retailer id, membership id, role code, permission code, email or token
/// parameter — a caller cannot nominate whose authorization is evaluated, name a
/// tenant, or widen the answer.
///
/// Two rules for any implementation:
///
/// * **Never cache the result durably.** Roles change server-side. The web
///   client's cache is request-scoped for exactly this reason; this app
///   re-resolves whenever the authenticated user changes, and on retry.
/// * **Never decode the JWT locally to discover a role.** The answer comes from
///   an authenticated call, or it does not come at all.
abstract interface class PortalContextRepository {
  Future<PortalContextResult> resolve();
}
