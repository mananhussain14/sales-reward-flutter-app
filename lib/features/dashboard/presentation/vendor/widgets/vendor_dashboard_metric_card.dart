import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import 'vendor_dashboard_copy.dart';

/// Which of the two scopes a metric belongs to.
///
/// Not a styling choice. `public.organization_members` and `public.audit_logs`
/// carry an `organization_id` and are counted for the caller's Vendor;
/// `public.roles` and `public.permissions` carry none and are counted across the
/// whole deployment. That is a difference in what the number *means*, so it is
/// modelled rather than left to a colour.
enum VendorMetricScope {
  /// Counted for the caller's Vendor organization.
  vendor,

  /// Counted deployment-wide. Identical for every authorized Vendor.
  sharedCatalogue,
}

extension on VendorMetricScope {
  /// The chip text. Always present — this is the non-colour channel.
  String get chipLabel => switch (this) {
    VendorMetricScope.vendor => VendorDashboardCopy.vendorScopeChip,
    VendorMetricScope.sharedCatalogue => VendorDashboardCopy.catalogueScopeChip,
  };

  /// The chip glyph. A second non-colour channel, so the distinction survives a
  /// greyscale render and a colour-vision difference alike.
  IconData get chipIcon => switch (this) {
    VendorMetricScope.vendor => Icons.apartment_rounded,
    VendorMetricScope.sharedCatalogue => Icons.public_rounded,
  };

  SrTone get chipTone => switch (this) {
    VendorMetricScope.vendor => SrTone.indigo,
    VendorMetricScope.sharedCatalogue => SrTone.slate,
  };
}

/// One count from the dashboard summary.
///
/// Deliberately **not** `SrStatCard`. That widget models a nullable figure and
/// renders "Unavailable" for null, which is exactly right for the web's per-card
/// degradation — and exactly wrong here. This contract has no per-card failure:
/// every count is a non-null `bigint`, all four arrive together, and a refusal
/// takes the whole screen rather than one card. A card that could render
/// "Unavailable" would be a card someone could later make render `0` for the same
/// reason.
///
/// So [value] is non-nullable, and the scope chip that `SrStatCard` has no place
/// for is a required part of the card rather than an optional decoration.
///
/// ## Accessibility
///
/// The whole card is one semantics node reading "label: value. scope. hint." —
/// one sentence rather than four fragments a reader would have to reassemble.
/// The visual tree is excluded beneath it so the figure is not announced twice,
/// once formatted and once raw.
class VendorDashboardMetricCard extends StatelessWidget {
  const VendorDashboardMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.scope,
    this.tone = SrTone.indigo,
  });

  final String label;

  /// The exact count. Non-nullable: there is no per-card unavailable state in
  /// this contract, and `0` is a real answer rather than an absence.
  final int value;

  final String hint;
  final IconData icon;
  final VendorMetricScope scope;

  /// The tint on the leading disc. Decoration only — it carries no meaning that
  /// the chip and the hint do not already carry in words.
  final SrTone tone;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    // Grouped in a fixed locale, as the web's `toLocaleString("en-US")` does, so
    // the two clients render the same figure the same way whatever the device is
    // set to.
    final String formatted = SrStatCard.format(value);

    return Semantics(
      label: VendorDashboardCopy.metricSemantics(
        label: label,
        value: formatted,
        scope: scope.chipLabel,
        hint: hint,
      ),
      excludeSemantics: true,
      child: SrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: SrTypography.label.copyWith(color: sr.textSecondary),
                  ),
                ),
                const SizedBox(width: SrSpacing.md),
                SrIconDisc(icon: icon, tone: tone, size: 40),
              ],
            ),
            const SizedBox(height: SrSpacing.md),
            Text(
              formatted,
              style: SrTypography.statValue.copyWith(color: sr.foreground),
            ),
            const SizedBox(height: SrSpacing.sm),
            // The chip sits between the figure and the hint so the scope is read
            // before the explanation qualifies it. `Align` rather than a full-
            // width row: a pill stretched across a card reads as a banner.
            Align(
              alignment: Alignment.centerLeft,
              child: SrBadge(
                label: scope.chipLabel,
                icon: scope.chipIcon,
                tone: scope.chipTone,
              ),
            ),
            const SizedBox(height: SrSpacing.sm),
            Text(
              hint,
              style: SrTypography.caption.copyWith(color: sr.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
