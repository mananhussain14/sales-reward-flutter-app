import 'package:flutter/material.dart';

import '../../../features/auth/domain/entities/app_role.dart';
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

  static const List<RoleDestination> destinations = <RoleDestination>[
    RoleDestination(
      label: 'Submit',
      icon: Icons.photo_camera_outlined,
      selectedIcon: Icons.photo_camera_rounded,
      path: submit,
    ),
    RoleDestination(
      label: 'History',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      path: history,
    ),
  ];

  static const RoleNavigation model = RoleNavigation(
    role: AppRole.salesStaff,
    routePrefix: prefix,
    portalName: 'Retailer Portal',
    landingPath: submit,
    chrome: RoleShellChrome.bottomBar,
    destinations: destinations,
  );
}
