import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_user_summary.dart';
import 'vendor_user_badges.dart';
import 'vendor_user_copy.dart';
import 'vendor_user_formatting.dart';
import 'vendor_user_role_chips.dart';

/// One user in the directory.
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
/// ## Two statuses, because they are two facts
///
/// `profile_status` is the person's own account state; `membership_status` is
/// their standing in *this* Vendor. The backend is explicit that they are
/// independent — a person with an ACTIVE profile can hold a SUSPENDED membership
/// here — and collapsing them into one pill would hide exactly the case a Vendor
/// most needs to see.
///
/// ## No email, and no space where one used to be
///
/// The contract returns no address, so there is nothing to render and no
/// placeholder row: a label for an absent field is still a claim about it.
class VendorUserCard extends StatelessWidget {
  const VendorUserCard({super.key, required this.user, required this.onOpen});

  final VendorUserSummary user;
  final VoidCallback onOpen;

  /// The one spoken sentence this card presents.
  ///
  /// Everything visible, in order, so a screen reader user is not made to walk
  /// two pills and six chips to learn the same thing. It names no identifier.
  static String semanticsFor(VendorUserSummary user) =>
      '${user.displayName}. '
      '${VendorUserStatusBadge.semanticsFor(user.profileStatus, VendorUserStatusKind.profile)}. '
      '${VendorUserStatusBadge.semanticsFor(user.membershipStatus, VendorUserStatusKind.membership)}. '
      '${VendorUserRoleChips.semanticsFor(user.roleNames)}. '
      'Joined ${formatJoined(user.joinedAt)}.';

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      button: true,
      label: semanticsFor(user),
      hint: VendorUserCopy.openDetails,
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
                  icon: Icons.person_rounded,
                  tone: SrTone.indigo,
                  size: 40,
                ),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        user.displayName,
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
                        formatRoleCount(user.roleNames.length),
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
            // Wrap rather than Row: two prefixed pills on a 360px phone must run
            // onto a second line instead of overflowing.
            Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              children: <Widget>[
                VendorUserStatusBadge(
                  status: user.profileStatus,
                  kind: VendorUserStatusKind.profile,
                ),
                VendorUserStatusBadge(
                  status: user.membershipStatus,
                  kind: VendorUserStatusKind.membership,
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.md),
            VendorUserRoleChips(roleNames: user.roleNames),
            const SizedBox(height: SrSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Joined ${formatJoined(user.joinedAt)}',
                    style: SrTypography.caption.copyWith(color: sr.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: SrSpacing.sm),
                Text(
                  VendorUserCopy.openDetails,
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
