import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_role_summary.dart';
import 'vendor_role_badges.dart';
import 'vendor_role_copy.dart';
import 'vendor_role_formatting.dart';

/// One role definition in the catalogue.
///
/// ## It has to *look* openable, and it does so three times over
///
/// The placeholder this screen replaces gave no hint that a row led anywhere.
/// This card carries a trailing chevron, an explicit "View details" affordance
/// at its foot, and the interactive card treatment (press state, brand-tinted
/// border) — so the affordance survives whether a reader is scanning shapes,
/// reading words, or feeling for a touch target. The whole card is the target,
/// not the 16px glyph.
///
/// ## The status sits beside the permission count, deliberately
///
/// The two are read together or not at all: "6 permissions mapped" on an
/// inactive definition means six mappings that currently grant nothing. Putting
/// the pill anywhere a reader could see one without the other would be the one
/// way this card could mislead.
///
/// ## No code, no scope, no kind
///
/// The role code is not returned and is never displayed. There is no "system" or
/// "custom" badge, because there is no such column — and no Vendor/Retailer
/// label, because inferring one from the role name would be inventing a taxonomy
/// that would disagree with the web page showing the same six roles.
class VendorRoleCard extends StatelessWidget {
  const VendorRoleCard({super.key, required this.role, required this.onOpen});

  final VendorRoleSummary role;
  final VoidCallback onOpen;

  /// The one spoken sentence this card presents.
  ///
  /// Everything visible, in order, so a screen reader user is not made to walk a
  /// pill and three lines to learn the same thing. It names no identifier.
  static String semanticsFor(VendorRoleSummary role) =>
      '${role.roleName}. '
      '${VendorRoleStatusBadge.semanticsFor(role.status)}. '
      '${formatDescription(role.description)}. '
      '${formatPermissionCount(role.permissionCount)}. '
      '${formatAssignedMembers(role.assignedMemberCount)}.';

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      button: true,
      label: semanticsFor(role),
      hint: VendorRoleCopy.openDetails,
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
                  icon: Icons.vpn_key_rounded,
                  tone: SrTone.indigo,
                  size: 40,
                ),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        role.roleName,
                        style: SrTypography.cardTitle.copyWith(
                          color: sr.foreground,
                        ),
                        // Two lines then ellipsis: a long name wraps rather than
                        // being cut at the first overflow.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: SrSpacing.xs),
                      Text(
                        'Created ${formatRoleDate(role.createdAt)}',
                        style: SrTypography.caption.copyWith(
                          color: sr.textMuted,
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
            // Wrap rather than Row: the pill must run onto its own line on a
            // 360px phone at large text scale instead of overflowing.
            Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              children: <Widget>[VendorRoleStatusBadge(status: role.status)],
            ),
            // A null description is a real answer, said in words rather than
            // left as a gap — and never invented from the role name.
            const SizedBox(height: SrSpacing.md),
            Text(
              formatDescription(role.description),
              style: SrTypography.body.copyWith(
                color: role.description == null
                    ? sr.textMuted
                    : sr.textSecondary,
                fontStyle: role.description == null
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: SrSpacing.md),
            VendorRoleCountLine(
              icon: Icons.lock_outline_rounded,
              label: formatPermissionCount(role.permissionCount),
              muted: role.hasNoPermissions,
            ),
            const SizedBox(height: SrSpacing.xs),
            VendorRoleCountLine(
              icon: Icons.group_outlined,
              label: formatAssignedMembers(role.assignedMemberCount),
              muted: role.hasNoAssignedMembers,
            ),
            const SizedBox(height: SrSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text(
                  VendorRoleCopy.openDetails,
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

/// The responsive arrangement for role cards.
///
/// The layout itself lives in [SrResponsiveGrid]; what belongs here is the pair
/// of numbers, which is a property of *this* content. A role card carries a
/// wrapping description and two full-sentence count lines — "No members in your
/// Vendor" is not a short string — so it needs more width than a Retailer card
/// before a second column stops crowding it, and less than a User card, which
/// carries two prefixed pills and a row of role chips.
class VendorRoleGrid extends StatelessWidget {
  const VendorRoleGrid({super.key, required this.children});

  final List<Widget> children;

  /// Below this a second column would squeeze the count sentences.
  static const double twoUpThreshold = 800;

  /// Above this a third column still leaves each card wider than a phone.
  static const double threeUpThreshold = 1150;

  @override
  Widget build(BuildContext context) {
    return SrResponsiveGrid(
      twoUpThreshold: twoUpThreshold,
      threeUpThreshold: threeUpThreshold,
      children: children,
    );
  }
}
