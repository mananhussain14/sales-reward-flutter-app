import 'package:supabase_flutter/supabase_flutter.dart';

/// The name of the one RPC this feature calls.
///
/// Declared as a constant so a security review has a single, greppable place to
/// confirm the surface — and so the boundary test can assert that no other file
/// in `lib/` names it.
const String getMyLifecycleAccessStateRpc = 'get_my_lifecycle_access_state';

/// Invokes the lifecycle-access diagnostic and returns its raw body.
///
/// ## The signature is the security property
///
/// This typedef takes **no parameters**, and that is the entire point rather
/// than a convenience. The RPC accepts zero arguments — the subject is
/// `auth.uid()` and can only ever be `auth.uid()` — so modelling the call as a
/// nullary function makes it *impossible to express* an auth-user id, profile
/// id, membership id, organization id, role code, permission code, portal kind,
/// email or tenant selector at this boundary.
///
/// A function that accepted any of those would be a lookup service for other
/// people's lifecycle states wearing a self-service label. With no argument at
/// all there is nothing for a caller to substitute, no tenant to select, and no
/// id to sweep. There is no argument to pass, so there is no argument to get
/// wrong.
///
/// It also gives tests a seam that records the call without standing up a
/// `SupabaseClient`.
typedef LifecycleAccessInvoker = Future<Object?> Function();

/// The production invoker.
///
/// The only place in the application that names the RPC and touches the Supabase
/// client for it. Note the call site: a function name and nothing else — no
/// `params`, no `{}`, no `null` second argument.
///
/// The client is the ordinary injected one, carrying the caller's own token. A
/// service-role client is never used and would not work if it were: the backend
/// grants this function to `authenticated` and to nothing else, deliberately,
/// because a service-role connection has no `auth.uid()` and could only ever
/// describe nobody.
LifecycleAccessInvoker supabaseLifecycleAccessInvoker(SupabaseClient client) {
  return () => client.rpc<Object?>(getMyLifecycleAccessStateRpc);
}

/// Reads the caller's lifecycle access state from the backend.
///
/// Thin by design: it performs the call and lets exceptions propagate. Turning
/// an exception into a result is the repository's job and turning a body into a
/// domain value is the parser's, so each of the three has one reason to change.
final class LifecycleAccessRpcDataSource {
  const LifecycleAccessRpcDataSource(this._invoke);

  final LifecycleAccessInvoker _invoke;

  /// Throws whatever the transport throws. The only error the function itself
  /// raises is `42501` for an unauthenticated caller; everything else arriving
  /// here is operational.
  Future<Object?> fetch() => _invoke();
}
