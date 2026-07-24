import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/app_role.dart';

/// The Vendor Super Admin landing screen.
///
/// A **placeholder** reproducing the layout and copy of § 5.2 of
/// `docs/mobile-ui-design-handoff.md` — the page header, the four-up stat grid
/// collapsed to one column, and the three "Quick actions" shortcuts — while
/// reading nothing from the backend.
///
/// Every metric therefore renders as **"Unavailable"**, which is [SrStatCard]'s
/// treatment of `null`. Deliberately not `0`: zero would be a figure, and there
/// is no figure here. The handoff states that rule twice, and it is one of the
/// honesty properties the port must not lose.
///
/// The web assembles these counts from four separate round trips (V-01). The
/// feature matrix proposes `get_vendor_admin_dashboard_summary()` to replace
/// them; it does not exist yet.
class VendorDashboardPage extends StatelessWidget {
  const VendorDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SrPageBody(
      children: <Widget>[
        SrPageHeader(
          eyebrow: AppRole.vendorSuperAdmin.displayName,
          title: 'Dashboard',
          description:
              "Overview of your organization's members, access control, and "
              'recorded activity.',
        ),
        const SizedBox(height: SrSpacing.xxl),

        // Labels, hints and tones verbatim from § 5.2.
        const SrCardGrid(
          children: <Widget>[
            SrStatCard(
              label: 'Active Members',
              value: null,
              hint: 'Active memberships in this organization',
              icon: Icons.group_rounded,
              tone: SrTone.indigo,
            ),
            SrStatCard(
              label: 'Active Roles',
              value: null,
              hint: 'Roles available in the role catalogue',
              icon: Icons.vpn_key_rounded,
              tone: SrTone.emerald,
            ),
            SrStatCard(
              label: 'Permissions',
              value: null,
              hint: 'Permissions defined across all modules',
              icon: Icons.lock_outline_rounded,
              tone: SrTone.amber,
            ),
            SrStatCard(
              label: 'Audit Events',
              value: null,
              hint: 'Recorded admin actions for this organization',
              icon: Icons.receipt_long_rounded,
              tone: SrTone.slate,
            ),
          ],
        ),

        const SizedBox(height: SrSpacing.xxxl),
        const SrSectionHeader(title: 'Quick actions'),
        const SizedBox(height: SrSpacing.lg),
        const SrCardGrid(
          children: <Widget>[
            SrShortcutCard(
              label: 'Manage Retailers',
              icon: Icons.storefront_rounded,
            ),
            SrShortcutCard(
              label: 'Product catalog',
              icon: Icons.inventory_2_rounded,
              tone: SrTone.emerald,
            ),
            SrShortcutCard(
              label: 'Audit logs',
              icon: Icons.receipt_long_rounded,
              tone: SrTone.slate,
            ),
          ],
        ),

        const SizedBox(height: SrSpacing.xxxl),
        SrSectionCard(
          title: 'Foundation build',
          description:
              'This shell, its navigation and this theme are in place. No '
              'Vendor screen reads from Supabase yet.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Wrap, not Row: badge clusters must reflow on a narrow phone.
              const Wrap(
                spacing: SrSpacing.sm,
                runSpacing: SrSpacing.sm,
                children: <Widget>[
                  SrBadge(
                    label: 'Shell ready',
                    tone: SrTone.emerald,
                    icon: Icons.check_rounded,
                  ),
                  SrBadge(
                    label: 'Data pending',
                    tone: SrTone.amber,
                    icon: Icons.schedule_rounded,
                  ),
                ],
              ),
              const SizedBox(height: SrSpacing.lg),
              Text(
                'Every Vendor feature is phase 3 in the feature matrix, and '
                'conditional on open question Q4 — whether Vendor '
                'administration belongs on mobile at all.',
                style: SrTypography.body.copyWith(
                  color: context.sr.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
