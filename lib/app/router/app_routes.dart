/// The routes that belong to no single role.
///
/// Every other path lives under a role prefix declared in that role's own
/// navigation file. Keeping the shared routes here, and the role routes there,
/// means adding a screen to a role never involves editing a file another role
/// also reads.
abstract final class AppRoutes {
  /// The entry point. A splash shown only while the session is being resolved;
  /// the router redirects away from it the moment the answer is known.
  static const String splash = '/';

  /// The sign-in screen. The one destination for a caller with no session.
  static const String login = '/login';

  /// The shared, role-neutral denial screen. Where a `portal_kind: NONE`
  /// caller, or a caller who wandered into the wrong role group, is sent.
  static const String accessDenied = '/access-denied';

  /// The retry screen for an operational failure — the RPC threw, or the body
  /// could not be parsed. Distinct from [accessDenied] on purpose.
  static const String unavailable = '/unavailable';
}
