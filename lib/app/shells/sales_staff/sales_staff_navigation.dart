import 'package:flutter/material.dart';

import '../../../features/auth/domain/entities/portal_kind.dart';
import '../../../features/auth/domain/entities/retailer_capabilities.dart';
import '../../navigation/role_destination.dart';

/// The Sales Staff navigation.
///
/// A SEPARATE list from every other role's. This is the narrowest shell in the
/// product, the first milestone's target, and the one most likely to run on a
/// shared shop-floor device — so it must not be able to inherit an entry from
/// anywhere else.
///
/// **Submit · History**, in a concise two-item bottom bar.
///
/// ## A recorded deviation from § 4.1 of the design handoff
///
/// The handoff and § 6 of the role-flow map both count Sales Staff as **one**
/// destination (`/retailer/receipts`) and recommend *no navigation chrome at
/// all*, on the grounds that a single-tab bar is noise.
///
/// This shell ships two tabs instead, for two reasons:
///
/// 1. **The web's single Receipts page is already two things.** § 5.11 describes
///    it as a "Submit a receipt" card stacked above a "Your submissions" history
///    card. Splitting one long scroll into two tabs is the ordinary mobile
///    transformation of that page, and it is what
///    `mobile-architecture-recommendation.md` § 4.2 independently proposed.
/// 2. **It keeps the primary action one tap away.** Submit is the landing tab
///    and never scrolls out of reach behind a history list — which is the whole
///    point for a role whose entire experience is a write flow.
///
/// Two entries is the same count the map already accepts as a bottom bar for the
/// Retailer Manager. This resolves decision **D-4** for this role; the mechanics
/// change, no colour, icon or label does.
///
/// Nothing else appears here. A Sales Staff member holds `RECEIPT_SUBMIT` and
/// nothing else — no `RETAILER_PORTAL_READ`, no `RETAILER_STAFF_READ`, no
/// `RETAILER_PRODUCTS_READ` — so Overview, Shops, Staff and Products are all
/// refused in SQL, and none is offered.
abstract final class SalesStaffNavigation {
  /// Every Sales Staff route lives under this prefix and no other role's does.
  static const String prefix = '/sales-staff';

  /// Web route `/retailer/receipts`, upper half.
  static const String submit = '$prefix/submit';

  /// Web route `/retailer/receipts`, lower half.
  static const String history = '$prefix/history';

  /// The relative segment of the receipt review route.
  ///
  /// Nested under [history] rather than sitting beside it, for the same reason
  /// every Vendor detail route is nested under its list: `indexForLocation`
  /// matches on the longest prefix, so the History destination stays
  /// highlighted while a single receipt is open, and Back has an obvious place
  /// to return to.
  static const String reviewSegment = ':submissionId';

  /// The review route for one submitted receipt.
  ///
  /// The submission id is the **only** thing this address carries. There is no
  /// extraction id, shop, organization or profile in it: every one of those is
  /// resolved in SQL from `auth.uid()`, and an id in a URL is a value a person
  /// can edit. Reaching another person's receipt this way is refused by
  /// `assert_my_receipt_extraction_access`, not by this path.
  static String review(String submissionId) => '$history/$submissionId';

  /// The campaigns running now or starting soon for this seller's Retailer.
  ///
  /// Backed by `list_my_staff_campaigns()`, which takes zero arguments and
  /// resolves through
  /// `resolve_retailer_member_organization('STAFF_CAMPAIGNS_VIEW')` — a
  /// **separate** permission from the Retailer Owner's, mapped to `SALES_STAFF`
  /// alone, returning fewer columns and only `ACTIVE`/`SCHEDULED` campaigns.
  ///
  /// It has no Web counterpart. There is no Sales Staff campaign surface on the
  /// Web at all; the contract was written for this client.
  static const String campaigns = '$prefix/campaigns';

  /// The relative segment of the campaign detail route. Nested under
  /// [campaigns] so the destination stays highlighted while one is open.
  static const String campaignDetailSegment = ':campaignId';

  /// The detail route for one campaign.
  ///
  /// The campaign id is the only thing this address carries — no Retailer, no
  /// shop, no profile, no submission. `get_my_staff_campaign()` re-derives the
  /// caller's Retailer from `auth.uid()` and re-applies the `ACTIVE`/`SCHEDULED`
  /// filter, so an id naming another Retailer's campaign, or one that has since
  /// been paused, returns zero rows.
  static String campaignDetail(String campaignId) => '$campaigns/$campaignId';

  static const List<RoleDestination> destinations = <RoleDestination>[
    RoleDestination(
      label: 'Submit',
      icon: Icons.photo_camera_outlined,
      selectedIcon: Icons.photo_camera_rounded,
      path: submit,
      requiredCapability: RetailerCapability.submitReceipts,
    ),
    RoleDestination(
      label: 'History',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      path: history,
    ),
    // Third and last. Submit stays the landing tab, so the primary action is
    // still one tap away — the reason this shell has a bottom bar at all.
    //
    // No `requiredCapability`: the portal context returns no campaign flag for
    // either role. See the equivalent note in `RetailerOwnerNavigation`.
    RoleDestination(
      label: 'Campaigns',
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign_rounded,
      path: campaigns,
    ),
  ];

  static const RoleNavigation model = RoleNavigation(
    role: PortalKind.salesStaff,
    routePrefix: prefix,
    portalName: 'Retailer Portal',
    landingPath: submit,
    chrome: RoleShellChrome.bottomBar,
    destinations: destinations,
  );
}
