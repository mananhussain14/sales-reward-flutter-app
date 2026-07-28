import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/retailer_staff_invitation.dart';
import '../../../domain/entities/retailer_staff_member.dart';
import '../cubit/retailer_staff_cubit.dart';
import '../widgets/retailer_invitation_card.dart';
import '../widgets/retailer_invite_staff_form.dart';
import '../widgets/retailer_staff_copy.dart';
import '../widgets/retailer_staff_member_card.dart';

/// The Retailer staff screen, for both the Owner and the Manager.
///
/// ## One page, two roles, and the difference is data rather than branching
///
/// The Owner and the Manager see the same widget. What differs is what the
/// backend returned and whether the invitation section applies at all — both
/// carried in the cubit's state, so this page has no `switch (role)` and no
/// permission logic.
///
/// The Manager's screen shows only the roster because
/// `list_retailer_staff_invitations()` resolves through
/// `RETAILER_STAFF_MANAGE` and raises `42501` for them. Not calling it is a
/// courtesy — issuing a request whose only outcome is a refusal would put a
/// denial notice on a screen where nothing is wrong — and never an authorization
/// decision: the backend still decides, and would start answering if the
/// permission were granted.
///
/// Likewise, a Manager seeing only ACTIVE members is the database answering a
/// narrower question (`and (v_can_manage or m.status = 'ACTIVE')`). This page
/// applies no equivalent filter and renders exactly the rows it was given.
///
/// ## One write, and only for the role whose shell asked for it
///
/// The Owner's screen carries the Invite Staff form; the Manager's does not,
/// which is the same arrangement the invitation history already had and rests on
/// the same fact — both contracts resolve through `RETAILER_STAFF_MANAGE`, so a
/// Manager would be refused either. `includeInvitations` is read from the cubit
/// rather than from [role] because it is set once at construction by the shell,
/// which makes it stable from the first frame; the phase-derived
/// `state.showsInvitations` only settles after a read.
///
/// It remains presentation scope and never authorization: the backend decides on
/// every call, and a hidden form is not a boundary. The Retailer Owner shell is
/// also the only place `RetailerInviteStaffCubit` is provided, so the Manager's
/// tree contains no invitation-sending machinery at all.
///
/// Everything else here is still read-only: no resend, revoke, role change,
/// activation or shop-assignment control anywhere — not disabled ones, none at
/// all. The section note says so, so the absence reads as scope rather than as a
/// broken screen.
class RetailerStaffPage extends StatefulWidget {
  const RetailerStaffPage({super.key, required this.role});

  /// Which shell this page is being rendered in. Used **only** for the eyebrow
  /// and the description — never to decide what to read or what to show.
  final PortalKind role;

  @override
  State<RetailerStaffPage> createState() => _RetailerStaffPageState();
}

/// Stateful only to own the first read.
///
/// The shell creates the cubit but deliberately does not load it, so the tab a
/// user actually opens is the one that issues RPCs. `loadOnce` is a no-op once
/// the roster phase has left `initial`, which is what makes returning to an
/// already-loaded tab read nothing.
class _RetailerStaffPageState extends State<RetailerStaffPage> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame so the reads cannot emit into a widget
    // tree that is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RetailerStaffCubit>().loadOnce();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RetailerStaffCubit, RetailerStaffState>(
      builder: (BuildContext context, RetailerStaffState state) {
        final RetailerStaffCubit cubit = context.read<RetailerStaffCubit>();

        if (state.isInitialLoading) {
          return const SrLoadingView(label: RetailerStaffCopy.loading);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: widget.role.displayName,
                title: RetailerStaffCopy.title,
                description: state.showsInvitations
                    ? RetailerStaffCopy.ownerDescription
                    : RetailerStaffCopy.managerDescription,
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: RetailerStaffCopy.refresh,
                    child: SrButton(
                      label: RetailerStaffCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: RetailerStaffCopy.refreshing,
                      onPressed: state.isRefreshing ? null : cubit.refresh,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SrSpacing.xxl),
              _Body(state: state, cubit: cubit),
            ],
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.cubit});

  final RetailerStaffState state;
  final RetailerStaffCubit cubit;

  @override
  Widget build(BuildContext context) {
    // The whole screen fails only when the roster — the section that is always
    // present — could not be read at all. An invitation failure never takes the
    // screen, because the roster beside it may be perfectly good.
    if (state.hasRosterFailedOutright && !state.showsInvitations) {
      return SrRetailerProblemView(
        problem: state.rosterProblem!,
        onRetry: cubit.load,
      );
    }
    if (state.hasRosterFailedOutright && state.hasInvitationsFailedOutright) {
      // Both genuinely failed. One notice, not two.
      return SrRetailerProblemView(
        problem: state.rosterProblem!,
        onRetry: cubit.load,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.isRosterStale || state.isInvitationsStale) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: RetailerStaffCopy.staleTitle,
            message: RetailerStaffCopy.staleBody,
          ),
          const SizedBox(height: SrSpacing.xxl),
        ],

        if (!state.showsInvitations) ...<Widget>[
          const _Note(text: RetailerStaffCopy.managerScopeNote),
          const SizedBox(height: SrSpacing.xl),
        ],

        // Owner only, and deliberately outside the search branch below: the
        // form is an action rather than a row, so filtering the lists must not
        // take it off the screen — least of all while a submission is in
        // flight.
        if (cubit.includeInvitations) ...<Widget>[
          RetailerInviteStaffForm(
            // A read. It re-reads `list_retailer_staff_invitations()` and
            // nothing else, and it is offered only when a send landed and the
            // history beside it did not reload.
            onRefreshHistory: cubit.rereadInvitations,
          ),
          const SizedBox(height: SrSpacing.xxl),
        ],

        // Hidden when there is genuinely nothing on the screen to filter.
        if (state.hasAnyContent) ...<Widget>[
          SrSearchField(
            label: RetailerStaffCopy.searchLabel,
            hint: RetailerStaffCopy.searchHint,
            placeholder: RetailerStaffCopy.searchPlaceholder,
            term: state.searchTerm,
            onChanged: cubit.searchChanged,
          ),
          const SizedBox(height: SrSpacing.xxl),
        ],

        if (state.isSearchEmpty)
          SrEmptyState(
            icon: Icons.search_off_rounded,
            tone: SrTone.slate,
            title: RetailerStaffCopy.searchEmptyTitle,
            description: RetailerStaffCopy.searchEmptyBody,
            action: SrButton(
              label: 'Clear search',
              variant: SrButtonVariant.outline,
              icon: Icons.close_rounded,
              onPressed: () => cubit.searchChanged(''),
            ),
          )
        else ...<Widget>[
          _RosterSection(state: state, cubit: cubit),
          if (state.showsInvitations) ...<Widget>[
            const SizedBox(height: SrSpacing.xxxl),
            _InvitationSection(state: state, cubit: cubit),
          ],
        ],
      ],
    );
  }
}

