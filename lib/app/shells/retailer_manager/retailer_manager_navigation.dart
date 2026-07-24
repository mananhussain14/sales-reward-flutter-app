import 'package:flutter/material.dart';

import '../../../features/auth/domain/entities/app_role.dart';
import '../../navigation/role_destination.dart';

/// The Retailer Manager navigation.
///
/// A SEPARATE list from the Retailer Owner's, deliberately duplicating two
/// labels rather than filtering the Owner's menu down. If this were
/// `ownerDestinations.where(...)`, an Owner-only entry added later would land in
/// a Manager's shell by default; here it cannot.
///
/// Matches § 4.2 of the architecture recommendation: **Staff · Products ·
/// Profile.**
///
/// Overview and Shops are absent because both are backed by
/// `get_retailer_owner_portal_context()` and `list_retailer_owner_portal_shops()`,
/// whose resolver requires the `RETAILER_OWNER` role — a Manager would be
/// refused by SQL. Receipts is absent for the same reason it is absent from the
/// Owner's menu. Linking any of them would advertise a dead end.
///
/// The Manager's read of the staff roster is narrowed to ACTIVE members only,
/// and that narrowing is a permission check **inside** the RPC — the same
/// `list_retailer_staff_members()` an Owner calls. It is never re-implemented on
/// the client.
///
/// **Open question Q3.** A Retailer Manager currently has no way to read their
/// own Retailer's name, because `get_retailer_owner_portal_context()` hard-filters
/// `RETAILER_OWNER`. Until `get_my_portal_context()` exists, this shell cannot
/// caption itself with the tenant it belongs to.
abstract final class RetailerManagerNavigation {
  /// Every Retailer Manager route lives under this prefix and no other role's
  /// does.
  static const String prefix = '/retailer-manager';

  static const String staff = '$prefix/staff';
  static const String products = '$prefix/products';
  static const String profile = '$prefix/profile';

  static const List<RoleDestination> destinations = <RoleDestination>[
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
    role: AppRole.retailerManager,
    routePrefix: prefix,
    landingPath: staff,
    chrome: RoleShellChrome.bottomBar,
    destinations: destinations,
  );
}
