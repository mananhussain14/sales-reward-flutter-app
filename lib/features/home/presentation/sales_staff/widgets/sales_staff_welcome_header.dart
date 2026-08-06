import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import 'sales_staff_home_copy.dart';

/// The greeting at the top of the Sales Staff home.
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
    required this.hasCampaigns,
    this.action,
  });

  /// The Retailer this seller belongs to, or null when the session context
  /// carried none. Null omits the line rather than rendering a placeholder.
  final String? organizationName;

  /// Whether any campaign is running or starting soon.
  ///
  /// Decides which encouraging line is shown, so the screen never says a reward
  /// is within reach directly above a section that says there are no campaigns.
  final bool hasCampaigns;

  /// The primary action, on layouts wide enough to carry it in the header.
  /// Null on a phone, where the action is the sticky bar at the bottom instead.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final String? organization = organizationName;

    final Widget identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(child: SrInitialsAvatar(name: organization, size: 44)),
        const SizedBox(width: SrSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                SalesStaffHomeCopy.greeting,
                style: SrTypography.pageTitle.copyWith(color: sr.foreground),
              ),
              if (organization != null) ...<Widget>[
                const SizedBox(height: SrSpacing.xxs),
                Text(
                  SalesStaffHomeCopy.forRetailer(organization),
                  style: SrTypography.body.copyWith(color: sr.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        identity,
        const SizedBox(height: SrSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: SrSpacing.xxs),
              child: ExcludeSemantics(
                child: Icon(
                  hasCampaigns
                      ? Icons.auto_awesome_rounded
                      : Icons.info_outline_rounded,
                  size: 16,
                  color: sr.brand,
                ),
              ),
            ),
            const SizedBox(width: SrSpacing.sm),
            Expanded(
              child: Text(
                hasCampaigns
                    ? SalesStaffHomeCopy.greetingLine
                    : SalesStaffHomeCopy.greetingLineNoCampaigns,
                style: SrTypography.body.copyWith(color: sr.textBody),
              ),
            ),
          ],
        ),
        if (action != null) ...<Widget>[
          const SizedBox(height: SrSpacing.xl),
          Align(alignment: Alignment.centerLeft, child: action!),
        ],
      ],
    );
  }
}
