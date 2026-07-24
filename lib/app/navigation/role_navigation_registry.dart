import '../../features/auth/domain/entities/portal_kind.dart';
import '../shells/retailer_manager/retailer_manager_navigation.dart';
import '../shells/retailer_owner/retailer_owner_navigation.dart';
import '../shells/sales_staff/sales_staff_navigation.dart';
import '../shells/vendor/vendor_navigation.dart';
import 'role_destination.dart';

/// Looks up a role's navigation model.
///
/// This is a **lookup, not a filter**. Each model is declared in full next to
/// its own shell; nothing here derives one role's menu from another's. The
/// registry exists so the router can ask "which shell and which landing?"
/// without importing four files, and it is the one place that knows all four
/// exist.
///
/// ## Landing precedence
///
/// The web application's `lib/auth/landing-decision.ts` establishes **vendor-first
/// precedence**: a user holding both a Vendor and a Retailer role lands on the
/// Vendor experience, with the Retailer one reachable directly. Two different
/// precedence orders across clients would be a support nightmare, so mobile
/// inherits it.
///
/// That precedence is *not implemented here*, and cannot be, because it is
/// applied by whatever resolves the role — the proposed
/// `public.get_my_portal_context()`, which folds the whole rule into one row and
/// one round trip. This registry receives a single already-decided [PortalKind].
/// The ordering of [ordered] below records the intended precedence for whoever
/// implements that resolver.
abstract final class RoleNavigationRegistry {
  /// The four models in **vendor-first precedence order**, matching the web's
  /// `selectLanding`. Recorded here so the rule has one written home on the
  /// mobile side; it is applied by the backend resolver, not by this list.
  static const List<RoleNavigation> ordered = <RoleNavigation>[
    VendorNavigation.model,
    RetailerOwnerNavigation.model,
    RetailerManagerNavigation.model,
    SalesStaffNavigation.model,
  ];

  /// The navigation model for [role], or null for [PortalKind.none], which has
  /// no shell.
  static RoleNavigation? forRole(PortalKind role) => switch (role) {
    PortalKind.vendorSuperAdmin => VendorNavigation.model,
    PortalKind.retailerOwner => RetailerOwnerNavigation.model,
    PortalKind.retailerManager => RetailerManagerNavigation.model,
    PortalKind.salesStaff => SalesStaffNavigation.model,
    PortalKind.none => null,
  };

  /// The role that owns [location], or null if no role does.
  ///
  /// Used by the route guard to decide whether the current role is allowed to
  /// be where the router is about to take it.
  static PortalKind? roleOwning(String location) {
    for (final RoleNavigation navigation in ordered) {
      if (navigation.owns(location)) {
        return navigation.role;
      }
    }
    return null;
  }

  /// Where [role] lands after resolution, or null for [PortalKind.none].
  static String? landingPathFor(PortalKind role) => forRole(role)?.landingPath;
}
