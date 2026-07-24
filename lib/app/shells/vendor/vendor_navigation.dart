import 'package:flutter/material.dart';

import '../../../features/auth/domain/entities/app_role.dart';
import '../../navigation/role_destination.dart';

/// The Vendor Super Admin navigation.
///
/// A SEPARATE list from every other role's, not a filtered view of a shared one.
///
/// Matches § 3 of `docs/mobile-role-flow-map.md`: **six active destinations plus
/// six deliberate "Coming soon" placeholders**, presented in a drawer.
///
/// The placeholders are kept on purpose. The role-flow map is explicit:
///
/// > *The placeholders sketch a roadmap to an internal audience and should be
/// > kept; the Retailer portal has none by design, because advertising unbuilt
/// > modules to an external customer sets an expectation this milestone cannot
/// > meet.*
///
/// Twelve entries cannot fit a bottom bar, which is why this role — and only
/// this role — uses [RoleShellChrome.drawer].
///
/// **Phase note.** Every Vendor feature is phase 3 in the feature matrix and
/// conditional on open question Q4 — whether Vendor administration belongs on
/// mobile at all. These destinations exist so the shell can be built and
/// reviewed; none is backed by an implemented screen.
abstract final class VendorNavigation {
  /// Every Vendor route lives under this prefix and no other role's does.
  static const String prefix = '/vendor';

  /// Web route `/`.
  static const String dashboard = '$prefix/dashboard';

  /// Web route `/retailers`.
  static const String retailers = '$prefix/retailers';

  /// Web route `/users`.
  static const String users = '$prefix/users';

  /// Web route `/roles`.
  static const String roles = '$prefix/roles';

  /// Web route `/products`.
  static const String products = '$prefix/products';

  /// Web route `/audit-logs`.
  static const String auditLogs = '$prefix/audit-logs';

  static const List<RoleDestination> destinations = <RoleDestination>[
    RoleDestination(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
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
      label: 'Audit Logs',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      path: auditLogs,
    ),

    // The six roadmap placeholders, in the web's order.
    RoleDestination.soon(
      label: 'Campaigns',
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign_rounded,
    ),
    RoleDestination.soon(
      label: 'Claims',
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment_rounded,
    ),
    RoleDestination.soon(
      label: 'Coins',
      icon: Icons.monetization_on_outlined,
      selectedIcon: Icons.monetization_on_rounded,
    ),
    RoleDestination.soon(
      label: 'Payouts',
      icon: Icons.payments_outlined,
      selectedIcon: Icons.payments_rounded,
    ),
    RoleDestination.soon(
      label: 'Reports',
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart_rounded,
    ),
    RoleDestination.soon(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];

  static const RoleNavigation model = RoleNavigation(
    role: AppRole.vendorSuperAdmin,
    routePrefix: prefix,
    portalName: 'Vendor Admin',
    landingPath: dashboard,
    chrome: RoleShellChrome.drawer,
    destinations: destinations,
  );
}
