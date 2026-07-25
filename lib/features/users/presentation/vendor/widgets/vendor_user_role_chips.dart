import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import 'vendor_user_copy.dart';

/// The roles a user holds, as chips.
///
/// ## The empty array is a real answer, and it is not a privilege
///
/// `role_names` is `NOT NULL` and may be empty, and an empty array means exactly
/// what it says: this person holds no active role. It renders as the neutral
/// "No active role" — the same wording the web uses, so the two clients agree —
/// and never as a default. An absent role is the one place in this feature where
/// a wrong guess would grant something, so there is deliberately no fallback
/// chip anywhere in this widget.
///
/// ## Order is the backend's
///
/// The array arrives sorted by role name then role id. Nothing here re-sorts,
/// de-duplicates or filters it: a `Set` would hide a genuine backend duplication
/// bug rather than prevent one, and the ACTIVE-role filter already ran in SQL.
///
/// ## Names, never codes
///
/// The backend returns `Vendor Super Admin`, not `VENDOR_SUPER_ADMIN`. Codes are
/// authorization vocabulary and are not returned at all; nothing here maps a
/// name back to one, and a role chip grants nothing — this milestone has no
/// action for it to unlock.
///
/// A long role name wraps inside its own chip rather than overflowing, and the
/// chips themselves wrap onto further lines, so a user with six long roles is a
/// taller card and never a horizontal scroll.
class VendorUserRoleChips extends StatelessWidget {
  const VendorUserRoleChips({super.key, required this.roleNames});

  final List<String> roleNames;

  /// The spoken form of the whole list — "Roles: Vendor Super Admin, Finance
  /// Admin", or the empty phrase. One sentence rather than N separate nodes, so
  /// a screen reader user is not made to walk six chips to learn one fact.
  static String semanticsFor(List<String> roleNames) => roleNames.isEmpty
      ? VendorUserCopy.noRoles
      : '${VendorUserCopy.rolesTitle}: ${roleNames.join(', ')}';

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      label: semanticsFor(roleNames),
      excludeSemantics: true,
      child: roleNames.isEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: sr.textMuted,
                ),
                const SizedBox(width: SrSpacing.xs),
                Flexible(
                  child: Text(
                    VendorUserCopy.noRoles,
                    style: SrTypography.caption.copyWith(
                      color: sr.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            )
          : Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              children: <Widget>[
                for (final String role in roleNames) _RoleChip(name: role),
              ],
            ),
    );
  }
}

/// One role name.
///
/// An indigo-tinted chip at the control radius rather than an [SrBadge]: a badge
/// is the product's *status* pill, and a role is not a status. Making them look
/// alike would invite a reader to compare them.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final SrToneColors colors = context.sr.tone(SrTone.indigo);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.sm,
        vertical: SrSpacing.xs,
      ),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(SrRadii.sm),
        border: Border.all(color: colors.ring),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.shield_outlined, size: 12, color: colors.foreground),
          const SizedBox(width: SrSpacing.xs),
          // Flexible + soft wrap: a long role name grows the chip downward
          // rather than pushing the row off the screen.
          Flexible(
            child: Text(
              name,
              style: SrTypography.badge.copyWith(color: colors.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
