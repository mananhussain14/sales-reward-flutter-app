import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_user_detail.dart';
import '../cubit/vendor_user_detail_cubit.dart';
import '../widgets/vendor_user_badges.dart';
import '../widgets/vendor_user_copy.dart';
import '../widgets/vendor_user_formatting.dart';
import '../widgets/vendor_user_role_chips.dart';

/// One Vendor user, addressed by `membership_id` from the route.
///
/// ## One call, once
///
/// [VendorUserDetailCubit] issues `get_vendor_user_detail` and nothing else —
/// roles arrive inside the same row, so there is no companion read to sequence.
/// This widget's only job is to start it exactly once: from [State.initState],
/// which runs once per mounted route, through an idempotent `open` that ignores
/// a repeat of the id it is already showing. A rebuild, a router refresh or a
/// theme change therefore issues nothing.
///
/// ## The route parameter is an address, not a permission
///
/// Typing another Vendor's membership id — or a Retailer's — into the URL bar
/// reaches this screen and produces [VendorUserDetailPhase.notFound], the same
/// state an unknown id and a malformed id produce, because SQL returns zero rows
/// for all four. The screen never says whether the person exists.
class VendorUserDetailPage extends StatefulWidget {
  const VendorUserDetailPage({super.key, required this.membershipId});

  /// The `:membershipId` segment, verbatim. Not validated here: the repository
  /// refuses a malformed id and answers exactly as the backend answers for an id
  /// that names no row, so a mistyped URL and a foreign one are one case.
  final String membershipId;

  @override
  State<VendorUserDetailPage> createState() => _VendorUserDetailPageState();
}

class _VendorUserDetailPageState extends State<VendorUserDetailPage> {
  @override
  void initState() {
    super.initState();
    context.read<VendorUserDetailCubit>().open(widget.membershipId);
  }

  @override
  void didUpdateWidget(VendorUserDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Navigating from one user straight to another reuses this element with a
    // new parameter. `open` is idempotent for the same id, so this is a no-op
    // unless the id genuinely changed.
    if (oldWidget.membershipId != widget.membershipId) {
      context.read<VendorUserDetailCubit>().open(widget.membershipId);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Reached by a deep link or a hard browser reload, where there is no list
    // page beneath this one to pop back to.
    context.go(VendorNavigation.users);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VendorUserDetailCubit, VendorUserDetailState>(
      // The shell's session isolation empties this cubit when the signed-in
      // person changes. Returning to `initial` is that event: the previous
      // Vendor's colleague is gone, and the same route is re-read under the new
      // caller's own identity — which either loads their user or, far more
      // likely, answers the non-leaking "not available".
      listenWhen:
          (VendorUserDetailState previous, VendorUserDetailState current) =>
              current.phase == VendorUserDetailPhase.initial,
      listener: (BuildContext context, VendorUserDetailState state) =>
          context.read<VendorUserDetailCubit>().open(widget.membershipId),
      builder: (BuildContext context, VendorUserDetailState state) {
        final VendorUserDetailCubit cubit = context
            .read<VendorUserDetailCubit>();

        if (state.phase == VendorUserDetailPhase.initial ||
            state.phase == VendorUserDetailPhase.loading) {
          return const SrLoadingView(label: VendorUserCopy.loadingDetail);
        }

        return SrPageBody(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: VendorUserCopy.backToList,
                child: SrButton(
                  label: VendorUserCopy.backToList,
                  variant: SrButtonVariant.ghost,
                  size: SrButtonSize.sm,
                  icon: Icons.arrow_back_rounded,
                  onPressed: _back,
                ),
              ),
            ),
            const SizedBox(height: SrSpacing.lg),
            ..._content(state, cubit),
          ],
        );
      },
    );
  }

  List<Widget> _content(
    VendorUserDetailState state,
    VendorUserDetailCubit cubit,
  ) {
    switch (state.phase) {
      case VendorUserDetailPhase.initial:
      case VendorUserDetailPhase.loading:
        // Handled above; the loading view replaces the whole page.
        return const <Widget>[];

      case VendorUserDetailPhase.notFound:
        return <Widget>[
          SrEmptyState(
            icon: Icons.person_search_outlined,
            title: VendorUserCopy.detailNotFoundTitle,
            description: VendorUserCopy.detailNotFoundBody,
            // No retry: the backend answered, and it will answer the same way.
            action: SrButton(
              label: VendorUserCopy.backToList,
              variant: SrButtonVariant.outline,
              icon: Icons.arrow_back_rounded,
              onPressed: _back,
            ),
          ),
        ];

      case VendorUserDetailPhase.failed:
        return <Widget>[
          SrFailureView(failure: state.failure!, onRetry: cubit.retry),
        ];

      case VendorUserDetailPhase.ready:
        final VendorUserDetail detail = state.detail!;
        return <Widget>[
          SrPageHeader(
            eyebrow: VendorUserCopy.detailEyebrow,
            title: detail.displayName,
          ),
          const SizedBox(height: SrSpacing.lg),
          Wrap(
            spacing: SrSpacing.sm,
            runSpacing: SrSpacing.sm,
            children: <Widget>[
              VendorUserStatusBadge(
                status: detail.profileStatus,
                kind: VendorUserStatusKind.profile,
              ),
              VendorUserStatusBadge(
                status: detail.membershipStatus,
                kind: VendorUserStatusKind.membership,
              ),
            ],
          ),
          const SizedBox(height: SrSpacing.xxl),
          _Roles(detail: detail),
          const SizedBox(height: SrSpacing.xxl),
          _Membership(detail: detail),
        ];
    }
  }
}

