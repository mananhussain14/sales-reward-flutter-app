import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/retailer_staff_lifecycle_action.dart';
import '../../../domain/entities/retailer_staff_member.dart';
import '../../../domain/repositories/retailer_staff_lifecycle_repository.dart';
import '../cubit/retailer_staff_lifecycle_cubit.dart';
import 'retailer_manage_staff_shops_copy.dart';
import 'retailer_staff_copy.dart';
import 'retailer_staff_lifecycle_copy.dart';
import 'retailer_staff_lifecycle_notices.dart';

/// One staff member.
///
/// ## Exactly one control, and only when it can do something
///
/// The card carries no `onTap`, no chevron, no overflow menu, no role picker and
/// no activate/deactivate switch — not disabled ones, none at all. Those are
/// operations this application does not perform, and a greyed-out control would
/// imply the feature exists and is merely switched off.
///
/// There are now exactly **two**, and each is rendered only when the page
/// supplies its callback:
///
/// * **Manage shops** — for a row the backend described as an active, accepted
///   Sales Staff member, in a shell that holds the write, for a caller whose
///   backend-derived capability hint offers shop assignment.
/// * **Deactivate / Reactivate** — for a row whose membership appears exactly
///   once in the whole roster, holds exactly `RETAILER_MANAGER` or `SALES_STAFF`,
///   and is `ACTIVE` or `DEACTIVATED`, for a caller whose hint offers staff
///   management. [lifecycleAction] carries the direction, the labels and the
///   status that will be requested, all from one table, so the verb on this
///   button cannot disagree with what is sent.
///
/// All of that is presentation scope: the database re-decides on every call and
/// would refuse a hand-crafted request whatever this card rendered.
///
/// ## The lifecycle outcome is scoped to this row
///
/// [lifecycleBusy], [lifecycleNotice] and [lifecycleProblem] are answered by the
/// cubit for **this membership id alone**. A request for a colleague never spins
/// this control, and a refusal that landed for them never appears under this
/// name.
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
    this.onLifecycle,
    this.lifecycleAction,
    this.lifecycleBusy = false,
    this.lifecycleNotice,
    this.lifecycleProblem,
  });

  final RetailerStaffMember member;

  /// Opens the shop editor for this member, or null when the action does not
  /// belong on this card.
  ///
  /// Null is the whole absence: there is no disabled variant, because a control
  /// that cannot act is a promise nothing keeps.
  final VoidCallback? onManageShops;

  /// Opens the deactivate/reactivate confirmation for this member, or null when
  /// the action does not belong on this card.
  ///
  /// Null for every excluded case — a Retailer Owner, the caller themselves, a
  /// membership appearing more than once in the roster, an invited or suspended
  /// membership, an unsupported role, and a caller without the staff-management
  /// hint. Null is again the whole absence.
  final VoidCallback? onLifecycle;

  /// The direction, labels and requested status for [onLifecycle].
  ///
  /// Non-null exactly when [onLifecycle] is. Held rather than derived here, so
  /// this card never decides eligibility — that is a whole-roster question and
  /// this widget can only see one row.
  final RetailerStaffLifecycleAction? lifecycleAction;

  /// Whether a lifecycle request for **this** membership is in flight.
  final bool lifecycleBusy;

  /// The acknowledgement for **this** membership, or null.
  final RetailerStaffLifecycleNotice? lifecycleNotice;

  /// The refusal for **this** membership, or null.
  final RetailerStaffLifecycleProblem? lifecycleProblem;

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

          // The outcome for THIS membership, above its own controls. A request
          // for a colleague never renders here — the page asks the cubit for
          // this membership id alone.
          if (lifecycleNotice != null) ...<Widget>[
            const SizedBox(height: SrSpacing.lg),
            RetailerStaffLifecycleNoticeAlert(notice: lifecycleNotice!),
          ],
          if (lifecycleProblem != null) ...<Widget>[
            const SizedBox(height: SrSpacing.lg),
            RetailerStaffLifecycleProblemAlert(problem: lifecycleProblem!),
          ],

          // Outside the semantics node above, so a screen reader announces the
          // member as one sentence and then each button as its own control,
          // rather than folding a control into a description.
          if (onManageShops != null || onLifecycle != null) ...<Widget>[
            const SizedBox(height: SrSpacing.lg),
            Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              children: <Widget>[
                if (onManageShops != null)
                  Semantics(
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
                if (onLifecycle != null && lifecycleAction != null)
                  Semantics(
                    button: true,
                    label: RetailerStaffLifecycleCopy.actionSemantics(
                      member.fullName,
                      isDeactivation: lifecycleAction!.isDeactivation,
                    ),
                    child: SrButton(
                      label: lifecycleAction!.actionLabel,
                      loadingLabel: lifecycleAction!.pendingLabel,
                      // Outline rather than danger. Deactivation is reversible
                      // with one press and destroys nothing — red would say
                      // "this cannot be undone" about something that can.
                      variant: SrButtonVariant.outline,
                      size: SrButtonSize.sm,
                      icon: lifecycleAction!.isDeactivation
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                      loading: lifecycleBusy,
                      // Null while busy, which is the duplicate-submission
                      // guard's visible half. The cubit refuses a second call
                      // regardless, and a same-status request is an idempotent
                      // no-op in SQL — so even a request that got through twice
                      // could not record two decisions.
                      onPressed: lifecycleBusy ? null : onLifecycle,
                    ),
                  ),
              ],
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
