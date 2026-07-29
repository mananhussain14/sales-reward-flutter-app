import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../../auth/domain/entities/retailer_capabilities.dart';
import '../../../../auth/presentation/bloc/session_bloc.dart';
import '../../../domain/entities/retailer_staff_invitation.dart';
import '../../../domain/entities/retailer_staff_lifecycle_action.dart';
import '../../../domain/entities/retailer_staff_member.dart';
import '../cubit/retailer_manage_staff_shops_cubit.dart';
import '../cubit/retailer_staff_cubit.dart';
import '../cubit/retailer_staff_lifecycle_cubit.dart';
import '../widgets/retailer_invitation_card.dart';
import '../widgets/retailer_invite_staff_form.dart';
import '../widgets/retailer_manage_staff_shops_copy.dart';
import '../widgets/retailer_manage_staff_shops_dialog.dart';
import '../widgets/retailer_staff_copy.dart';
import '../widgets/retailer_staff_lifecycle_confirmations.dart';
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
/// ## Manage shops: three presentation signals, and none of them a role label
///
/// The per-member editor is offered only when all three hold:
///
/// * the **shell** provided the write — the same `includeInvitations` marker the
///   Invite form uses, set once at construction by the Owner shell, so a
///   Manager's tree contains no shop-assignment machinery to render;
/// * the caller's **backend-derived capability hint** offers shop assignment.
///   `assign_staff_shops` is computed by the same resolver, on the same
///   permission (`RETAILER_STAFF_SHOP_ASSIGN`), that the write itself resolves
///   through, so the hint cannot drift from its gate;
/// * the **row itself** is one the backend described as an active, accepted
///   Sales Staff member.
///
/// None of the three is a role name compared in Dart, and none of them is
/// authorization. The database re-derives the caller, the Retailer, the
/// permission and the target's own role and status on every call. A false hint
/// is a reason not to advertise a dead end, never proof of anything.
///
/// Everything else here is still read-only: no resend, revoke, role change or
/// activation control anywhere — not disabled ones, none at all. The section
/// note says so, so the absence reads as scope rather than as a broken screen.
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

  /// Whether this caller's backend-derived hints offer shop assignment.
  ///
  /// Presentation only. See the class doc: the hint is computed by the resolver
  /// the write itself uses, and the write re-decides regardless.
  static bool _offersShopAssignment(BuildContext context) {
    final SessionState session = context.watch<SessionBloc>().state;
    return session is SessionActive &&
        session.portalContext.capabilities.allows(
          RetailerCapability.assignStaffShops,
        );
  }

  /// Whether this caller's backend-derived hints offer staff management.
  ///
  /// The **existing** server-derived capability, computed by the backend from
  /// the same resolver `set_retailer_staff_membership_status()` gates on
  /// (`RETAILER_STAFF_MANAGE`, mapped to `RETAILER_OWNER` alone). No second
  /// probe is added: a client-side permission call would duplicate this and be
  /// strictly worse, because this flag is derived from the very resolver the
  /// write uses.
  ///
  /// Presentation only, and it fails closed — every capability flag defaults to
  /// false, and the write re-decides regardless.
  static bool _offersStaffManagement(BuildContext context) {
    final SessionState session = context.watch<SessionBloc>().state;
    return session is SessionActive &&
        session.portalContext.capabilities.allows(
          RetailerCapability.manageStaff,
        );
  }

  @override
  Widget build(BuildContext context) {
    final bool offersShopAssignment = _offersShopAssignment(context);
    final bool offersStaffManagement = _offersStaffManagement(context);

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
              _Body(
                state: state,
                cubit: cubit,
                offersShopAssignment: offersShopAssignment,
                offersStaffManagement: offersStaffManagement,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.cubit,
    required this.offersShopAssignment,
    required this.offersStaffManagement,
  });

  final RetailerStaffState state;
  final RetailerStaffCubit cubit;
  final bool offersShopAssignment;
  final bool offersStaffManagement;

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

        // Owner only, for the same structural reason as the form below: the
        // Manager shell provides no `RetailerManageStaffShopsCubit`, so reading
        // one there would not merely be wrong, it would throw. `includeInvitations`
        // is the shell-set marker, stable from the first frame.
        //
        // Deliberately outside the search branch: a committed save must be
        // acknowledged whatever is typed in the filter, and a filter that hid
        // the confirmation of a write would be the worst possible place to hide
        // something.
        if (cubit.includeInvitations) ...<Widget>[
          _ManageShopsOutcome(
            members: state.members,
            // A read. It re-reads `list_retailer_staff_members()` and nothing
            // else, and it is offered only when a save landed and the roster
            // beside it did not reload.
            onRefreshRoster: cubit.rereadMembers,
          ),
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
          _RosterSection(
            state: state,
            cubit: cubit,
            offersShopAssignment: offersShopAssignment,
            offersStaffManagement: offersStaffManagement,
          ),
          if (state.showsInvitations) ...<Widget>[
            const SizedBox(height: SrSpacing.xxxl),
            _InvitationSection(state: state, cubit: cubit),
          ],
        ],
      ],
    );
  }
}

