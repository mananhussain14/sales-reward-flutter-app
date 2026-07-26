import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../../auth/presentation/bloc/session_bloc.dart';
import '../../../domain/entities/vendor_dashboard_summary.dart';
import '../cubit/vendor_dashboard_cubit.dart';
import '../widgets/vendor_dashboard_copy.dart';
import '../widgets/vendor_dashboard_metric_card.dart';
import '../widgets/vendor_dashboard_quick_links.dart';

/// The Vendor Super Admin landing screen.
///
/// Backed by `public.get_vendor_admin_dashboard_summary()` — **one call, zero
/// arguments**, replacing the five round trips the web pays for the same four
/// numbers. The cubit is created and loaded once by the Vendor shell, so entering
/// this route a second time renders the figures already held rather than
/// re-reading them.
///
/// ## Two sources, and neither is asked for the other's fact
///
/// * The four **counts** come from the summary RPC and from nowhere else.
/// * The **organization name** comes from the trusted Session / PortalContext the
///   application already holds, resolved by `get_my_portal_context()`.
///
/// Nothing is sent from the second to the first — the function takes no arguments,
/// so it could not accept an organization id even if one were offered — and the
/// name is never queried from `organizations` directly. Both contracts derive
/// their Vendor from `auth.uid()` through the same resolver with the same
/// lowest-organization-id tie-break, so the name shown and the Vendor-scoped
/// counts shown describe the same organization by construction rather than by
/// coincidence.
///
/// **The name is a caption, not a scope.** Two of the four figures are not
/// properties of the organization it names, which is why the metrics are split
/// into two headed sections rather than listed under it.
///
/// ## Read-only, and it does not pretend otherwise
///
/// There is no chart, trend, percentage, comparison, sparkline, time series,
/// revenue, sales, receipt, claim, coin, payout or campaign figure here, and no
/// disabled one either. There is no Retailer, Product, shop, assignment or
/// invitation count, because the contract returns none — a card with an invented
/// number would be worse than no card. There is no dashboard customisation, no
/// Vendor profile editing and no write action of any kind: the backend function
/// is `STABLE` and this screen has nothing to call that is not.
///
/// ## Refreshing
///
/// Two affordances for one action: pull-to-refresh, which is what a phone user
/// reaches for, and a header button, which is what a browser user reaches for and
/// what a keyboard or screen-reader user can actually operate. Both call the same
/// method, and that method ignores a second call while a read is in flight — so a
/// repeated tap cannot produce simultaneous requests.
///
/// A refresh **replaces the whole summary atomically** and never merges a field:
/// the four counts come from one statement and describe one instant. A refresh
/// that fails keeps the figures and says so above them, because they are still
/// the last thing the backend actually said.
class VendorDashboardPage extends StatelessWidget {
  const VendorDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The trusted organization name, from the session the application already
    // resolved. Read through `vendor` directly rather than through a portal-kind
    // switch: the block is null unless the backend resolved a Vendor for this
    // caller, so there is no branch here that could caption this page with a
    // Retailer's name.
    //
    // `watch` rather than `read` so a re-resolution updates the caption in the
    // same frame the shell clears the counts.
    final SessionState session = context.watch<SessionBloc>().state;
    final String? organizationName = session is SessionActive
        ? session.portalContext.vendor?.organizationName
        : null;

