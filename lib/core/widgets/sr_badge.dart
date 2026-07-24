import 'package:flutter/material.dart';

import '../design/design.dart';

/// A status pill, translated from `components/ui/badge.tsx`.
///
/// `rounded-full px-2.5 py-0.5 text-xs font-medium` with a 1px inset ring.
/// Meaning is never carried by color alone: the label text is always present,
/// and key states add an icon — a rule this widget preserves from the web.
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.smPlus,
        vertical: SrSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(SrRadii.full),
        border: Border.all(color: tone.ring),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: tone.foreground),
            const SizedBox(width: SrSpacing.xs),
          ],
          // Flexible so a long label truncates rather than overflowing the
          // pill. A badge is a fixed-height chip; it must not wrap.
          Flexible(
            child: Text(
              label,
              style: SrTypography.badge.copyWith(color: tone.foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Backend status → presentation, mirroring `STATUS_MAP` in `badge.tsx`.
///
/// This is the ONE place a backend status enum becomes a user-facing label, so
/// the same value reads identically on both clients and a raw enum string is
/// never printed. An unrecognized status renders as "Unknown" in a neutral tone
/// rather than leaking the raw database value into the page.
///
/// The map is presentation only. It decides nothing: which statuses a caller can
/// even see is decided in SQL.
class SrStatusBadge extends StatelessWidget {
  const SrStatusBadge({super.key, required this.status});

  final String status;

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

  @override
  Widget build(BuildContext context) {
    final (String, SrTone, IconData?)? meta = _statusMap[status];

    if (meta == null) {
      return const SrBadge(label: 'Unknown');
    }

    return SrBadge(label: meta.$1, tone: meta.$2, icon: meta.$3);
  }
}
