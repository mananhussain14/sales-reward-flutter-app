import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_retailer_summary.dart';
import 'vendor_retailer_badges.dart';
import 'vendor_retailer_copy.dart';
import 'vendor_retailer_formatting.dart';

/// One Retailer in the directory.
///
/// ## It has to *look* openable, and it does so three times over
///
/// The placeholder this screen replaces gave no hint that a row led anywhere.
/// This card carries a trailing chevron, an explicit "View details" affordance
/// at its foot, and the interactive card treatment (press state, brand-tinted
/// border) — so the affordance survives whether a reader is scanning shapes,
/// reading words, or feeling for a touch target.
///
/// The whole card is the target, not just the chevron: 44pt is the minimum and
/// a 16px glyph is not it.
///
/// ## Two statuses, because they are two facts
///
/// `retailer_status` is the Retailer company's own state; `relationship_status`
/// is this Vendor's relationship with it. A Retailer can be `ACTIVE` while the
/// relationship is `SUSPENDED`, and collapsing them into one pill would hide
/// exactly the case a Vendor most needs to see.
class VendorRetailerCard extends StatelessWidget {
  const VendorRetailerCard({
    super.key,
    required this.retailer,
    required this.onOpen,
  });

  final VendorRetailerSummary retailer;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      button: true,
      // One spoken sentence carrying everything the card shows, so a screen
      // reader user is not made to walk six separate pills to learn the same
      // thing. It names no id.
      label:
          '${retailer.retailerName}. '
          'Relationship ${VendorRetailerStatusBadge.labelFor(retailer.relationshipStatus)}. '
          'Retailer ${VendorRetailerStatusBadge.labelFor(retailer.retailerStatus)}. '
          '${RetailerOwnerStateBadge.labelFor(retailer.ownerState)}. '
          '${formatShopCounts(retailer.shopCount, retailer.activeShopCount)}.',
      hint: VendorRetailerCopy.openDetails,
      excludeSemantics: true,
      child: SrCard(
        variant: SrCardVariant.interactive,
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SrIconDisc(
                  icon: Icons.storefront_rounded,
                  tone: SrTone.indigo,
                  size: 40,
                ),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        retailer.retailerName,
                        style: SrTypography.cardTitle.copyWith(
                          color: sr.foreground,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: SrSpacing.xs),
                      Text(
                        formatShopCounts(
                          retailer.shopCount,
                          retailer.activeShopCount,
                        ),
                        style: SrTypography.caption.copyWith(
                          color: sr.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SrSpacing.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: sr.textMuted,
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.lg),
            // Wrap rather than Row: three pills on a 360px phone must run onto a
            // second line instead of overflowing.
            Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              children: <Widget>[
                VendorRetailerStatusBadge(
                  status: retailer.relationshipStatus,
                  prefix: 'Relationship',
                ),
                VendorRetailerStatusBadge(
                  status: retailer.retailerStatus,
                  prefix: 'Retailer',
                ),
                RetailerOwnerStateBadge(ownerState: retailer.ownerState),
              ],
            ),
            const SizedBox(height: SrSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Onboarded ${formatOnboardedDate(retailer.relationshipCreatedAt)}',
                    style: SrTypography.caption.copyWith(color: sr.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: SrSpacing.sm),
                Text(
                  VendorRetailerCopy.openDetails,
                  style: SrTypography.caption.copyWith(color: sr.brand),
                ),
                Icon(Icons.arrow_forward_rounded, size: 14, color: sr.brand),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
