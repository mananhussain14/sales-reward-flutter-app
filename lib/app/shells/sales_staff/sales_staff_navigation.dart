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
/// **Home · Submit · History · Campaigns · Earnings**, in a five-item bottom bar
/// — the upper end of the two-to-five range [RoleShellChrome.bottomBar] is for.
///
/// ## Why a Home destination was added, and why it landed first
///
/// Until the experience redesign this shell landed directly on the submission
/// form, and that was the right call while the form was the only thing a seller
/// could do. It is no longer: `get_my_campaign_earnings_summary()`,
/// `list_my_staff_campaigns()` and `get_my_campaign_target_progress()` now say
/// what a seller has earned, what is running and how far along a target is —
/// and none of that has anywhere to live on a screen whose whole job is
/// choosing a file.
///
/// The redesign asks for a landing screen that answers "what should I do next?"
/// **and** a prominent action that *opens* the submission flow. Those are two
/// screens by definition: a call to action cannot open the screen it is on. So
/// [home] is the landing and [submit] keeps its route, its cubits, its tests and
/// its place in the bar — nothing was moved, one destination was added in front.
///
/// This is a recorded deviation from the previous milestone's "Submit is the
/// landing tab" decision. The primary action is still one tap away: it is a tab
/// **and** the sticky call to action on the landing screen.
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

  /// The seller's own landing screen, and the only surface in this application
  /// that composes more than one contract.
  ///
  /// It reads four things this shell already holds — the earnings summary, the
  /// campaign list, the target progress and the recent submissions — and issues
  /// no request of its own. There is no home RPC, no dashboard contract and no
  /// aggregate: every figure on it comes from a read that already had a screen.
  ///
  /// It has no Web counterpart. There is no Sales Staff surface on the Web at
  /// all.
  static const String home = '$prefix/home';

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

  /// What this seller has actually earned from those campaigns.
  ///
  /// Backed by `get_my_campaign_earnings_summary()` and
  /// `get_my_campaign_rewards()`, both of which resolve through
  /// `sales_staff_earnings_profile()` — a **separate** permission from the
  /// campaign reads, `STAFF_EARNINGS_VIEW`, mapped to `SALES_STAFF` alone.
  /// *"Seeing which campaigns are running is a different question from seeing
  /// what you personally earned."*
  ///
  /// No route beneath it, and none to add: the contract returns no verified sale
  /// id, and there is no authorized Sales Staff route that opens a receipt from
  /// a reward.
  static const String earnings = '$prefix/earnings';

  static const List<RoleDestination> destinations = <RoleDestination>[
    // First, and the landing. No `requiredCapability`: this screen is a
    // composition of reads that each carry their own refusal, and hiding it
    // would leave a seller with no way back to the rest of the shell.
    RoleDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      path: home,
    ),
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
    // Fourth. Submit is no longer the landing tab, but it is still one tap
    // away — and it is also the sticky call to action on the landing screen.
    //
    // No `requiredCapability`: the portal context returns no campaign flag for
    // either role. See the equivalent note in `RetailerOwnerNavigation`.
    RoleDestination(
      label: 'Campaigns',
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign_rounded,
      path: campaigns,
    ),
    // Fifth and last, which is the most a bottom bar carries.
    //
    // ## A recorded deviation on the LABEL, and only the label
    //
    // The milestone names this destination "My campaign earnings". A bottom-bar
    // label is rendered under an icon in a quarter of a phone's width, at the
    // reader's own text scale — three words there either ellipsise to
    // "My camp…" or force every other tab to shrink with them, and both are
    // worse than a shorter word that means the same thing.
    //
    // So the visible label is "Earnings" and the specified name is carried
    // where it has room: the screen's own title, its header, and the accessible
    // announcement of the page. Nothing about what the destination reaches
    // changes.
    //
    // No `requiredCapability`, for the same reason as Campaigns: the portal
    // context returns no earnings flag, and navigation is not authorization —
    // `STAFF_EARNINGS_VIEW` is re-decided in SQL on every one of the three
    // reads behind this screen.
    RoleDestination(
      label: 'Earnings',
      icon: Icons.savings_outlined,
      selectedIcon: Icons.savings_rounded,
      path: earnings,
    ),
  ];

  /// Declared here, in this role's own file, and nowhere else.
  ///
  /// The caption reads **"Sales Staff Portal"**, not "Retailer Portal". A seller
  /// signs in on a shared shop-floor device and needs the header to say which
  /// portal is open; "Retailer Portal" is the Retailer Owner's and Manager's
  /// caption and reads, on this shell, as though the wrong account is signed in.
  /// The app bar's *title* is still the organization name the backend supplied —
  /// only this caption names the portal.
  static const RoleNavigation model = RoleNavigation(
    role: PortalKind.salesStaff,
    routePrefix: prefix,
    portalName: 'Sales Staff Portal',
    landingPath: home,
    chrome: RoleShellChrome.bottomBar,
    destinations: destinations,
  );
}