/// The roles this membership holds.
///
/// Its own section rather than a line in the overview, because it is the answer
/// to "what can this person do here" and is the reason a Vendor opens the screen.
/// There is no assign or remove action: role assignment is web-only and has no
/// mobile contract, and a disabled button would advertise a capability this
/// build does not have.
class _Roles extends StatelessWidget {
  const _Roles({required this.detail});

  final VendorUserDetail detail;

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: VendorUserCopy.rolesTitle,
      description: detail.hasNoRoles
          ? VendorUserCopy.noRolesBody
          : formatRoleCount(detail.roleNames.length),
      child: VendorUserRoleChips(roleNames: detail.roleNames),
    );
  }
}

/// The membership's lifecycle facts.
///
/// Every value came from `get_vendor_user_detail`. There is no email, phone
/// number, auth user id, profile id, organization id, role id or code, or
/// permission of any kind — the deployed read returns none of them. The
/// membership id is not displayed either: it is an internal address, useful in a
/// URL and noise on a screen.
class _Membership extends StatelessWidget {
  const _Membership({required this.detail});

  final VendorUserDetail detail;

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: VendorUserCopy.overviewTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Fact(
            label: VendorUserCopy.profileStatusLabel,
            value: VendorUserStatusBadge.labelFor(detail.profileStatus),
          ),
          _Fact(
            label: VendorUserCopy.membershipStatusLabel,
            value: VendorUserStatusBadge.labelFor(detail.membershipStatus),
          ),
          _Fact(
            label: VendorUserCopy.membershipCreatedLabel,
            value: formatUserDate(detail.membershipCreatedAt),
          ),
          // A null joined_at is a real answer, said in words. It describes the
          // date and asserts nothing about the status, which has its own badge.
          _Fact(
            label: VendorUserCopy.joinedLabel,
            value: formatJoined(detail.joinedAt),
            muted: detail.joinedAt == null,
          ),
          // Shown only when there is one. A "Not deactivated" row would be a
          // label for an absent fact, and an invitation to read a lifecycle
          // state out of a date rather than out of the status.
          if (detail.deactivatedAt != null)
            _Fact(
              label: VendorUserCopy.deactivatedLabel,
              value: formatUserDate(detail.deactivatedAt!),
            ),
        ],
      ),
    );
  }
}

/// One label/value pair.
///
/// Stacks on a narrow phone and sits side by side once there is room, so a long
/// value never has to be truncated to fit beside its label. The pair is spoken
/// as one node so a screen reader reads "Joined, Not joined yet" rather than two
/// disconnected fragments.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;

  /// Renders the value in the muted, italic treatment reserved for "there is no
  /// value here" phrases.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    final Widget labelText = Text(
      label,
      style: SrTypography.caption.copyWith(color: sr.textMuted),
    );
    final Widget valueText = Text(
      value,
      style: SrTypography.body.copyWith(
        color: muted ? sr.textMuted : sr.foreground,
        fontStyle: muted ? FontStyle.italic : FontStyle.normal,
      ),
    );

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: SrSpacing.md),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  labelText,
                  const SizedBox(height: SrSpacing.xxs),
                  valueText,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(width: 200, child: labelText),
                const SizedBox(width: SrSpacing.md),
                Expanded(child: valueText),
              ],
            );
          },
        ),
      ),
    );
  }
}
