import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/retailer_staff_member.dart';
import 'retailer_manage_staff_shops_copy.dart';
import 'retailer_staff_copy.dart';

/// One staff member.
///
/// ## Exactly one control, and only when it can do something
///
/// The card carries no `onTap`, no chevron, no overflow menu, no role picker and
/// no activate/deactivate switch — not disabled ones, none at all. Those are
/// operations this application does not perform, and a greyed-out control would
/// imply the feature exists and is merely switched off.
///
/// The one exception is **Manage shops**, rendered only when [onManageShops] is
/// supplied. The page supplies it only for a row the backend described as an
/// active, accepted Sales Staff member, in a shell that holds the write, for a
/// caller whose backend-derived capability hint offers shop assignment. All of
/// that is presentation scope: the database re-decides on every call and would
/// refuse a hand-crafted request whatever this card rendered.
///
/// ## No identifier is rendered
///
/// The entity now carries `membershipId` and `shopIds`, because the editor needs
/// them — and neither appears anywhere on this card. The membership id is passed
/// to a callback; it is never a label, a semantics string, or a widget key. Shops
/// are shown by **name** alone.
///
/// ## Accessibility
///
/// One semantics node reading a single sentence — name, role, status, shops,
/// joined date — rather than five fragments a screen reader would announce as
/// unrelated strings, followed by the button as its own node naming the person
/// it acts on. Status is announced by its **label**, never by colour.
class RetailerStaffMemberCard extends StatelessWidget {
  const RetailerStaffMemberCard({
    super.key,
    required this.member,
    this.onManageShops,
  });

  final RetailerStaffMember member;

  /// Opens the shop editor for this member, or null when the action does not
  /// belong on this card.
  ///
  /// Null is the whole absence: there is no disabled variant, because a control
  /// that cannot act is a promise nothing keeps.
  final VoidCallback? onManageShops;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            label: _semanticLabel(),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            member.fullName,
                            style: SrTypography.sectionTitle.copyWith(
                              color: sr.foreground,
                            ),
                          ),
                          const SizedBox(height: SrSpacing.xxs),
                          Text(
                            member.roleName,
                            style: SrTypography.body.copyWith(
                              color: sr.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: SrSpacing.sm),
                    SrBadge(
                      label: member.status.label,
                      tone: _tone(member.status),
                    ),
                  ],
                ),

                const SizedBox(height: SrSpacing.lg),

                // Shops. An empty list is the expected shape for an Owner or a
                // Manager, who hold no shop rows at all — so it is stated plainly
                // rather than left as a blank gap that reads like missing data.
                Text(
                  RetailerStaffCopy.shopsLabel,
                  style: SrTypography.caption.copyWith(color: sr.textMuted),
                ),
                const SizedBox(height: SrSpacing.xs),
                if (member.hasShops)
                  Wrap(
                    spacing: SrSpacing.sm,
                    runSpacing: SrSpacing.sm,
                    children: <Widget>[
                      for (final String shop in member.shopNames)
                        SrBadge(
                          label: shop,
                          tone: SrTone.slate,
                          icon: Icons.storefront_rounded,
                        ),
                    ],
                  )
                else
                  Text(
                    RetailerStaffCopy.noShopsLabel,
                    style: SrTypography.body.copyWith(color: sr.textMuted),
                  ),

                const SizedBox(height: SrSpacing.lg),

                Text(
                  '${RetailerStaffCopy.joinedLabel}: ${_joined()}',
                  style: SrTypography.caption.copyWith(color: sr.textMuted),
                ),
              ],
            ),
          ),

          // Outside the semantics node above, so a screen reader announces the
          // member as one sentence and then the button as its own control,
          // rather than folding a control into a description.
          if (onManageShops != null) ...<Widget>[
            const SizedBox(height: SrSpacing.lg),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: RetailerManageStaffShopsCopy.actionSemantics(
                  member.fullName,
                ),
                child: SrButton(
                  label: RetailerManageStaffShopsCopy.action,
                  variant: SrButtonVariant.outline,
                  size: SrButtonSize.sm,
                  icon: Icons.storefront_rounded,
                  onPressed: onManageShops,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The joining date, or an explicit absence.
  ///
  /// Never substitutes `created_at`: a membership row created by an invitation
  /// that was never accepted has no joining date, and showing the creation
  /// instant would state a day this person joined on when they have not joined.
  String _joined() {
    final DateTime? joined = member.joinedAt;
    return joined == null
        ? RetailerStaffCopy.joinedUnknown
        : formatDayDate(joined);
  }

  String _semanticLabel() {
    final String shops = member.hasShops
        ? '${RetailerStaffCopy.shopsLabel}: ${member.shopNames.join(', ')}.'
        : '${RetailerStaffCopy.noShopsLabel}.';
    return '${member.fullName}. ${member.roleName}. '
        '${member.status.label}. $shops '
        '${RetailerStaffCopy.joinedLabel}: ${_joined()}.';
  }

  static SrTone _tone(RetailerMemberStatus status) => switch (status) {
    RetailerMemberStatus.active => SrTone.emerald,
    RetailerMemberStatus.invited => SrTone.blue,
    RetailerMemberStatus.suspended => SrTone.amber,
    RetailerMemberStatus.deactivated => SrTone.red,
    RetailerMemberStatus.unknown => SrTone.slate,
  };
}
