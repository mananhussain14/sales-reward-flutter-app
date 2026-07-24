import 'package:supabase_flutter/supabase_flutter.dart';

/// The name of the one RPC this feature calls.
const String getMyPortalContextRpc = 'get_my_portal_context';

/// Invokes the portal-context RPC and returns its raw body.
///
/// ## The signature is the security property
///
/// This typedef takes **no parameters**, and that is deliberate. The RPC accepts
/// zero arguments — identity comes from `auth.uid()` and from nothing else — so
/// modelling the call as a nullary function makes it *impossible to express* a
/// user id, organization id, retailer id, membership id, role code, permission
/// code, email or token at this boundary. There is no argument to pass, so there
/// is no argument to get wrong.
///
/// It also gives tests a seam that records the call without standing up a
/// `SupabaseClient`.
typedef PortalContextInvoker = Future<Object?> Function();

/// The production invoker.
///
/// The only place in the application that names the RPC and touches the
/// Supabase client for it. Note the call site: a function name and nothing else.
PortalContextInvoker supabasePortalContextInvoker(SupabaseClient client) {
  return () => client.rpc<Object?>(getMyPortalContextRpc);
}

/// Reads the caller's portal context from the backend.
///
/// Thin by design: it performs the call and lets exceptions propagate. Turning
/// an exception into a [Failure] is the repository's job, and turning a body
/// into a domain object is the parser's, so each of the three has one reason to
/// change.
final class PortalContextDataSource {
  const PortalContextDataSource(this._invoke);

  final PortalContextInvoker _invoke;

  /// Throws whatever the transport throws. The contract guarantees the function
  /// itself raises nothing and never returns SQL NULL, so an exception here is
  /// genuinely operational.
  Future<Object?> fetch() => _invoke();
}
