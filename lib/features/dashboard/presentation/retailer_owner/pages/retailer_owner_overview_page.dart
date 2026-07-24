import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/app_role.dart';

/// The Retailer Owner landing screen.
///
/// A **placeholder** reproducing § 5.7 of `docs/mobile-ui-design-handoff.md`:
/// the eyebrow, the description, and a four-up detail grid collapsed to one
/// column.
///
/// The web sets the page **title to the retailer's name**, which comes from
/// `get_retailer_owner_portal_context()` (RO-01). Nothing is read here, so the
/// title falls back to "Overview" rather than fabricating an organization name —
/// the same choice the web makes for a Manager, whose source documents it as
/// *"Rather than fabricate a name or guess one, the header omits it."*
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
              'A read-only view of your organization and its shops on '
              'SalesReward.',
        ),
        const SizedBox(height: SrSpacing.xxl),

        const SrCardGrid(
          children: <Widget>[
            SrStatCard(
              label: 'Shops',
              value: null,
              hint: 'Active locations in your organization',
              icon: Icons.storefront_rounded,
              tone: SrTone.indigo,
            ),
            SrStatCard(
              label: 'Staff',
              value: null,
              hint: 'Members and pending invitations',
              icon: Icons.group_rounded,
              tone: SrTone.emerald,
            ),
            SrStatCard(
              label: 'Products',
              value: null,
              hint: 'Assigned to your organization',
              icon: Icons.inventory_2_rounded,
              tone: SrTone.amber,
            ),
          ],
        ),

        const SizedBox(height: SrSpacing.xxxl),
        SrSectionCard(
          title: 'What this role can do',
          description:
              'Read the portal, manage staff and invitations, and view the '
              'products assigned to you.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Deliberately describes the rule in product language rather than
              // naming the permission code: an internal identifier in
              // user-facing copy is noise, and detail the client has no business
              // asserting.
              Text(
                'Submitting receipts is not one of them. Receipt submission '
                'belongs to Sales Staff alone, so those operations refuse an '
                'Owner — which is why this shell offers no Receipts tab.',
                style: SrTypography.body.copyWith(
                  color: context.sr.textSecondary,
                ),
              ),
              const SizedBox(height: SrSpacing.lg),
              const Wrap(
                spacing: SrSpacing.sm,
                runSpacing: SrSpacing.sm,
                children: <Widget>[
                  SrBadge(
                    label: 'Read paths ready',
                    tone: SrTone.emerald,
                    icon: Icons.check_rounded,
                  ),
                  SrBadge(label: 'Enforced in SQL', tone: SrTone.slate),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
