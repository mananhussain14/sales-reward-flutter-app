import 'package:flutter/material.dart';

import '../../../features/auth/domain/entities/portal_kind.dart';
import '../../../features/auth/domain/entities/retailer_capabilities.dart';
import '../../navigation/role_destination.dart';

/// The Retailer Manager navigation.
///
/// A SEPARATE list from the Retailer Owner's, deliberately repeating two labels
/// rather than filtering the Owner's menu down. Were this
/// `ownerDestinations.where(...)`, an Owner-only entry added later would land in
/// a Manager's shell by default; here it cannot.
///
/// Matches § 5 of `docs/mobile-role-flow-map.md`: **Staff · Products**, in a
/// two-item bottom bar. The map notes that two destinations could arguably be an
/// app-bar-only layout, and recommends the bottom bar for consistency with the
/// Owner.
///
/// Overview, Shops and Receipts are all omitted because SQL refuses the Manager
/// on each — *"linking any of them would advertise dead ends."*
///
/// The Manager's roster read is narrowed to ACTIVE members only, and that
/// narrowing is a permission check **inside** `list_retailer_staff_members()` —
/// the same RPC the Owner calls. The map is emphatic that a Flutter client
/// *"needs no role logic at all here"*: render what came back.
///
/// **Open question Q3 / decision D-6.** A Manager cannot read their own
/// Retailer's name, because `get_retailer_owner_portal_context()` hard-filters
/// `RETAILER_OWNER`. The web omits the name rather than fabricating one; the
/// handoff notes the omission is *"much more visible"* on mobile, where the app
/// bar is a larger share of the screen. This shell therefore captions itself
/// with the portal name alone.
abstract final class RetailerManagerNavigation {
  /// Every Retailer Manager route lives under this prefix and no other role's
  /// does. See [RetailerOwnerNavigation.prefix] for why the two roles do not
  /// share the web's single `/retailer/*` tree.
  static const String prefix = '/retailer-manager';

  /// Web route `/retailer/staff`.
  static const String staff = '$prefix/staff';

  /// Web route `/retailer/products`.
  static const String products = '$prefix/products';

  static const List<RoleDestination> destinations = <RoleDestination>[
    RoleDestination(
      label: 'Staff',
      icon: Icons.group_outlined,
      selectedIcon: Icons.group_rounded,
      path: staff,
      requiredCapability: RetailerCapability.viewStaff,
    ),
    RoleDestination(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      path: products,
      requiredCapability: RetailerCapability.viewAssignedProducts,
    ),
  ];

  static const RoleNavigation model = RoleNavigation(
    role: PortalKind.retailerManager,
    routePrefix: prefix,
    portalName: 'Retailer Portal',
    // The roster is the only portal page a Manager may read in full. Sending
    // them to the overview instead would bounce them straight off it.
    landingPath: staff,
    chrome: RoleShellChrome.bottomBar,
    destinations: destinations,
  );
}
