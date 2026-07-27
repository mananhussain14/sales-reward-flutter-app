import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/retailer_staff_member.dart';
import 'retailer_staff_copy.dart';

/// One staff member.
///
/// ## Deliberately not tappable, and carrying no controls
///
/// No `onTap`, no chevron, no overflow menu, no role picker, no
/// activate/deactivate switch and no shop-assignment editor — not disabled ones,
/// none at all. This milestone is read-only, there is no member detail screen,
/// and a greyed-out control would imply the feature exists and is merely
/// switched off.
///
/// ## No identifier is rendered
///
/// The contract returns `membership_id` and `shop_ids`; the entity carries
/// neither, so there is nothing here that could put a UUID on screen. Shops are
/// shown by **name** alone.
///
/// ## Accessibility
///
/// One semantics node reading a single sentence — name, role, status, shops,
/// joined date — rather than five fragments a screen reader would announce as
/// unrelated strings. Status is announced by its **label**, never by colour.
class RetailerStaffMemberCard extends StatelessWidget {
  const RetailerStaffMemberCard({super.key, required this.member});

  final RetailerStaffMember member;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      label: _semanticLabel(),
      excludeSemantics: true,
      child: SrCard(
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
                SrBadge(label: member.status.label, tone: _tone(member.status)),
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
