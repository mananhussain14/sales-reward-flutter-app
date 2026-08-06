import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import 'sales_staff_home_copy.dart';

/// The greeting at the top of the Sales Staff home.
///
/// ## Compact, because the screen below it is the point
///
/// The first version gave this a 24px title, a subtitle, an encouraging line
/// and — on a phone — a button, which pushed the actual opportunity below the
/// fold. It is now **one row**: an avatar, "Welcome back", and the Retailer.
/// The encouraging line moved onto the hero, where it can be about a real
/// campaign instead of about nothing in particular.
///
/// ## Two facts, and no third
///
/// A greeting and the organization the seller is selling for. The organization
/// name comes from the **trusted session context** the shell was built with —
/// the same source the app bar's title uses — never from a campaign row, a
/// reward row or a receipt.
///
/// There is deliberately no personal statistic here: no rank, no streak, no
/// "you are ahead of last week", no submission count. Every one of those would
/// have to be invented, because no contract in this application returns one.
class SalesStaffWelcomeHeader extends StatelessWidget {
  const SalesStaffWelcomeHeader({
    super.key,
    required this.organizationName,
    this.action,
  });

  /// The Retailer this seller belongs to, or null when the session context
  /// carried none. Null omits the line rather than rendering a placeholder.
  final String? organizationName;

  /// The primary action, on layouts wide enough to carry it in the header.
  /// Null on a phone, where the action is the floating pill instead.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final String? organization = organizationName;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        ExcludeSemantics(child: SrInitialsAvatar(name: organization, size: 40)),
        const SizedBox(width: SrSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                SalesStaffHomeCopy.greeting,
                style: SrTypography.sectionTitle.copyWith(color: sr.foreground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (organization != null)
                Text(
                  SalesStaffHomeCopy.forRetailer(organization),
                  style: SrTypography.caption.copyWith(color: sr.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (action != null) ...<Widget>[
          const SizedBox(width: SrSpacing.md),
          action!,
        ],
      ],
    );
  }
}
