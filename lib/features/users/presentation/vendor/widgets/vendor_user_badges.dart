import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_user_status.dart';

/// Which of the two status columns a badge is showing.
///
/// The prefix is not decoration. This screen shows **two** statuses that share a
/// vocabulary, and a bare "Active" pill twice over tells a reader nothing about
/// which is which — so the subject travels with the value, in the visible label
/// and in the semantics alike.
enum VendorUserStatusKind {
  profile('Profile status'),
  membership('Membership status');

  const VendorUserStatusKind(this.label);

  final String label;
}

/// A profile or membership status, as a pill.
///
/// ## Colour is never the message
///
/// Every state carries its own word and its own glyph, so a user who cannot
/// distinguish amber from emerald reads exactly the same facts. The semantics
/// label spells the pair out in full — "Profile status: Invited" — because a
/// screen reader announcing "Invited" alone would leave the same ambiguity the
/// prefix exists to remove.
///
/// ## An unknown token is neutral, and grants nothing
///
/// [VendorUserStatus.unknown] renders "Unknown" in the slate tone with a
/// question glyph. The raw backend token is never shown — a future status must
/// not leak a database literal into the interface — and because the enum's
/// `isActive` tests `active` positively, nothing downstream can mistake it for a
/// working membership. The user is still listed: losing sight of somebody
/// because their status is unfamiliar would be worse than showing it plainly.
class VendorUserStatusBadge extends StatelessWidget {
  const VendorUserStatusBadge({
    super.key,
    required this.status,
    required this.kind,
    this.showPrefix = true,
  });

  final VendorUserStatus status;
  final VendorUserStatusKind kind;

  /// Whether the subject appears in the visible label. When false it still
  /// appears in the semantics label, so the pair is never lost.
  final bool showPrefix;

  /// The label for [status], without the subject. Exposed so a test can assert
  /// the mapping without building five widgets.
  static String labelFor(VendorUserStatus status) => switch (status) {
    VendorUserStatus.invited => 'Invited',
    VendorUserStatus.active => 'Active',
    VendorUserStatus.suspended => 'Suspended',
    VendorUserStatus.deactivated => 'Deactivated',
    VendorUserStatus.unknown => 'Unknown',
  };

  static SrTone _toneFor(VendorUserStatus status) => switch (status) {
    VendorUserStatus.invited => SrTone.amber,
    VendorUserStatus.active => SrTone.emerald,
    VendorUserStatus.suspended => SrTone.amber,
    VendorUserStatus.deactivated => SrTone.slate,
    VendorUserStatus.unknown => SrTone.slate,
  };

  static IconData _iconFor(VendorUserStatus status) => switch (status) {
    VendorUserStatus.invited => Icons.schedule_rounded,
    VendorUserStatus.active => Icons.check_rounded,
    VendorUserStatus.suspended => Icons.pause_rounded,
    VendorUserStatus.deactivated => Icons.block_rounded,
    VendorUserStatus.unknown => Icons.help_outline_rounded,
  };

  /// The full spoken form — "Membership status: Active".
  static String semanticsFor(
    VendorUserStatus status,
    VendorUserStatusKind kind,
  ) => '${kind.label}: ${labelFor(status)}';

  @override
  Widget build(BuildContext context) {
    final String value = labelFor(status);

    return Semantics(
      label: semanticsFor(status, kind),
      excludeSemantics: true,
      child: SrBadge(
        label: showPrefix ? '${kind.label.split(' ').first}: $value' : value,
        tone: _toneFor(status),
        icon: _iconFor(status),
      ),
    );
  }
}
