import 'package:flutter/material.dart';

import '../design/design.dart';

/// A status pill (§ 3.6): full radius, `px-2.5 py-0.5`, 12px/500, a 1px **inset**
/// ring at 20% (30% in dark), and an optional leading 12px icon.
///
/// Meaning is never carried by colour alone — the label is always present, and
/// the key states add an icon.
class SrBadge extends StatelessWidget {
  const SrBadge({
    super.key,
    required this.label,
    this.tone = SrTone.slate,
    this.icon,
  });

  final String label;
  final SrTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final SrToneColors colors = context.sr.tone(tone);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.smPlus,
        vertical: SrSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(SrRadii.full),
        border: Border.all(color: colors.ring),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: colors.foreground),
            const SizedBox(width: SrSpacing.xs),
          ],
          // Flexible so a long label truncates rather than overflowing the pill.
          Flexible(
            child: Text(
              label,
              style: SrTypography.badge.copyWith(color: colors.foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Backend status → presentation.
///
/// The Dart port of the **single** enum map in `components/ui/badge.tsx`
/// (§ 3.6), reproduced verbatim including the `Unknown` fallback.
///
/// Two properties are load-bearing rather than cosmetic:
///
/// * **The raw enum never reaches the screen.** An unrecognised value renders
///   "Unknown" in a neutral tone, so a future backend status cannot leak a
///   database token into the interface.
/// * **`null` falls into the same branch.**
///   `list_retailer_staff_invitations().derived_state` has no `ELSE` in SQL and
///   can genuinely be `NULL` (contract fix #2); it must render, not crash.
class SrStatusBadge extends StatelessWidget {
  const SrStatusBadge({super.key, required this.status});

  /// The backend enum, or null.
  final String? status;

  static const Map<String, (String, SrTone, IconData?)> _statusMap =
      <String, (String, SrTone, IconData?)>{
        'ACTIVE': ('Active', SrTone.emerald, Icons.check_rounded),
        'ACCEPTED': ('Accepted', SrTone.emerald, Icons.check_rounded),
        'APPROVED': ('Approved', SrTone.emerald, Icons.check_rounded),
        'INVITED': ('Invited', SrTone.amber, Icons.schedule_rounded),
        'PENDING': ('Pending', SrTone.amber, Icons.schedule_rounded),
        'AWAITING': (
          'Awaiting acceptance',
          SrTone.amber,
          Icons.schedule_rounded,
        ),
        'SUSPENDED': ('Suspended', SrTone.amber, null),
        'PROCESSING': ('Processing', SrTone.indigo, null),
        'UPLOADED': ('Uploaded', SrTone.blue, null),
        'SUBMITTED': ('Submitted', SrTone.blue, null),
        'EXPIRED': ('Expired', SrTone.slate, null),
        'REVOKED': ('Revoked', SrTone.slate, null),
        'DEACTIVATED': ('Deactivated', SrTone.slate, null),
        'INACTIVE': ('Inactive', SrTone.slate, null),
        'FAILED': ('Failed', SrTone.red, null),
        'REJECTED': ('Rejected', SrTone.red, null),
      };

  /// The label this widget would render for [status]. Exposed so tests can
  /// assert the map without building a widget for each of seventeen cases.
  static String labelFor(String? status) => _statusMap[status]?.$1 ?? 'Unknown';

  @override
  Widget build(BuildContext context) {
    final (String, SrTone, IconData?)? meta = _statusMap[status];

    if (meta == null) {
      return const SrBadge(label: 'Unknown');
    }
    return SrBadge(label: meta.$1, tone: meta.$2, icon: meta.$3);
  }
}
