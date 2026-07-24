import 'package:flutter/material.dart';

import '../../../features/auth/domain/entities/app_role.dart';
import '../../navigation/role_destination.dart';

/// The Vendor Super Admin navigation.
///
/// A SEPARATE list from every other role's, not a filtered view of a shared one.
/// Nothing here is importable into a Retailer shell without an obvious, reviewed
/// edit — which is the point.
///
/// The web sidebar carries six active modules (Dashboard, Retailers, Users,
/// Roles, Products, Audit Logs) plus a set of deliberately disabled "coming
/// soon" entries. The disabled entries are **not** carried over: they sketch a
/// roadmap to an internal audience on a wide screen, and they would be dead
/// weight in a mobile drawer.
///
/// Six destinations do not fit a bottom bar, so this role uses
/// [RoleShellChrome.drawer] — the closest mobile analogue of the dark sidebar it
/// replaces, keeping the same `--surface-nav` surface and brand lockup.
///
/// **Phase note.** The feature matrix places every Vendor feature in phase 3,
/// conditional on open question Q4 — whether Vendor administration belongs on
/// mobile at all. These destinations exist so the shell can be built and
/// reviewed; none of them is backed by an implemented screen.
abstract final class VendorNavigation {
  /// Every Vendor route lives under this prefix and no other role's does.
  static const String prefix = '/vendor';

  static const String dashboard = '$prefix/dashboard';
  static const String retailers = '$prefix/retailers';
  static const String users = '$prefix/users';
  static const String roles = '$prefix/roles';
  static const String products = '$prefix/products';
  static const String auditLogs = '$prefix/audit-logs';
  static const String profile = '$prefix/profile';

  static const List<RoleDestination> destinations = <RoleDestination>[
    RoleDestination(
      label: 'Dashboard',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      path: dashboard,
    ),
    RoleDestination(
      label: 'Retailers',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront_rounded,
      path: retailers,
    ),
    RoleDestination(
      label: 'Users',
      icon: Icons.group_outlined,
      selectedIcon: Icons.group_rounded,
      path: users,
    ),
    RoleDestination(
      label: 'Roles',
      icon: Icons.vpn_key_outlined,
      selectedIcon: Icons.vpn_key_rounded,
      path: roles,
    ),
    RoleDestination(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      path: products,
    ),
    RoleDestination(
      label: 'Audit logs',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      path: auditLogs,
    ),
    RoleDestination(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      path: profile,
    ),
  ];

  static const RoleNavigation model = RoleNavigation(
    role: AppRole.vendorSuperAdmin,
    routePrefix: prefix,
    landingPath: dashboard,
    chrome: RoleShellChrome.drawer,
    destinations: destinations,
  );
}
