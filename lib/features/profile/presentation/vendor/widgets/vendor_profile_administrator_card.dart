import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_administrator_profile.dart';
import 'vendor_profile_copy.dart';
import 'vendor_profile_initials.dart';
import 'vendor_profile_role_chips.dart';

/// The signed-in administrator, exactly as `get_my_vendor_profile()` describes
/// them.
///
/// ## Two fields, and only two
///
/// The display name, rendered **verbatim** — the database composed it, and this
/// widget neither splits it, trims it, re-joins it nor substitutes the
/// organization name for it — and the active role names, in the order the backend
/// sent them.
///
/// ## What is deliberately absent
///
/// No email, no mobile number, no profile status, no membership status, no
/// organization status, no created or updated timestamp, no profile id, no
/// membership id, no auth user id, no role code, no permission code, no metadata
/// and no avatar image. The contract returns none of them, so none of them can be
/// rendered here even by accident — and the three statuses in particular are
/// ACTIVE **by construction** for any caller who receives a row, so a badge built
/// from them could never change.
///
/// ## Read-only
///
/// No Edit button, no disabled field, no password or security link, no avatar
/// upload. There is no profile write path anywhere in this product.
class VendorProfileAdministratorCard extends StatelessWidget {
  const VendorProfileAdministratorCard({super.key, required this.profile});

  final VendorAdministratorProfile profile;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            label: VendorProfileCopy.administratorSemantics(
              profile.displayName,
            ),
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Initials computed from the name already on screen. There is no
                // avatar column and no identity bucket; nothing is fetched here.
                VendorProfileAvatar(name: profile.displayName),
                const SizedBox(width: SrSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        VendorProfileCopy.administratorSectionTitle,
                        style: SrTypography.caption.copyWith(
                          color: sr.textMuted,
                        ),
                      ),
                      const SizedBox(height: SrSpacing.xxs),
                      Text(
                        // Exactly as returned.
                        profile.displayName,
                        style: SrTypography.sectionTitle.copyWith(
                          color: sr.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SrSpacing.xl),
          Text(
            VendorProfileCopy.rolesTitle,
            style: SrTypography.label.copyWith(color: sr.foreground),
          ),
          const SizedBox(height: SrSpacing.xs),
          Text(
            VendorProfileCopy.rolesDescription,
            style: SrTypography.caption.copyWith(color: sr.textSecondary),
          ),
          const SizedBox(height: SrSpacing.md),
          VendorProfileRoleChips(roleNames: profile.roleNames),
        ],
      ),
    );
  }
}
