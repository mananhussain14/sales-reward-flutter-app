import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/app_role.dart';

/// The Retailer Manager landing screen.
///
/// A **placeholder** for the staff roster — the only portal page a Manager may
/// read, and therefore this role's landing, matching the web's
/// `LANDING_ROUTES.retailerStaff`.
///
/// It shows the mobile translation of the web's roster table: a card list rather
/// than a table, because a five-column table on a 360px viewport is neither
/// readable nor tappable. The list is empty here because nothing is read.
///
/// Two facts this screen must not misrepresent, both decided in SQL:
///
/// * A Manager sees **ACTIVE members only**. That narrowing lives inside
///   `list_retailer_staff_members()` — the same RPC an Owner calls — and is
///   never re-implemented on the client.
/// * A Manager cannot manage staff. The denial is enforced by permission
///   mapping, not by this screen hiding a button.
class RetailerManagerStaffPage extends StatelessWidget {
  const RetailerManagerStaffPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SrPageBody(
      children: <Widget>[
        SrPageHeader(
          eyebrow: AppRole.retailerManager.displayName,
          title: 'Staff',
          description: 'The active members of your retail organization.',
        ),
        const SizedBox(height: SrSpacing.xxl),

        const SrEmptyState(
          icon: Icons.group_outlined,
          tone: SrTone.indigo,
          title: 'No roster loaded',
          description:
              'The staff roster is not connected to Supabase in this build.',
        ),

        const SizedBox(height: SrSpacing.xxl),
        SrSectionCard(
          title: 'Read-only by design',
          description:
              'This role reads the roster. Inviting, re-sending and revoking '
              'belong to the Retailer Owner.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Wrap(
                spacing: SrSpacing.sm,
                runSpacing: SrSpacing.sm,
                children: <Widget>[
                  SrBadge(
                    label: 'Active members only',
                    tone: SrTone.emerald,
                    icon: Icons.check_rounded,
                  ),
                  SrBadge(label: 'Enforced in SQL', tone: SrTone.slate),
                ],
              ),
              const SizedBox(height: SrSpacing.lg),
              Text(
                'Open question Q3: a Manager currently has no way to read their '
                'own retailer\'s name, because the portal-context RPC filters '
                'for Retailer Owner. Until that is resolved this shell cannot '
                'caption itself with the organization it belongs to.',
                style: SrTypography.bodyMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
