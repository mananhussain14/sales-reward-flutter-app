import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/app_role.dart';

/// The Retailer Owner landing screen.
///
/// A **placeholder**. It shows the portal overview layout with the SalesReward
/// theme applied, and reads nothing.
///
/// The web equivalent is backed by `get_retailer_owner_portal_context()`, which
/// already exists and is marked ready. It is not wired here because this
/// milestone stops at the foundation — and because the shell cannot yet know it
/// is *legitimately* a Retailer Owner shell until `get_my_portal_context()`
/// lands.
class RetailerOwnerOverviewPage extends StatelessWidget {
  const RetailerOwnerOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SrPageBody(
      children: <Widget>[
        SrPageHeader(
          eyebrow: AppRole.retailerOwner.displayName,
          title: 'Overview',
          description:
              'Your shops, your staff, and the products assigned to you.',
        ),
        const SizedBox(height: SrSpacing.xxl),

        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const List<(String, String, IconData, SrTone)> metrics =
                <(String, String, IconData, SrTone)>[
                  (
                    'Shops',
                    'Active locations',
                    Icons.storefront_rounded,
                    SrTone.indigo,
                  ),
                  (
                    'Staff',
                    'Members and pending invitations',
                    Icons.group_rounded,
                    SrTone.emerald,
                  ),
                  (
                    'Products',
                    'Assigned to your organization',
                    Icons.inventory_2_rounded,
                    SrTone.amber,
                  ),
                ];

            final bool twoUp = constraints.maxWidth >= 520;
            final double itemWidth = twoUp
                ? (constraints.maxWidth - SrSpacing.lg) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: SrSpacing.lg,
              runSpacing: SrSpacing.lg,
              children: <Widget>[
                for (final (String, String, IconData, SrTone) metric in metrics)
                  SizedBox(
                    width: itemWidth,
                    child: SrStatCard(
                      label: metric.$1,
                      value: null,
                      hint: metric.$2,
                      icon: metric.$3,
                      tone: metric.$4,
                    ),
                  ),
              ],
            );
          },
        ),

        const SizedBox(height: SrSpacing.xxl),
        SrSectionCard(
          title: 'What this role can do',
          description:
              'Read the portal, manage staff and invitations, and view assigned '
              'products.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Deliberately describes the rule in product language rather than
              // naming the permission code. An internal identifier in user-
              // facing copy is noise to the reader and detail the client has no
              // business asserting.
              Text(
                'Submitting receipts is not one of them. Receipt submission '
                'belongs to Sales Staff alone, so those operations refuse an '
                'Owner — which is why this shell offers no Receipts tab.',
                style: SrTypography.bodyMuted,
              ),
              const SizedBox(height: SrSpacing.lg),
              const SrBadge(
                label: 'Read paths ready in SQL',
                tone: SrTone.emerald,
                icon: Icons.check_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
