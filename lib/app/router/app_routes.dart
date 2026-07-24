/// The routes that belong to no role.
///
/// Every other path in the application lives under a role prefix, declared in
/// that role's own navigation file — [VendorNavigation.prefix],
/// [RetailerOwnerNavigation.prefix], [RetailerManagerNavigation.prefix],
/// [SalesStaffNavigation.prefix].
///
/// Keeping the shared routes here, and the role routes there, means adding a
/// screen to a role never involves editing a file another role also reads.
abstract final class AppRoutes {
  /// The entry point: resolve the role, then redirect to its landing path.
  static const String roleGate = '/';

  /// The shared, role-neutral denial screen. Reachable from any state, and
  /// never guarded — it is where the guard sends people.
  static const String accessDenied = '/access-denied';
}