    return BlocBuilder<VendorDashboardCubit, VendorDashboardState>(
      builder: (BuildContext context, VendorDashboardState state) {
        final VendorDashboardCubit cubit = context.read<VendorDashboardCubit>();

        // The skeleton stands in only for the *first* read. A refresh over figures
        // already on screen keeps them.
        if (state.isFirstLoad) {
          return const SrLoadingView(label: VendorDashboardCopy.loading);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: PortalKind.vendorSuperAdmin.displayName,
                title: VendorDashboardCopy.title,
                description: VendorDashboardCopy.description,
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: VendorDashboardCopy.refresh,
                    child: SrButton(
                      label: VendorDashboardCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: VendorDashboardCopy.refreshing,
                      // Disabled while a read is in flight, so a repeated press
                      // cannot issue two requests for the same summary.
                      onPressed: state.isRefreshing ? null : cubit.refresh,
                    ),
                  ),
                ],
              ),
              if (organizationName != null) ...<Widget>[
                const SizedBox(height: SrSpacing.lg),
                _OrganizationCaption(name: organizationName),
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

/// The trusted Vendor organization name.
///
/// Rendered as a caption rather than as the page title, and omitted entirely when
/// the session carries none — the application's rule everywhere else is that a
/// missing name is left out rather than replaced with a placeholder, because a
/// fabricated organization name on an administration screen is a claim about
/// whose data is on it.
class _OrganizationCaption extends StatelessWidget {
  const _OrganizationCaption({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      label: '${VendorDashboardCopy.organizationLabel} $name',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: SrSpacing.xxs),
            child: Icon(Icons.apartment_rounded, size: 16, color: sr.textMuted),
          ),
          const SizedBox(width: SrSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  VendorDashboardCopy.organizationLabel,
                  style: SrTypography.caption.copyWith(color: sr.textMuted),
                ),
                const SizedBox(height: SrSpacing.xxs),
                Text(
                  name,
                  style: SrTypography.sectionTitle.copyWith(
                    color: sr.foreground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The summary, or the reason there is none.
class _Body extends StatelessWidget {
  const _Body({required this.state, required this.cubit});

  final VendorDashboardState state;
  final VendorDashboardCubit cubit;

  @override
  Widget build(BuildContext context) {
    // A failure with nothing loaded is the whole screen. `SrFailureView` decides
    // the wording and whether a retry is offered, per discriminant — a denial
    // never offers one, an outage always does, and neither ever names a
    // permission code or a backend object.
    //
    // Critically, no card renders here. A denied caller must never be shown four
    // zeros: "you may not read this summary" and "this Vendor has nothing" are
    // opposite claims, and the backend deliberately refuses to say which gate
    // stopped them.
    if (state.hasFailedFirstRead) {
      return SrFailureView(failure: state.failure!, onRetry: cubit.load);
    }

    final VendorDashboardSummary? summary = state.summary;
    if (summary == null) {
      // Unreachable: `isFirstLoad` covers "nothing read yet" above and
      // `hasFailedFirstRead` covers "the read failed". Kept as a shrink rather
      // than an assertion so an unforeseen ordering renders nothing at all — never
      // a zero-filled grid.
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A refresh that failed over figures already on screen says so without
        // throwing them away. Non-blocking: the cards below stay exactly as they
        // were, and the Refresh button remains the retry.
        if (state.isStale) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: VendorDashboardCopy.staleTitle,
            message: VendorDashboardCopy.staleBody,
          ),
          const SizedBox(height: SrSpacing.xxl),
        ],

        // -- the two Vendor-scoped counts ------------------------------------
        const SrSectionHeader(
          title: VendorDashboardCopy.vendorSectionTitle,
          description: VendorDashboardCopy.vendorSectionDescription,
        ),
        const SizedBox(height: SrSpacing.lg),
        SrCardGrid(
          children: <Widget>[
            VendorDashboardMetricCard(
              label: VendorDashboardCopy.activeMembersLabel,
              value: summary.activeMemberCount,
              hint: VendorDashboardCopy.activeMembersHint,
              icon: Icons.group_rounded,
              scope: VendorMetricScope.vendor,
            ),
            VendorDashboardMetricCard(
              label: VendorDashboardCopy.auditEventsLabel,
              value: summary.auditEventCount,
              hint: VendorDashboardCopy.auditEventsHint,
              icon: Icons.receipt_long_rounded,
              scope: VendorMetricScope.vendor,
              tone: SrTone.blue,
            ),
          ],
        ),
        const SizedBox(height: SrSpacing.lg),
        const _Note(text: VendorDashboardCopy.auditEventsNote),

        const SizedBox(height: SrSpacing.xxxl),

        // -- the two deployment-wide catalogue counts -------------------------
        const SrSectionHeader(
          title: VendorDashboardCopy.catalogueSectionTitle,
          description: VendorDashboardCopy.catalogueSectionDescription,
        ),
        const SizedBox(height: SrSpacing.lg),
        SrCardGrid(
          children: <Widget>[
            VendorDashboardMetricCard(
              label: VendorDashboardCopy.activeRoleDefinitionsLabel,
              value: summary.catalogActiveRoleCount,
              hint: VendorDashboardCopy.activeRoleDefinitionsHint,
              icon: Icons.vpn_key_rounded,
              scope: VendorMetricScope.sharedCatalogue,
              tone: SrTone.emerald,
            ),
            VendorDashboardMetricCard(
              label: VendorDashboardCopy.permissionDefinitionsLabel,
              value: summary.catalogPermissionCount,
              hint: VendorDashboardCopy.permissionDefinitionsHint,
              icon: Icons.lock_outline_rounded,
              scope: VendorMetricScope.sharedCatalogue,
              tone: SrTone.slate,
            ),
          ],
        ),

        const SizedBox(height: SrSpacing.xxxl),

        // -- navigation, carrying no figures ----------------------------------
        const SrSectionHeader(
          title: VendorDashboardCopy.quickLinksTitle,
          description: VendorDashboardCopy.quickLinksDescription,
        ),
        const SizedBox(height: SrSpacing.lg),
        const VendorDashboardQuickLinks(),
      ],
    );
  }
}

/// A one-line qualifier beneath a metric group.
///
/// Used for the single thing about these figures a reader could otherwise get
/// wrong on sight: the audit total has no time window.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: SrSpacing.xxs),
            child: Icon(
              Icons.info_outline_rounded,
              size: 16,
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
      ),
    );
  }
}
