import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/app_role.dart';

/// The Retailer Manager landing screen.
///
/// A **placeholder** for the staff roster — the only portal page a Manager may
/// read in full, and therefore this role's landing (RM-01). Sending them to the
/// overview instead would bounce them straight off it.
///
/// It shows the mobile translation of the web's roster table: a **card list**
/// rather than a table, per § 4.2 — *"never horizontally scroll a table on a
/// phone"*. The list is empty because nothing is read.
///
/// ## Two facts this screen must not misrepresent
///
/// * A Manager sees **ACTIVE members only**. That narrowing lives inside
///   `list_retailer_staff_members()` — the same RPC an Owner calls — and the
///   role-flow map is emphatic that a Flutter client *"needs no role logic at
///   all here"*. Render what came back.
/// * A Manager cannot manage staff. The denial is enforced by permission
///   mapping, not by this screen hiding a button. When the invitation sections
///   are built they must be driven by the **backend-returned status**
///   (`ok` / `denied` / `unavailable`), reproducing `showsInvitationSection`,
///   `showsInviteSection` and `showsInviteForm` — never by a client-side role
///   string.
///
/// Note the distinction the map draws: an **empty** roster and a **denied**
/// invitation section must look different. One is an empty-state card; the other
/// is simply absent.
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
          title: 'No staff yet',
          // Reason-free: the copy never explains why, because the only thing
          // that could produce a failure here is a database error whose detail
          // must not reach a client.
          description:
              'The staff roster is not connected to Supabase in this build.',
        ),

        const SizedBox(height: SrSpacing.xxxl),
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
                "own retailer's name, because the portal-context RPC filters "
                'for Retailer Owner. Until that is resolved this shell captions '
                'itself with the portal name rather than the organization.',
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
