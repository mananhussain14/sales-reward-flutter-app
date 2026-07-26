import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import 'vendor_dashboard_copy.dart';

/// One quick link: a label, an icon and the Vendor route it opens.
///
/// A record rather than a class — it holds no behaviour, and the list below is
/// the whole of what a quick link can be.
typedef _QuickLink = ({String label, IconData icon, SrTone tone, String path});

/// The shortcuts to the Vendor areas that exist.
///
/// **Five entries, and every one of them is a route that is built.** Retailers,
/// Users, Roles, Products and Audit Logs are the five implemented Vendor
/// destinations; Campaigns, Claims, Coins, Payouts, Reports and Settings are
/// "Soon" entries in the navigation model with no route at all, so there is
/// nothing here to link to and no disabled tile pretending otherwise. An
/// affordance that cannot act is a promise about a feature that has not been
/// built.
///
/// **No tile carries a figure.** The summary returns four counts and none of them
/// is a Retailer, Product, shop, assignment or invitation count — so a number on
/// any of these would be one this screen invented rather than one the backend
/// sent. They are links, and the section description says so.
class VendorDashboardQuickLinks extends StatelessWidget {
  const VendorDashboardQuickLinks({super.key});

  static const List<_QuickLink> _links = <_QuickLink>[
    (
      label: VendorDashboardCopy.retailersLink,
      icon: Icons.storefront_rounded,
      tone: SrTone.indigo,
      path: VendorNavigation.retailers,
    ),
    (
      label: VendorDashboardCopy.usersLink,
      icon: Icons.group_rounded,
      tone: SrTone.blue,
      path: VendorNavigation.users,
    ),
    (
      label: VendorDashboardCopy.rolesLink,
      icon: Icons.vpn_key_rounded,
      tone: SrTone.emerald,
      path: VendorNavigation.roles,
    ),
    (
      label: VendorDashboardCopy.productsLink,
      icon: Icons.inventory_2_rounded,
      tone: SrTone.amber,
      path: VendorNavigation.products,
    ),
    (
      label: VendorDashboardCopy.auditLogsLink,
      icon: Icons.receipt_long_rounded,
      tone: SrTone.slate,
      path: VendorNavigation.auditLogs,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SrCardGrid(
      children: <Widget>[
        for (final _QuickLink link in _links)
          Semantics(
            button: true,
            label: VendorDashboardCopy.quickLinkSemantics(link.label),
            excludeSemantics: true,
            child: SrShortcutCard(
              label: link.label,
              icon: link.icon,
              tone: link.tone,
              // `go`, not `push`: these are the shell's own top-level
              // destinations, so arriving at one should leave the browser history
              // and the back gesture exactly where the drawer would have left
              // them, rather than stacking a dashboard beneath a directory.
              onTap: () => context.go(link.path),
            ),
          ),
      ],
    );
  }
}
