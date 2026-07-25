import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_role_detail.dart';
import '../../../domain/entities/vendor_role_permission.dart';
import '../cubit/vendor_role_detail_cubit.dart';
import '../widgets/vendor_role_badges.dart';
import '../widgets/vendor_role_copy.dart';
import '../widgets/vendor_role_effectiveness_notice.dart';
import '../widgets/vendor_role_formatting.dart';
import '../widgets/vendor_role_permission_tile.dart';

/// One role definition, addressed by `role_id` from the route.
///
/// ## Two calls, in one order, once each
///
/// [VendorRoleDetailCubit] issues `get_vendor_role_detail` first and
/// `list_vendor_role_permissions` only after a row comes back. This widget's
/// only job in that sequence is to start it exactly once — from
/// [State.initState], which runs once per mounted route, and through an
/// idempotent `open` that ignores a repeat of the id it is already showing. A
/// rebuild, a router refresh or a theme change therefore issues nothing.
///
/// ## The route parameter is an address, not a permission
///
/// Typing an unknown id — or `not-a-uuid` — into the URL bar reaches this screen
/// and produces [VendorRoleDetailPhase.notFound], the same state for all of
/// them, because SQL returns zero rows for an unknown id and the repository
/// answers a malformed one locally without a request. The screen never says
/// whether the role exists, and never says it belongs to somebody else — the
/// catalogue is global, so there is nobody else for it to belong to.
///
/// ## Status stays on screen while the permissions are
///
/// The status pill sits in the header, the effectiveness notice sits directly
/// above the permission section, and the definition card repeats the status as a
/// labelled fact. The permission list reports what is *mapped*; an inactive role
/// grants none of it, and a reader must never be able to see the list without
/// the fact that qualifies it.
class VendorRoleDetailPage extends StatefulWidget {
  const VendorRoleDetailPage({super.key, required this.roleId});

  /// The `:roleId` segment, verbatim. Not validated here: the repository refuses
  /// a malformed id and answers exactly as the backend answers for an id that
  /// names no role, so a mistyped URL and an unknown one are one case.
  final String roleId;

  @override
  State<VendorRoleDetailPage> createState() => _VendorRoleDetailPageState();
}

class _VendorRoleDetailPageState extends State<VendorRoleDetailPage> {
  @override
  void initState() {
    super.initState();
    context.read<VendorRoleDetailCubit>().open(widget.roleId);
  }

  @override
  void didUpdateWidget(VendorRoleDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Navigating from one role straight to another reuses this element with a
    // new parameter. `open` is idempotent for the same id, so this is a no-op
    // unless the id genuinely changed.
    if (oldWidget.roleId != widget.roleId) {
      context.read<VendorRoleDetailCubit>().open(widget.roleId);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Reached by a deep link or a hard browser reload, where there is no list
    // page beneath this one to pop back to.
    context.go(VendorNavigation.roles);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VendorRoleDetailCubit, VendorRoleDetailState>(
      // The shell's session isolation empties this cubit when the signed-in
      // person changes. Returning to `initial` is that event: the previous
      // Vendor's member count is gone, and the same route is re-read under the
      // new caller's own identity.
      listenWhen:
          (VendorRoleDetailState previous, VendorRoleDetailState current) =>
              current.phase == VendorRoleDetailPhase.initial,
      listener: (BuildContext context, VendorRoleDetailState state) =>
          context.read<VendorRoleDetailCubit>().open(widget.roleId),
      builder: (BuildContext context, VendorRoleDetailState state) {
        final VendorRoleDetailCubit cubit = context
            .read<VendorRoleDetailCubit>();

        if (state.phase == VendorRoleDetailPhase.initial ||
            state.phase == VendorRoleDetailPhase.loading) {
          return const SrLoadingView(label: VendorRoleCopy.loadingDetail);
        }

        return SrPageBody(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: VendorRoleCopy.backToList,
                child: SrButton(
                  label: VendorRoleCopy.backToList,
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
    VendorRoleDetailState state,
    VendorRoleDetailCubit cubit,
  ) {
    switch (state.phase) {
      case VendorRoleDetailPhase.initial:
      case VendorRoleDetailPhase.loading:
        // Handled above; the loading view replaces the whole page.
        return const <Widget>[];

      case VendorRoleDetailPhase.notFound:
        return <Widget>[
          SrEmptyState(
            icon: Icons.vpn_key_off_outlined,
            title: VendorRoleCopy.detailNotFoundTitle,
            description: VendorRoleCopy.detailNotFoundBody,
            // No retry: the backend answered, and it will answer the same way.
            action: SrButton(
              label: VendorRoleCopy.backToList,
              variant: SrButtonVariant.outline,
              icon: Icons.arrow_back_rounded,
              onPressed: _back,
            ),
          ),
        ];

      case VendorRoleDetailPhase.failed:
        return <Widget>[
          SrFailureView(failure: state.failure!, onRetry: cubit.retryDetail),
        ];

      case VendorRoleDetailPhase.ready:
        final VendorRoleDetail detail = state.detail!;
        return <Widget>[
          SrPageHeader(
            eyebrow: VendorRoleCopy.detailEyebrow,
            title: detail.roleName,
          ),
          const SizedBox(height: SrSpacing.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: VendorRoleStatusBadge(status: detail.status),
          ),
          const SizedBox(height: SrSpacing.xxl),
          _Definition(detail: detail),
          const SizedBox(height: SrSpacing.xxl),
          // Above the section it qualifies, so the two are read in that order —
          // and it is silent for an active role rather than reassuring.
          VendorRoleEffectivenessNotice(status: detail.status),
          if (!detail.status.grantsMappedPermissions)
            const SizedBox(height: SrSpacing.lg),
          _PermissionsSection(state: state, cubit: cubit),
        ];
    }
  }
}

/// The role definition's own facts.
///
/// Every value came from `get_vendor_role_detail`. There is no role code, role
/// id, organization id, permission code, permission module, member name or
/// member id here — the deployed read returns none of them, and several are
/// refused on purpose. The role id is not displayed either: it is an internal
/// address, useful in a URL and noise on a screen.
class _Definition extends StatelessWidget {
  const _Definition({required this.detail});

  final VendorRoleDetail detail;

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: VendorRoleCopy.overviewTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Fact(
            label: VendorRoleCopy.descriptionLabel,
            value: formatDescription(detail.description),
            muted: detail.description == null,
          ),
          // Repeated as a labelled fact as well as a pill, so the status is
          // legible to a reader scanning the fields rather than the chrome.
          _Fact(
            label: VendorRoleCopy.statusLabel,
            value: VendorRoleStatusBadge.labelFor(detail.status),
          ),
          _Fact(
            label: VendorRoleCopy.permissionCountLabel,
            value: formatPermissionCount(detail.permissionCount),
          ),
          // Worded with the possessive because the definition is shared and this
          // number is not: it counts the caller's own Vendor and nobody else's.
          _Fact(
            label: VendorRoleCopy.assignedMembersLabel,
            value: formatAssignedMembers(detail.assignedMemberCount),
          ),
          _Fact(
            label: VendorRoleCopy.createdLabel,
            value: formatRoleDate(detail.createdAt),
          ),
        ],
      ),
    );
  }
}

/// The permissions mapped to this role.
///
/// Its own section, loaded by its own call, and degrading on its own: a role
/// whose permissions could not be read still has a name, a status and two counts
/// that came from a call which succeeded, and the retry here re-reads **only**
/// the companion.
///
/// There is no assign, remove or edit action, and no disabled one either: no
/// backend anywhere in the product can write a role→permission mapping, so an
/// affordance would advertise a capability that does not exist.
class _PermissionsSection extends StatelessWidget {
  const _PermissionsSection({required this.state, required this.cubit});

