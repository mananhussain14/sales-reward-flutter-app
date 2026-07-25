import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_role_status.dart';

/// A role definition's lifecycle status, as a pill.
///
/// ## Colour is never the message
///
/// Every state carries its own word and its own glyph, so a reader who cannot
/// distinguish emerald from slate reads exactly the same facts. This matters
/// more here than anywhere else in the application: the status is what decides
/// whether the permission list beside it means anything, so a colour-only
/// distinction would hide the single most consequential fact on the screen.
///
/// The semantics label spells the pair out — "Role status: Inactive" — because a
/// screen reader announcing "Inactive" alone leaves the subject to be guessed.
///
/// ## An unknown token is neutral, and grants nothing
///
/// [VendorRoleStatus.unknown] renders "Unknown" in the slate tone with a
/// question glyph. The raw backend token is never shown — a future status must
/// not leak a database literal into the interface — and because the enum's
/// `isActive` and `grantsMappedPermissions` test `active` positively, nothing
/// downstream can mistake it for a live role. The role is still listed: losing
/// sight of a definition because its status is unfamiliar would be worse than
/// showing it plainly.
class VendorRoleStatusBadge extends StatelessWidget {
  const VendorRoleStatusBadge({
    super.key,
    required this.status,
    this.showPrefix = true,
  });

  final VendorRoleStatus status;

  /// Whether the subject appears in the visible label. When false it still
  /// appears in the semantics label, so the pair is never lost.
  final bool showPrefix;

  /// The subject, used in the visible prefix and in the spoken form.
  static const String subject = 'Role status';

  /// The label for [status], without the subject. Exposed so a test can assert
  /// the mapping without building three widgets.
  static String labelFor(VendorRoleStatus status) => switch (status) {
    VendorRoleStatus.active => 'Active',
    VendorRoleStatus.inactive => 'Inactive',
    VendorRoleStatus.unknown => 'Unknown',
  };

  static SrTone _toneFor(VendorRoleStatus status) => switch (status) {
    VendorRoleStatus.active => SrTone.emerald,
    VendorRoleStatus.inactive => SrTone.slate,
    VendorRoleStatus.unknown => SrTone.slate,
  };

  static IconData _iconFor(VendorRoleStatus status) => switch (status) {
    VendorRoleStatus.active => Icons.check_rounded,
    VendorRoleStatus.inactive => Icons.block_rounded,
    VendorRoleStatus.unknown => Icons.help_outline_rounded,
  };

  /// The full spoken form — "Role status: Active".
  static String semanticsFor(VendorRoleStatus status) =>
      '$subject: ${labelFor(status)}';

  @override
  Widget build(BuildContext context) {
    final String value = labelFor(status);

    return Semantics(
      label: semanticsFor(status),
      excludeSemantics: true,
      child: SrBadge(
        label: showPrefix ? 'Status: $value' : value,
        tone: _toneFor(status),
        icon: _iconFor(status),
      ),
    );
  }
}

/// A count with a glyph and a sentence — the summary line a role card carries
/// twice, for its permission mappings and for its own Vendor's members.
///
/// A plain row rather than an [SrBadge]: a badge is this product's *status*
/// pill, and a count is not a status. Making them look alike would invite a
/// reader to compare them, which is exactly the confusion the permission-count /
/// role-status distinction cannot afford.
class VendorRoleCountLine extends StatelessWidget {
  const VendorRoleCountLine({
    super.key,
    required this.icon,
    required this.label,
    this.muted = false,
  });

  final IconData icon;

  /// The already-formatted sentence — "6 permissions mapped", "No members in
  /// your Vendor". Formatting lives in `vendor_role_formatting.dart` so the
  /// wording has one definition.
  final String label;

  /// Renders the zero case in the muted treatment. The *wording* still carries
  /// the meaning; the tone only reinforces it.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final Color color = muted ? sr.textMuted : sr.textSecondary;

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: SrSpacing.xxs),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: SrSpacing.xs),
          // Expanded + soft wrap: a long count sentence at large text scale
          // grows the card downward rather than off the side of a phone.
          Expanded(
            child: Text(
              label,
              style: SrTypography.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