/// One roster card, bound to the lifecycle state for **its own membership**.
///
/// A `BlocBuilder` per card rather than one around the grid, so a request for one
/// colleague rebuilds one card. More importantly, every question this widget asks
/// the cubit is keyed by [RetailerStaffMember.membershipId] — `isBusyFor`,
/// `problemFor`, `noticeFor` — which is what makes it impossible for a request
/// for staff A to render progress, a refusal or an acknowledgement on staff B.
///
/// When [lifecycleAction] is null the card is built without any lifecycle
/// affordance at all, and no cubit is read. That is the case for every excluded
/// row: a Retailer Owner, the caller themselves, an invited or suspended
/// membership, an unsupported role, **any membership appearing more than once in
/// the roster**, and every caller without the staff-management hint.
class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.onManageShops,
    required this.lifecycleAction,
  });

  final RetailerStaffMember member;
  final VoidCallback? onManageShops;
  final RetailerStaffLifecycleAction? lifecycleAction;

  @override
  Widget build(BuildContext context) {
    final RetailerStaffLifecycleAction? action = lifecycleAction;
    if (action == null) {
      return RetailerStaffMemberCard(
        member: member,
        onManageShops: onManageShops,
      );
    }

    return BlocBuilder<
      RetailerStaffLifecycleCubit,
      RetailerStaffLifecycleState
    >(
      builder: (BuildContext context, RetailerStaffLifecycleState state) {
        final String id = member.membershipId;
        return RetailerStaffMemberCard(
          member: member,
          onManageShops: onManageShops,
          lifecycleAction: action,
          lifecycleBusy: state.isBusyFor(id),
          lifecycleNotice: state.noticeFor(id),
          lifecycleProblem: state.problemFor(id),
          onLifecycle: () => _confirmAndApply(context, action),
        );
      },
    );
  }

  /// Asks first, then applies.
  ///
  /// The dialog is the screen's job and the cubit knows nothing about it, so a
  /// test can exercise the write without a widget *and* a screen cannot skip the
  /// confirmation by calling something cheaper — the only path to
  /// [RetailerStaffLifecycleCubit.apply] from this feature's UI is through here.
  ///
  /// Cancelling calls nothing at all: no RPC, no state change, no optimistic
  /// flip.
  Future<void> _confirmAndApply(
    BuildContext context,
    RetailerStaffLifecycleAction action,
  ) async {
    final RetailerStaffLifecycleCubit cubit = context
        .read<RetailerStaffLifecycleCubit>();

    final bool confirmed = await confirmRetailerStaffLifecycle(
      context,
      action: action,
      // Display text from the canonical roster. It is never sent anywhere and is
      // never an authorization input.
      memberName: member.fullName,
    );

    if (confirmed) {
      // The membership id from the canonical roster row — the same
      // `organization_members.id` the read returned. Never a profile id, an auth
      // user id, an email, an invitation id or a position in a filtered list.
      await cubit.apply(member.membershipId, action);
    }
  }
}

/// The Manage Shops result, and the roster-change watcher that goes with it.
///
/// ## Why the result lives here rather than in the editor
///
/// A committed save closes the editor, deliberately — an editor left armed over
/// a change that already happened is an editor whose Save button resubmits it.
/// So the success sentence is shown beside the roster, which is both the thing
/// the save changed and the thing that was re-read to prove it.
///
/// ## Two separate sentences, never merged
///
/// When the write committed but the roster reread did not land, that is stated
/// as an additional notice with its own action — and that action is a **read**.
/// Nothing on this screen repeats a write on anyone's behalf, least of all one
/// that already succeeded.
class _ManageShopsOutcome extends StatelessWidget {
  const _ManageShopsOutcome({
    required this.members,
    required this.onRefreshRoster,
  });

  /// The canonical roster rows, or null when none has been read.
  final List<RetailerStaffMember>? members;

  /// Re-reads the roster alone. Never a write.
  final VoidCallback onRefreshRoster;

