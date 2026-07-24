import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/app_role.dart';

/// The Vendor Super Admin landing screen.
///
/// A **placeholder**. It demonstrates the SalesReward theme on a real dashboard
/// layout — the page header, the metric grid, a section card, the status pills —
/// and it reads nothing from the backend.
///
/// Every metric therefore renders as **Unavailable**, which is [SrStatCard]'s
/// honest treatment of `null`. It is deliberately not `0`: zero would be a
/// figure, and there is no figure here.
///
/// The web counterpart assembles these counts from four separate round trips.
/// The feature matrix proposes `get_vendor_admin_dashboard_summary()` to replace
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
              'Platform-wide administration: retailers, catalogue, access and '
              'audit.',
        ),
        const SizedBox(height: SrSpacing.xxl),

        // The web renders these in a responsive grid. On mobile they stack, and
        // pair up once there is room for two.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const List<(String, String, IconData, SrTone)> metrics =
                <(String, String, IconData, SrTone)>[
                  (
                    'Retailers',
                    'Active retail organizations',
                    Icons.storefront_rounded,
                    SrTone.indigo,
                  ),
                  (
                    'Products',
                    'Items in the catalogue',
                    Icons.inventory_2_rounded,
                    SrTone.emerald,
                  ),
                  (
                    'Members',
                    'Users across all organizations',
                    Icons.group_rounded,
                    SrTone.amber,
                  ),
                  (
                    'Audit events',
                    'Recorded in the last 30 days',
                    Icons.receipt_long_rounded,
                    SrTone.slate,
                  ),
                ];

            final bool twoUp = constraints.maxWidth >= 520;
            final double itemWidth = twoUp
                ? (constraints.maxWidth - SrSpacing.lg) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: SrSpacing.lg,
              runSpacing: SrSpacing.lg,
              children: <Widget>[
                for (final (String, String, IconData, SrTone) metric in metrics)
                  SizedBox(
                    width: itemWidth,
                    child: SrStatCard(
                      label: metric.$1,
                      value: null,
                      hint: metric.$2,
                      icon: metric.$3,
                      tone: metric.$4,
                    ),
                  ),
              ],
            );
          },
        ),

        const SizedBox(height: SrSpacing.xxl),
        SrSectionCard(
          title: 'Foundation build',
          description:
              'This shell, its navigation and this theme are in place. No '
              'Vendor screen reads from Supabase yet.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Wrap, not Row: badge clusters must reflow on a narrow phone
              // rather than overflow.
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
                'Vendor administration is phase 3 in the mobile feature matrix, '
                'and conditional on open question Q4 — whether it belongs on '
                'mobile at all.',
                style: SrTypography.bodyMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
