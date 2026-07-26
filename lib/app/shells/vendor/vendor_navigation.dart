import 'package:flutter/material.dart';

import '../../../features/auth/domain/entities/portal_kind.dart';
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
/// **Phase note.** Five destinations are implemented. **Retailers** is backed
/// by `list_vendor_retailers()`, `get_vendor_retailer_detail(uuid)` and
/// `list_vendor_retailer_shops(uuid)` (`docs/flutter-vendor-retailer-reads.md`);
/// **Users** by `list_vendor_users()` and `get_vendor_user_detail(uuid)`
/// (`docs/flutter-vendor-user-reads.md`); **Roles** by `list_vendor_roles()`,
/// `get_vendor_role_detail(uuid)` and `list_vendor_role_permissions(uuid)`
/// (`docs/flutter-vendor-role-reads.md`); **Products** by
/// `list_vendor_products()`, `get_vendor_product_detail(uuid)` and
/// `list_vendor_product_assigned_retailers(uuid)`
/// (`docs/flutter-vendor-product-reads.md`); and **Audit Logs** by
/// `list_vendor_audit_logs(p_limit, p_before_occurred_at, p_before_audit_log_id)`
/// (`docs/flutter-vendor-audit-log-reads.md`), which is list-only — there is no
/// audit detail read to open. All five are read-only.
///
/// **Dashboard** remains a placeholder: `get_vendor_admin_dashboard_summary()`
/// is the one outstanding Vendor contract. Every other Vendor destination is
/// still phase 3 in the feature matrix and conditional on open question Q4 —
/// whether Vendor administration belongs on mobile at all — and none of them has
/// a mobile backend contract yet, so each renders a "Soon" entry.
abstract final class VendorNavigation {
  /// Every Vendor route lives under this prefix and no other role's does.
  static const String prefix = '/vendor';

  /// Web route `/`.
  static const String dashboard = '$prefix/dashboard';

  /// Web route `/retailers`.
  static const String retailers = '$prefix/retailers';

  /// The relative segment of the Retailer detail route.
  ///
  /// Nested under [retailers] so the two share a prefix, the shell keeps the
  /// Retailers destination highlighted while a Retailer is open
  /// (`indexForLocation` takes the longest matching prefix), and the back
  /// gesture pops to the directory rather than to the dashboard.
  static const String retailerDetailSegment = ':relationshipId';

  /// The full path for one Retailer, addressed by `vendor_retailers.id`.
  ///
  /// The same address the web detail route already carries, and the same id
  /// `list_vendor_retailers()` returns — so a link is portable between the two
  /// clients.
  ///
  /// > Holding this id grants nothing. Every read behind the route derives the
  /// > Vendor from `auth.uid()` in SQL and matches the row on **both** its own
  /// > id and that derived Vendor, so another Vendor's id reaches a screen that
  /// > says the Retailer is not available and nothing else.
  static String retailerDetailPath(String relationshipId) =>
      '$retailers/$relationshipId';

  /// Web route `/users`.
  static const String users = '$prefix/users';

  /// The relative segment of the Vendor user detail route.
  ///
  /// Nested under [users] for the same reasons the Retailer detail is nested
  /// under [retailers]: the shell keeps the Users destination highlighted while
  /// a user is open (`indexForLocation` takes the longest matching prefix), and
  /// the back gesture pops to the directory rather than to the dashboard.
  static const String userDetailSegment = ':membershipId';

  /// The full path for one Vendor user, addressed by `organization_members.id`.
  ///
  /// The membership id and not the profile id: a membership row names one person
  /// **in one organization**, so scoping it to the caller's Vendor is a predicate
  /// on the same row. A profile id names a person globally and would have to be
  /// narrowed back down before it could be authorized; an auth user id is the
  /// token subject and the contract neither returns nor accepts it.
  ///
  /// > Holding this id grants nothing. The read behind the route derives the
  /// > Vendor from `auth.uid()` in SQL and matches the row on **both** its own id
  /// > and that derived Vendor, so another Vendor's id — or a Retailer's — reaches
  /// > a screen that says the user is not available and nothing else.
  static String userDetailPath(String membershipId) => '$users/$membershipId';

  /// Web route `/roles`.
  static const String roles = '$prefix/roles';

  /// The relative segment of the role detail route.
  ///
  /// Nested under [roles] for the same reasons the Retailer and user details are
  /// nested under theirs: the shell keeps the Roles destination highlighted while
  /// a role is open (`indexForLocation` takes the longest matching prefix), and
  /// the back gesture pops to the catalogue rather than to the dashboard.
  static const String roleDetailSegment = ':roleId';

  /// The full path for one role definition, addressed by `roles.id`.
  ///
  /// The id and never the code. `roles.code` is `UNIQUE` and would address a
  /// role just as precisely, which is exactly why the backend refuses it: the
  /// codes are the literals the RLS policies and the authorization helpers match
  /// on, and putting one in a URL would put authorization vocabulary in a
  /// client's hands. The uuid is opaque, is what the list already returned, and
  /// means nothing anywhere else.
  ///
  /// > Holding this id grants nothing. The reads behind the route derive the
  /// > Vendor from `auth.uid()` in SQL and use the id only to select which
  /// > already-authorized catalogue row is read, so an id that names no role
  /// > reaches a screen that says the role is not available and nothing else.
  static String roleDetailPath(String roleId) => '$roles/$roleId';

  /// Web route `/products`.
  static const String products = '$prefix/products';

  /// The relative segment of the product detail route.
  ///
  /// Nested under [products] for the same reasons the Retailer, user and role
  /// details are nested under theirs: the shell keeps the Products destination
  /// highlighted while a product is open (`indexForLocation` takes the longest
  /// matching prefix), and the back gesture pops to the catalogue rather than to
  /// the dashboard.
  static const String productDetailSegment = ':productId';

  /// The full path for one product, addressed by `vendor_products.id`.
  ///
  /// The id and never the product code. The code is unique **per Vendor**
  /// (`vendor_products_code_unique_idx (vendor_organization_id, product_code)`),
  /// so two Vendors may each own `A-100` and a code in a URL would not name one
  /// row without a tenant beside it — which is exactly the tenant input this
  /// contract refuses. The uuid names one Vendor's own row and nothing else.
  ///
  /// > Holding this id grants nothing. `vendor_products.vendor_organization_id`
  /// > is `NOT NULL` and immutable by trigger, and both reads behind this route
  /// > derive the Vendor from `auth.uid()` in SQL and match the row on **both**
  /// > its own id and that derived Vendor — so another Vendor's id reaches a
  /// > screen that says the product is not available and nothing else.
  static String productDetailPath(String productId) => '$products/$productId';

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
    role: PortalKind.vendorSuperAdmin,
    routePrefix: prefix,
    portalName: 'Vendor Admin',
    landingPath: dashboard,
    chrome: RoleShellChrome.drawer,
    destinations: destinations,
  );
}
