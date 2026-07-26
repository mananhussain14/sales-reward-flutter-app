import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import 'vendor_profile_copy.dart';

/// The caller's own active roles, as chips.
///
/// ## Order is the backend's
///
/// The array arrives ordered by role name then role id, fixed in SQL. Nothing
/// here re-sorts, de-duplicates or filters it: the ACTIVE-role filter already ran
/// in the database, and re-ordering in Dart would apply a collation the database
/// does not use, so the mobile order would drift from the web's.
///
/// ## The empty array is defensive, and it is not a privilege
///
/// An authorized caller always holds at least the ACTIVE `Vendor Super Admin`
/// assignment that authorized them — withdrawing it denies the read rather than
/// emptying the array. The empty branch is therefore unreachable in practice and
/// is kept only so an unexpected answer renders safely instead of crashing. It
/// shows the neutral "No active role" and never a default chip: an absent role is
/// the one place where a wrong guess would grant something.
///
/// ## Names, never codes
///
/// The backend returns `Vendor Super Admin`, not `VENDOR_SUPER_ADMIN`. Codes are
/// authorization vocabulary and are not returned at all; nothing here maps a name
/// back to one, and a role chip grants nothing — this milestone has no action for
/// it to unlock.
///
/// A long role name wraps inside its own chip rather than overflowing, and the
/// chips themselves wrap onto further lines, so an administrator with several
/// long roles is a taller card and never a horizontal scroll.
class VendorProfileRoleChips extends StatelessWidget {
  const VendorProfileRoleChips({super.key, required this.roleNames});

  final List<String> roleNames;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    if (roleNames.isEmpty) {
      return Semantics(
        label: VendorProfileCopy.rolesSemantics(roleNames),
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.person_outline_rounded, size: 14, color: sr.textMuted),
            const SizedBox(width: SrSpacing.xs),
            Flexible(
              child: Text(
                VendorProfileCopy.noRoles,
                style: SrTypography.caption.copyWith(
                  color: sr.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // The whole list is announced as one sentence by the card above, and each
    // chip is independently focusable and labelled for a reader moving chip by
    // chip. `explicitChildNodes` keeps both: the group node carries the summary
    // and the chips stay as children rather than being merged into it.
    return Semantics(
      label: VendorProfileCopy.rolesSemantics(roleNames),
      explicitChildNodes: true,
      child: Wrap(
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
/// alike would invite a reader to compare them — and this screen shows no status
/// at all, because an authorized caller's three statuses are ACTIVE by
/// construction and the backend returns none of them.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final SrToneColors colors = context.sr.tone(SrTone.indigo);

    return Semantics(
      label: VendorProfileCopy.roleSemantics(name),
      excludeSemantics: true,
      child: Container(
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
      ),
    );
  }
}
