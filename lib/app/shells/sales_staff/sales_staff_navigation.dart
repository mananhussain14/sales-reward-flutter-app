import 'package:flutter/material.dart';

import '../../../features/auth/domain/entities/app_role.dart';
import '../../navigation/role_destination.dart';

/// The Sales Staff navigation.
///
/// A SEPARATE list from every other role's. This is the narrowest shell in the
/// product and the one most likely to run on a shared shop-floor device, so it
/// must not be able to inherit an entry from anywhere else.
///
/// Matches § 4.2 of the architecture recommendation: **Submit · History ·
/// Profile.**
///
/// The web portal offers Sales Staff a single "Receipts" page. Mobile splits it
/// in two, because capture is the reason this role opens the app and it deserves
/// to be one tap away rather than a section of a list screen. Both halves are
/// still backed by the same two operations — `reserve_receipt_submission()`
/// through the `submit-receipt` Edge Function, and
/// `list_my_receipt_submissions()`.
///
/// Nothing else appears here. A Sales Staff member holds neither
/// `RETAILER_PORTAL_READ` nor `RETAILER_STAFF_READ` nor
/// `RETAILER_PRODUCTS_READ`, so Overview, Shops, Staff and Products are all
/// refused to them in SQL, and none is offered here.
abstract final class SalesStaffNavigation {
  /// Every Sales Staff route lives under this prefix and no other role's does.
  static const String prefix = '/sales-staff';

  static const String submit = '$prefix/submit';
  static const String history = '$prefix/history';
  static const String profile = '$prefix/profile';

  static const List<RoleDestination> destinations = <RoleDestination>[
    RoleDestination(
      label: 'Submit',
      icon: Icons.photo_camera_outlined,
      selectedIcon: Icons.photo_camera_rounded,
      path: submit,
    ),
    RoleDestination(
      label: 'History',
      icon: Icons.history_rounded,
      selectedIcon: Icons.history_rounded,
      path: history,
    ),
    RoleDestination(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      path: profile,
    ),
  ];

  static const RoleNavigation model = RoleNavigation(
    role: AppRole.salesStaff,
    routePrefix: prefix,
    landingPath: submit,
    chrome: RoleShellChrome.bottomBar,
    destinations: destinations,
  );
}