  final VendorRoleDetailState state;
  final VendorRoleDetailCubit cubit;

  @override
  Widget build(BuildContext context) {
    final VendorRoleDetail detail = state.detail!;

    return SrSectionCard(
      title: VendorRoleCopy.permissionsTitle,
      description: VendorRoleCopy.permissionsDescription,
      child: switch (state.permissionsPhase) {
        VendorRolePermissionsPhase.initial ||
        VendorRolePermissionsPhase.loading => const SrSkeletonScreen(
          label: 'Loading permissions',
          child: SrSkeletonList(rows: 3),
        ),

        VendorRolePermissionsPhase.failed => SrEmptyState(
          icon: Icons.cloud_off_rounded,
          title: VendorRoleCopy.permissionsUnavailableTitle,
          description: VendorRoleCopy.permissionsUnavailableBody,
          action: SrButton(
            label: VendorRoleCopy.retryPermissions,
            variant: SrButtonVariant.outline,
            icon: Icons.refresh_rounded,
            onPressed: cubit.retryPermissions,
          ),
        ),

        // A real, successful "this role grants nothing" — distinguishable from
        // "this is not a role" only because the detail read came back first.
        VendorRolePermissionsPhase.ready when state.permissions.isEmpty =>
          const SrEmptyState(
            icon: Icons.lock_open_outlined,
            tone: SrTone.slate,
            title: VendorRoleCopy.permissionsEmptyTitle,
            description: VendorRoleCopy.permissionsEmptyBody,
          ),

        VendorRolePermissionsPhase.ready => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Every returned row is still rendered and the count is still the
            // backend's; the note only says the two reads disagreed.
            if (state.permissionCountDisagrees) ...<Widget>[
              const SrAlert(
                tone: SrAlertTone.warning,
                title: VendorRoleCopy.countMismatchTitle,
                message: VendorRoleCopy.countMismatchBody,
              ),
              const SizedBox(height: SrSpacing.lg),
            ],
            // The order the backend sent, preserved. Keyed by position because
            // the contract returns no permission id — safe here precisely
            // because nothing reorders, filters or de-duplicates this list.
            for (final (int index, VendorRolePermission permission)
                in state.permissions.indexed)
              VendorRolePermissionTile(
                key: ValueKey<int>(index),
                permission: permission,
              ),
            Text(
              formatPermissionCount(detail.permissionCount),
              style: SrTypography.caption.copyWith(color: context.sr.textMuted),
            ),
          ],
        ),
      },
    );
  }
}

/// One label/value pair.
///
/// Stacks on a narrow phone and sits side by side once there is room, so a long
/// value never has to be truncated to fit beside its label. The pair is spoken
/// as one node so a screen reader reads "Role status, Inactive" rather than two
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
