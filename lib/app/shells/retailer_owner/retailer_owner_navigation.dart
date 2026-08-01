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

  /// Web route `/retailer/campaigns`.
  ///
  /// Backed by `list_my_retailer_campaigns()`, which takes zero arguments and
  /// resolves through
  /// `resolve_retailer_member_organization('CAMPAIGNS_VIEW_ASSIGNED')` — a
  /// permission mapped to `RETAILER_OWNER` alone. The Retailer Manager has no
  /// equivalent destination and no equivalent route, because that resolver
  /// refuses them with `42501`.
  static const String campaigns = '$prefix/campaigns';

  /// The relative segment of the campaign detail route.
  ///
  /// Nested under [campaigns] rather than sitting beside it, for the same
  /// reason every Vendor detail route is nested under its list:
  /// `indexForLocation` matches on the longest prefix, so the Campaigns
  /// destination stays highlighted while one campaign is open, and Back has an
  /// obvious place to return to.
  static const String campaignDetailSegment = ':campaignId';

  /// The detail route for one campaign.
  ///
  /// The campaign id is the **only** thing this address carries. There is no
  /// organization, Vendor, version, snapshot or profile in it: every one of
  /// those is resolved in SQL from `auth.uid()`, and an id in a route is a value
  /// a person can edit. Reaching another Retailer's campaign this way returns
  /// zero rows from `get_my_retailer_campaign()`, not a different screen.
  static String campaignDetail(String campaignId) => '$campaigns/$campaignId';

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
    // No `requiredCapability`, because the backend returns no flag for this
    // one. `get_retailer_owner_portal_context()` predates the campaign
    // contracts and its `capabilities` block was deliberately **not** widened
    // when they shipped — so there is nothing to read, and inventing a hint
    // from a role name would be exactly the client-side authorization this
    // codebase refuses everywhere else.
    //
    // Always showing it is the safe direction. Navigation is not authorization:
    // if `CAMPAIGNS_VIEW_ASSIGNED` is ever unmapped from `RETAILER_OWNER`, the
    // RPC raises `42501` and the screen renders the shared denial view. A
    // hidden entry would have granted nothing either.
    RoleDestination(
      label: 'Campaigns',
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign_rounded,
      path: campaigns,
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
