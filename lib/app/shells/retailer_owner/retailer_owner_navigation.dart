import 'package:flutter/material.dart';

import '../../../features/auth/domain/entities/portal_kind.dart';
import '../../../features/auth/domain/entities/retailer_capabilities.dart';
import '../../navigation/role_destination.dart';

/// The Retailer Owner navigation.
///
/// A SEPARATE list from every other role's — including the Retailer Manager's,
/// which overlaps with it. The two roles are not a superset and a subset of one
/// menu; they are two menus that happen to share two labels.
///
/// Matches § 4 of `docs/mobile-role-flow-map.md`: **Overview · Shops · Staff ·
/// Products**, in a bottom navigation bar.
///
/// Two deliberate omissions, both taken from the map's own reasoning:
///
/// * **Receipts is absent.** `RECEIPT_SUBMIT` is mapped to `SALES_STAFF` alone,
///   so every receipt RPC refuses an Owner. The map calls showing it *"exactly
///   the 'Owner navigation accidentally exposes a Sales-Staff-only action'
///   mistake this milestone must avoid"*, and says plainly: do not add it.
/// * **Products is the read-only assigned list.** Managing the catalogue is a
///   Vendor capability on a different surface entirely.
///
/// There is no Profile entry: the web has no profile screen at all, and the
/// account surface is a sheet from the app bar (decision D-5).
abstract final class RetailerOwnerNavigation {
  /// Every Retailer Owner route lives under this prefix and no other role's
  /// does.
  ///
  /// The web serves the Owner and the Manager from the *same* `/retailer/*`
  /// routes and separates them by server-side checks. Mobile gives each role
  /// its own prefix instead, so that "can this role reach that screen?" is
  /// answerable from the route tree alone — and so a shell can never be built
  /// for the wrong role.
  static const String prefix = '/retailer-owner';

  /// Web route `/retailer`.
  static const String overview = '$prefix/overview';

  /// Web route `/retailer/shops`.
  static const String shops = '$prefix/shops';

  /// Web route `/retailer/staff`.
  static const String staff = '$prefix/staff';

  /// Web route `/retailer/products`.
  static const String products = '$prefix/products';

  static const List<RoleDestination> destinations = <RoleDestination>[
    RoleDestination(
      label: 'Overview',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      path: overview,
      requiredCapability: RetailerCapability.viewRetailerOverview,
    ),
    RoleDestination(
      label: 'Shops',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront_rounded,
      path: shops,
      requiredCapability: RetailerCapability.viewShops,
    ),
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
    role: PortalKind.retailerOwner,
    routePrefix: prefix,
    portalName: 'Retailer Portal',
    landingPath: overview,
    chrome: RoleShellChrome.bottomBar,
    destinations: destinations,
  );
}