  @override
  Widget build(BuildContext context) {
    final RetailerManageStaffShopsCubit cubit = context
        .read<RetailerManageStaffShopsCubit>();

    // The roster is the authority on who exists. When it changes underneath an
    // open editor — a refresh, the reread after a save, or a backend answer that
    // no longer contains the target — the editor is closed rather than left
    // collecting a selection with nowhere to send it.
    final List<String> membershipIds = <String>[
      for (final RetailerStaffMember member
          in members ?? const <RetailerStaffMember>[])
        member.membershipId,
    ];
    // The lifecycle cubit is told the same thing, for the same reason: a
    // colleague who has left the roster is no longer a row an outcome can be
    // attached to, and a notice left hanging over a card that is gone would
    // attach itself to whichever row took its place.
    //
    // Read with `read` rather than `watch`, and only for its `rosterChanged`
    // hook — this widget renders none of its state. The per-card builders own
    // that, keyed by membership id.
    final RetailerStaffLifecycleCubit lifecycle = context
        .read<RetailerStaffLifecycleCubit>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        cubit.rosterChanged(membershipIds);
        lifecycle.rosterChanged(membershipIds);
      }
    });

    return BlocBuilder<
      RetailerManageStaffShopsCubit,
      RetailerManageStaffShopsState
    >(
      // Only the settled result belongs on the page. Everything else — the
      // selection, the options, a refusal — is the editor's, and rebuilding the
      // whole screen for a ticked checkbox would be wasteful and would fight the
      // dialog for the person's attention.
      buildWhen:
          (
            RetailerManageStaffShopsState previous,
            RetailerManageStaffShopsState current,
          ) =>
              previous.notice != current.notice ||
              previous.change != current.change ||
              previous.rosterRereadFailed != current.rosterRereadFailed ||
              previous.isOpen != current.isOpen,
      builder: (BuildContext context, RetailerManageStaffShopsState state) {
        final RetailerManageShopsNotice? notice = state.notice;
        // While the editor is open it shows its own notice; showing the same one
        // twice, in two places, would read as two separate things happening.
        if (notice == null || state.isOpen) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              liveRegion: true,
              child: SrAlert(
                tone: notice.isSuccess
                    ? SrAlertTone.success
                    : (notice.isUnresolved
                          ? SrAlertTone.warning
                          : SrAlertTone.error),
                title: RetailerManageStaffShopsCopy.noticeTitle(notice),
                message: RetailerManageStaffShopsCopy.noticeBody(
                  notice,
                  change: state.change,
                ),
              ),
            ),
            if (state.rosterRereadFailed) ...<Widget>[
              const SizedBox(height: SrSpacing.md),
              const SrAlert(
                tone: SrAlertTone.warning,
                title: RetailerManageStaffShopsCopy.rosterRereadFailedTitle,
                message: RetailerManageStaffShopsCopy.rosterRereadFailedBody,
              ),
              const SizedBox(height: SrSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  button: true,
                  label: RetailerManageStaffShopsCopy.refreshRoster,
                  child: SrButton(
                    label: RetailerManageStaffShopsCopy.refreshRoster,
                    variant: SrButtonVariant.outline,
                    icon: Icons.refresh_rounded,
                    // A read, and only a read.
                    onPressed: onRefreshRoster,
                  ),
                ),
              ),
            ],
            const SizedBox(height: SrSpacing.xxl),
          ],
        );
      },
    );
  }
}

/// The staff roster.
class _RosterSection extends StatelessWidget {
  const _RosterSection({
    required this.state,
    required this.cubit,
    required this.offersShopAssignment,
    required this.offersStaffManagement,
  });

  final RetailerStaffState state;
  final RetailerStaffCubit cubit;

  /// Whether this caller's backend-derived hint offers shop assignment.
  final bool offersShopAssignment;

  /// Whether this caller's backend-derived hint offers staff management.
  final bool offersStaffManagement;

  /// Whether [member] gets a Manage shops control.
  ///
  /// Three signals, all from the backend, and none of them a role label compared
  /// in Dart. See [RetailerStaffPage] for why each is presentation scope rather
  /// than authorization.
  bool _canManageShopsFor(RetailerStaffMember member) =>
      cubit.includeInvitations &&
      offersShopAssignment &&
      member.isEditableSalesStaff;

  /// The membership ids the lifecycle control may be offered for.
  ///
  /// ## Computed over the WHOLE roster, never the visible subset
  ///
  /// `state.members` is what the backend returned; `state.visibleMembers` is
  /// that list narrowed by a **local search term**. The duplicate rule depends
  /// on counting every row a membership produced, so computing it from the
  /// filtered list would be a real defect: a search that happened to match only
  /// one row of a two-role member would make that membership look unique, and
  /// the control would be offered for a target the RPC refuses — including,
  /// for an Owner who also holds another role, on the row that is not the Owner
  /// row.
  ///
  /// So the set is built from the full roster and only then asked about a
  /// visible card.
  Set<String> _eligibleMemberships() {
    if (!offersStaffManagement || !cubit.includeInvitations) {
      // No hint, or a shell that does not hold the write. Nothing is offered,
      // and nothing is computed.
      return const <String>{};
    }
    return RetailerStaffLifecycleEligibility.eligibleMemberships(
      state.members ?? const <RetailerStaffMember>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<RetailerStaffMember> visible = state.visibleMembers;
    final Set<String> lifecycleEligible = _eligibleMemberships();

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
                _MemberCard(
                  member: member,
                  // The whole member is handed to the editor, which takes the
                  // membership id from it. Nothing here reads an id, renders
                  // one, or addresses a row by its position in `visible` — that
                  // list is filtered by a local search and its indices mean
                  // nothing.
                  onManageShops: _canManageShopsFor(member)
                      ? () => showRetailerManageStaffShopsDialog(
                          context,
                          member: member,
                        )
                      : null,
                  // Derived over the whole roster, then asked about this row.
                  lifecycleAction: RetailerStaffLifecycleEligibility.actionFor(
                    member,
                    lifecycleEligible,
                  ),
                ),
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
