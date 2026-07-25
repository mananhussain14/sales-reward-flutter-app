import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/vendor_role_summary.dart';
import '../cubit/vendor_role_list_cubit.dart';
import '../widgets/vendor_role_card.dart';
import '../widgets/vendor_role_copy.dart';
import '../widgets/vendor_role_filter_bar.dart';

/// The shared role catalogue.
///
/// Backed by **one** call to `public.list_vendor_roles()` — zero arguments, the
/// Vendor derived from `auth.uid()` in SQL, both counts computed as scalar
/// aggregates in the same statement. The cubit is created and loaded once by the
/// Vendor shell, so entering this route a second time renders the rows already
/// held rather than issuing a second read, and coming back from a role's detail
/// screen does not reload the catalogue.
///
/// ## The screen says the catalogue is shared, twice
///
/// A Vendor Super Admin who opens Roles and finds *Retailer Owner* listed needs
/// to know why before they conclude something is wrong. The page description
/// states it, and a note beside the rows repeats it where a reader is actually
/// looking at one. Neither is decoration: the alternative — filtering the list
/// to what "looks like" a Vendor role — would require a scope column that does
/// not exist and would immediately disagree with the web page showing the same
/// six roles.
///
/// ## Refreshing
///
/// Two affordances for one action: pull-to-refresh, which is what a phone user
/// reaches for, and a header button, which is what a browser user reaches for
/// and what a keyboard or screen-reader user can actually operate. Both call the
/// same method, and that method ignores a second call while one read is in
/// flight — so a repeated tap cannot produce simultaneous requests.
class VendorRolesPage extends StatelessWidget {
  const VendorRolesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VendorRoleListCubit, VendorRoleListState>(
      builder: (BuildContext context, VendorRoleListState state) {
        final VendorRoleListCubit cubit = context.read<VendorRoleListCubit>();

        // The skeleton stands in only for the *first* read. A refresh over rows
        // already on screen keeps them, because they are still the last thing
        // the backend actually said.
        if (state.phase == VendorRoleListPhase.initial ||
            (state.phase == VendorRoleListPhase.loading &&
                state.roles.isEmpty)) {
          return const SrLoadingView(label: VendorRoleCopy.loadingList);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: PortalKind.vendorSuperAdmin.displayName,
                title: VendorRoleCopy.listTitle,
                description: VendorRoleCopy.listDescription,
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: VendorRoleCopy.refresh,
                    child: SrButton(
                      label: VendorRoleCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: VendorRoleCopy.refreshing,
                      onPressed: state.isRefreshing ? null : cubit.refresh,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SrSpacing.xxl),
              _Summary(state: state),
              if (state.roles.isNotEmpty) ...<Widget>[
                const SizedBox(height: SrSpacing.xxl),
                VendorRoleFilterBar(
                  searchTerm: state.searchTerm,
                  statusFilter: state.statusFilter,
                  availableStatuses: state.presentStatuses,
                  onSearchChanged: cubit.search,
                  onStatusChanged: cubit.filterByStatus,
                  onClear: cubit.clearFilters,
                ),
              ],
              const SizedBox(height: SrSpacing.xxl),
              _Body(state: state, cubit: cubit),
            ],
          ),
        );
      },
    );
  }
}

/// The figures the catalogue legitimately reports about itself.
///
/// Every one is counted from a value the backend returned. An unrecognised
/// status falls into **neither** the active nor the inactive bucket rather than
/// being folded into one, so the total is always the honest number and the
/// breakdown never claims to be exhaustive.
///
/// The inactive card and the mappings card appear only when they have something
/// to report, so a catalogue with no retired definitions is not shown a zero to
/// puzzle over.
class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final VendorRoleListState state;

  @override
  Widget build(BuildContext context) {
    if (state.roles.isEmpty) {
      return const SizedBox.shrink();
    }

    return SrCardGrid(
      children: <Widget>[
        SrStatCard(
          label: VendorRoleCopy.totalLabel,
          value: state.totalCount,
          hint: VendorRoleCopy.totalHint,
          icon: Icons.vpn_key_rounded,
        ),
        SrStatCard(
          label: VendorRoleCopy.activeLabel,
          value: state.activeCount,
          hint: VendorRoleCopy.activeHint,
          icon: Icons.check_circle_outline_rounded,
          tone: SrTone.emerald,
        ),
        if (state.inactiveCount > 0)
          SrStatCard(
            label: VendorRoleCopy.inactiveLabel,
            value: state.inactiveCount,
            hint: VendorRoleCopy.inactiveHint,
            icon: Icons.block_rounded,
            tone: SrTone.slate,
          ),
        if (state.totalPermissionMappings > 0)
          SrStatCard(
            label: VendorRoleCopy.mappingsLabel,
            value: state.totalPermissionMappings,
            hint: VendorRoleCopy.mappingsHint,
            icon: Icons.lock_outline_rounded,
            tone: SrTone.indigo,
          ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.cubit});

  final VendorRoleListState state;
  final VendorRoleListCubit cubit;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    // A failure with nothing loaded is the whole screen. `SrFailureView` decides
    // the wording and whether a retry is offered, per discriminant — a denial
    // never offers one, an outage always does.
    if (state.phase == VendorRoleListPhase.failed && state.roles.isEmpty) {
      return SrFailureView(failure: state.failure!, onRetry: cubit.load);
    }

    // Not reachable while the caller is authorized — they hold a role of this
    // very catalogue — but a defensive floor all the same.
    if (state.isEmpty) {
      return const SrEmptyState(
        icon: Icons.vpn_key_outlined,
        tone: SrTone.slate,
        title: VendorRoleCopy.emptyTitle,
        description: VendorRoleCopy.emptyBody,
      );
    }

    if (state.hasNoMatches) {
      return SrEmptyState(
        icon: Icons.search_off_rounded,
        title: VendorRoleCopy.noMatchesTitle,
        description: VendorRoleCopy.noMatchesBody,
        action: SrButton(
          label: VendorRoleCopy.clearFilters,
          variant: SrButtonVariant.outline,
          icon: Icons.filter_alt_off_outlined,
          onPressed: cubit.clearFilters,
        ),
      );
    }

    final List<VendorRoleSummary> visible = state.visibleRoles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A refresh that failed over rows already on screen says so without
        // throwing the rows away.
        if (state.phase == VendorRoleListPhase.failed) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: VendorRoleCopy.staleListTitle,
            message: VendorRoleCopy.staleListBody,
          ),
          const SizedBox(height: SrSpacing.lg),
        ],
        // The global-catalogue explanation, beside the rows it explains.
        const SrAlert(message: VendorRoleCopy.sharedCatalogueNote),
        const SizedBox(height: SrSpacing.lg),
        if (state.hasFilters) ...<Widget>[
          Text(
            'Showing ${visible.length} of ${state.totalCount}',
            style: SrTypography.caption.copyWith(color: sr.textSecondary),
          ),
          const SizedBox(height: SrSpacing.md),
        ],
        VendorRoleGrid(
          children: <Widget>[
            for (final VendorRoleSummary role in visible)
              VendorRoleCard(
                key: ValueKey<String>(role.roleId),
                role: role,
                onOpen: () =>
                    context.go(VendorNavigation.roleDetailPath(role.roleId)),
              ),
          ],
        ),
      ],
    );
  }
}
