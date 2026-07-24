import 'package:flutter/material.dart';

import '../../../features/auth/domain/entities/app_role.dart';
import '../../navigation/role_destination.dart';

/// The Retailer Owner navigation.
///
/// A SEPARATE list from every other role's — including the Retailer Manager's,
/// which overlaps with it. The two roles are not a superset and a subset of one
/// menu; they are two menus that happen to share two labels.
///
/// Matches § 4.2 of the architecture recommendation:
/// **Overview · Shops · Staff · Products · Profile.**
///
/// Two deliberate omissions, both taken from the web portal's own reasoning:
///
/// * **No Receipts.** `RECEIPT_SUBMIT` is mapped to `SALES_STAFF` alone, so
///   every receipt RPC would refuse an Owner. Offering the entry would advertise
///   a capability the database will not grant.
/// * **Products is the read-only assigned list.** Managing the catalogue is a
///   Vendor capability on an entirely different surface.
abstract final class RetailerOwnerNavigation {
  /// Every Retailer Owner route lives under this prefix and no other role's does.
  static const String prefix = '/retailer-owner';

  static const String overview = '$prefix/overview';
  static const String shops = '$prefix/shops';
  static const String staff = '$prefix/staff';
  static const String products = '$prefix/products';
  static const String profile = '$prefix/profile';

  static const List<RoleDestination> destinations = <RoleDestination>[
    RoleDestination(
      label: 'Overview',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      path: overview,
    ),
    RoleDestination(
      label: 'Shops',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront_rounded,
      path: shops,
    ),
    RoleDestination(
      label: 'Staff',
      icon: Icons.group_outlined,
      selectedIcon: Icons.group_rounded,
      path: staff,
    ),
    RoleDestination(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      path: products,
    ),
    RoleDestination(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      path: profile,
    ),
  ];

  static const RoleNavigation model = RoleNavigation(
    role: AppRole.retailerOwner,
    routePrefix: prefix,
    landingPath: overview,
    chrome: RoleShellChrome.bottomBar,
    destinations: destinations,
  );
}
