import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../domain/entities/vendor_role_permission.dart';
import 'vendor_role_formatting.dart';

/// One permission mapped to the open role: the name over its description.
///
/// Exactly the two fields the web `/roles` page renders, through the same shape.
///
/// ## A simple vertical row, at every width
///
/// No table, no columns, no module grouping. A permission is a name and a
/// sentence, both of which wrap; a two-column layout would truncate one of them
/// on a phone and gain nothing on a desktop. The list is short — the longest
/// seeded role maps ten — so density is not the problem to solve here.
///
/// ## No status, no code, no action
///
/// There is no active/inactive pill on a permission, because there is no
/// permission status column anywhere in the schema and an inactive assigned
/// permission is unrepresentable. Whether these mappings are *effective* is
/// carried by the **role's** status, stated once at the top of the section
/// rather than implied per row.
///
/// The permission code is not returned and is never shown; the module is not
/// returned either, so nothing here groups. And there is no remove, edit or
/// assign affordance — not even a disabled one — because no backend anywhere in
/// the product can write a role→permission mapping.
class VendorRolePermissionTile extends StatelessWidget {
  const VendorRolePermissionTile({super.key, required this.permission});

  final VendorRolePermission permission;

  /// The spoken form — "Permission: Read RBAC. Sees roles and permissions."
  ///
  /// One node per permission rather than two, so a screen reader user walks a
  /// list of permissions rather than a list of disconnected fragments.
  static String semanticsFor(VendorRolePermission permission) =>
      'Permission: ${permission.name}. '
      '${formatPermissionDescription(permission.description)}';

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool hasDescription = permission.description != null;

    return Semantics(
      label: semanticsFor(permission),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: SrSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: SrSpacing.xxs),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: sr.textMuted,
              ),
            ),
            const SizedBox(width: SrSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // No maxLines: a long permission name wraps onto as many lines
                  // as it needs rather than being cut, because there is no code
                  // beside it to disambiguate a truncated one.
                  Text(
                    permission.name,
                    style: SrTypography.body.copyWith(
                      color: sr.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: SrSpacing.xxs),
                  Text(
                    formatPermissionDescription(permission.description),
                    style: SrTypography.caption.copyWith(
                      color: sr.textSecondary,
                      fontStyle: hasDescription
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
