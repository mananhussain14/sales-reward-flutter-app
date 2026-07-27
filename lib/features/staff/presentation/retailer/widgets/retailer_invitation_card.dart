import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/retailer_staff_invitation.dart';
import 'retailer_staff_copy.dart';

/// One invitation.
///
/// ## No write affordance of any kind
///
/// No Invite button, no Resend, no Revoke, no "activate account", no
/// registration link — not disabled ones, none at all. Sending an invitation
/// requires the `send-staff-invitation` Edge Function, which holds the delivery
/// credential and is not called anywhere in this application; revoking is a
/// write this milestone does not implement. The section note says so in words,
/// so the absence reads as scope rather than as a broken screen.
///
/// ## Nothing internal reaches the screen
///
/// `invitation_id` and `shop_ids` are not carried by the entity, so no UUID can
/// appear here. `failure_code` was reduced to a boolean at the parser, so no
/// backend enum token can appear either — [RetailerStaffCopy.deliveryFailedHint]
/// is fixed copy describing the outcome a person can act on.
///
/// The intended role is rendered through [RetailerStaffCopy.roleLabelFor],
/// because the invitation contract returns only `role_code` and `SALES_STAFF` on
/// screen would be an internal identifier leaking into the UI. An unrecognised
/// code falls back to a neutral phrase rather than showing the token.
///
/// ## Dates are shown only where they mean something
///
/// Each state has its own relevant instant, so the card shows that one rather
/// than listing five fields of which four are null. An accepted invitation shows
/// when it was accepted; a revoked one when it was revoked; a live one when it
/// expires.
class RetailerInvitationCard extends StatelessWidget {
  const RetailerInvitationCard({super.key, required this.invitation});

  final RetailerStaffInvitation invitation;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final List<({String label, String value})> dates = _dates();

    return Semantics(
      label: _semanticLabel(dates),
      excludeSemantics: true,
      child: SrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The state badge is stacked beneath the name rather than beside
            // it. An invitation state label is variable-length prose ("Awaiting
            // acceptance", "Status unavailable"), and competing with an email
            // address for one row overflows a phone — which is exactly what the
            // narrow-layout test caught. Stacking is also the honest reading
            // order: who, where, then what happened.
            Text(
              invitation.fullName,
              style: SrTypography.sectionTitle.copyWith(color: sr.foreground),
            ),
            const SizedBox(height: SrSpacing.xxs),
            Text(
              invitation.email,
              style: SrTypography.body.copyWith(color: sr.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: SrSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: SrBadge(
                label: invitation.state.label,
                tone: _tone(invitation.state),
              ),
            ),

            const SizedBox(height: SrSpacing.lg),

            Text(
              '${RetailerStaffCopy.invitedAsLabel}: '
              '${RetailerStaffCopy.roleLabelFor(invitation.roleCode)}',
              style: SrTypography.body.copyWith(color: sr.textSecondary),
            ),

            if (dates.isNotEmpty) ...<Widget>[
              const SizedBox(height: SrSpacing.md),
              Wrap(
                spacing: SrSpacing.xl,
                runSpacing: SrSpacing.sm,
                children: <Widget>[
                  for (final ({String label, String value}) date in dates)
                    Text(
                      '${date.label}: ${date.value}',
                      style: SrTypography.caption.copyWith(color: sr.textMuted),
                    ),
                ],
              ),
            ],

            // The delivery failure. Shown as an alert rather than a badge
            // because it is the one state on this card that asks a person to do
            // something — and the something is on the web portal, which the copy
            // says.
            if (invitation.hasDeliveryFailure) ...<Widget>[
              const SizedBox(height: SrSpacing.lg),
              const SrAlert(
                tone: SrAlertTone.warning,
                title: RetailerStaffCopy.deliveryFailedLabel,
                message: RetailerStaffCopy.deliveryFailedHint,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The instants worth showing for this invitation's state.
  List<({String label, String value})> _dates() {
    final RetailerStaffInvitation i = invitation;

    return <({String label, String value})>[
      if (i.acceptedAt != null)
        (
          label: RetailerStaffCopy.acceptedLabel,
          value: formatDayDate(i.acceptedAt!),
        )
      else if (i.revokedAt != null)
        (
          label: RetailerStaffCopy.revokedLabel,
          value: formatDayDate(i.revokedAt!),
        )
      else
        (
          // For a live or expired invitation the expiry is the fact that
          // matters. The label changes with the state so an expired invitation
          // does not read as though it is still counting down.
          label: i.state == RetailerInvitationState.expired
              ? RetailerStaffCopy.expiredLabel
              : RetailerStaffCopy.expiresLabel,
          value: formatDayDate(i.expiresAt),
        ),
      (
        label: RetailerStaffCopy.sentLabel,
        value: i.sentAt == null
            ? RetailerStaffCopy.neverSent
            : formatDayDate(i.sentAt!),
      ),
    ];
  }

  String _semanticLabel(List<({String label, String value})> dates) {
    final StringBuffer buffer = StringBuffer()
      ..write('${invitation.fullName}. ')
      ..write('${invitation.email}. ')
      ..write('${invitation.state.label}. ')
      ..write(
        '${RetailerStaffCopy.invitedAsLabel}: '
        '${RetailerStaffCopy.roleLabelFor(invitation.roleCode)}.',
      );
    for (final ({String label, String value}) date in dates) {
      buffer.write(' ${date.label}: ${date.value}.');
    }
    if (invitation.hasDeliveryFailure) {
      buffer.write(' ${RetailerStaffCopy.deliveryFailedLabel}.');
    }
    return buffer.toString();
  }

  static SrTone _tone(RetailerInvitationState state) => switch (state) {
    RetailerInvitationState.accepted => SrTone.emerald,
    RetailerInvitationState.pending => SrTone.blue,
    RetailerInvitationState.reserved => SrTone.slate,
    RetailerInvitationState.deliveryFailed => SrTone.amber,
    RetailerInvitationState.expired => SrTone.slate,
    RetailerInvitationState.revoked => SrTone.red,
    // Both fallbacks read neutrally. Neither is ever styled as a success or a
    // failure, because this build does not know which it is.
    RetailerInvitationState.unknown => SrTone.slate,
    RetailerInvitationState.indeterminate => SrTone.slate,
  };
}