/// The staff roster.
class _RosterSection extends StatelessWidget {
  const _RosterSection({required this.state, required this.cubit});

  final RetailerStaffState state;
  final RetailerStaffCubit cubit;

  @override
  Widget build(BuildContext context) {
    final List<RetailerStaffMember> visible = state.visibleMembers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SrSectionHeader(
          title: RetailerStaffCopy.rosterTitle,
          description: state.members == null
              ? null
              : RetailerStaffCopy.showing(
                  visible.length,
                  state.members!.length,
                ),
        ),
        const SizedBox(height: SrSpacing.lg),

        if (state.hasRosterFailedOutright)
          // This section alone failed. Scoped copy and a scoped retry, so the
          // screen never claims the invitation history beside it failed too.
          SrRetailerProblemView(
            problem: state.rosterProblem!,
            onRetry: cubit.refresh,
          )
        else if (state.isRosterEmpty)
          const SrEmptyState(
            icon: Icons.group_outlined,
            tone: SrTone.slate,
            title: RetailerStaffCopy.rosterEmptyTitle,
            description: RetailerStaffCopy.rosterEmptyBody,
          )
        else
          SrResponsiveGrid(
            twoUpThreshold: 720,
            threeUpThreshold: 1200,
            children: <Widget>[
              for (final RetailerStaffMember member in visible)
                RetailerStaffMemberCard(member: member),
            ],
          ),
      ],
    );
  }
}

/// The invitation history. Owner only — see [RetailerStaffPage].
class _InvitationSection extends StatelessWidget {
  const _InvitationSection({required this.state, required this.cubit});

  final RetailerStaffState state;
  final RetailerStaffCubit cubit;

  @override
  Widget build(BuildContext context) {
    final List<RetailerStaffInvitation> visible = state.visibleInvitations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SrSectionHeader(
          title: RetailerStaffCopy.invitationsTitle,
          description: RetailerStaffCopy.invitationsDescription,
        ),
        const SizedBox(height: SrSpacing.lg),
        const _Note(text: RetailerStaffCopy.invitationsReadOnlyNote),
        const SizedBox(height: SrSpacing.lg),

        if (state.hasInvitationsFailedOutright)
          SrRetailerProblemView(
            problem: state.invitationProblem!,
            onRetry: cubit.refresh,
          )
        else if (state.isInvitationsEmpty)
          const SrEmptyState(
            icon: Icons.mail_outline_rounded,
            tone: SrTone.slate,
            title: RetailerStaffCopy.invitationsEmptyTitle,
            description: RetailerStaffCopy.invitationsEmptyBody,
          )
        else
          SrResponsiveGrid(
            twoUpThreshold: 760,
            threeUpThreshold: 1240,
            children: <Widget>[
              for (final RetailerStaffInvitation invitation in visible)
                RetailerInvitationCard(invitation: invitation),
            ],
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: SrSpacing.xxs),
          child: Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: sr.textMuted,
          ),
        ),
        const SizedBox(width: SrSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: SrTypography.caption.copyWith(color: sr.textMuted),
          ),
        ),
      ],
    );
  }
}
