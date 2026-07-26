import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/vendor_audit_log_entry.dart';
import '../cubit/vendor_audit_log_cubit.dart';
import '../widgets/vendor_audit_log_copy.dart';
import '../widgets/vendor_audit_log_formatting.dart';
import '../widgets/vendor_audit_log_tile.dart';

/// The Vendor's recorded administrative history.
///
/// Backed by `public.list_vendor_audit_logs(...)` — a fixed page size of 50 and
/// a two-part keyset cursor, with the Vendor derived from `auth.uid()` in SQL.
/// The cubit is created and loaded once by the Vendor shell, so entering this
/// route a second time renders the pages already held rather than re-reading
/// them.
///
/// ## Read-only, and it does not pretend otherwise
///
/// There is no export, CSV, PDF, delete, clear, retention or filter action here,
/// and no disabled one either. There is no detail route: no audit detail read
/// exists to open, and `entity_id` and `actor_profile_id` are deliberately never
/// returned, so no row on this screen holds an address for anything. An
/// affordance that cannot act is a promise about a feature that has not been
/// built.
///
/// ## Refreshing
///
/// Two affordances for one action: pull-to-refresh, which is what a phone user
/// reaches for, and a header button, which is what a browser user reaches for and
/// what a keyboard or screen-reader user can actually operate. Both call the same
/// method, and that method ignores a second call while any read is in flight — so
/// a repeated tap cannot produce simultaneous requests.
///
/// A refresh **replaces** the loaded pages rather than being merged onto them,
/// and it resets the end-of-history flag from the page it returned. New events
/// arrive at the head; they can never appear in an *older* page, because the
/// cursor comparison is strictly-less-than against a fixed position.
///
/// ## Reaching further back
///
/// An explicit button, not an infinite scroll. Deterministic — one press, one
/// page, and the press is disabled while a page is in flight — and operable by a
/// keyboard and a screen reader, neither of which can trigger a scroll-position
/// heuristic. Nothing auto-fetches, so the app never walks an append-only table
/// that grows forever on a reader's behalf.
class VendorAuditLogsPage extends StatelessWidget {
  const VendorAuditLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VendorAuditLogCubit, VendorAuditLogState>(
      builder: (BuildContext context, VendorAuditLogState state) {
        final VendorAuditLogCubit cubit = context.read<VendorAuditLogCubit>();

        // The skeleton stands in only for the *first* read. A refresh over rows
        // already on screen keeps them, because they are still the last thing
        // the backend actually said.
        if (state.phase == VendorAuditLogPhase.initial ||
            (state.phase == VendorAuditLogPhase.loading &&
                state.events.isEmpty)) {
          return const SrLoadingView(label: VendorAuditLogCopy.loadingList);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            // Narrower than the catalogue pages on purpose. This is a reading
            // surface rather than a grid, and a line of prose stretched across a
            // desktop browser is harder to scan, not easier.
            maxWidth: SrSpacing.formMaxWidth,
            children: <Widget>[
              SrPageHeader(
                eyebrow: PortalKind.vendorSuperAdmin.displayName,
                title: VendorAuditLogCopy.listTitle,
                description: VendorAuditLogCopy.listDescription,
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: VendorAuditLogCopy.refresh,
                    child: SrButton(
                      label: VendorAuditLogCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: VendorAuditLogCopy.refreshing,
                      // Disabled while *any* read is in flight, including an
                      // older page: a refresh mid-page would discard the cursor
                      // that request is still using.
                      onPressed: state.isBusy ? null : cubit.refresh,
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

  final VendorAuditLogState state;
  final VendorAuditLogCubit cubit;

  @override
  Widget build(BuildContext context) {
    // A failure with nothing loaded is the whole screen. `SrFailureView` decides
    // the wording and whether a retry is offered, per discriminant — a denial
    // never offers one, an outage always does, and neither ever names a
    // permission code or a backend object.
    if (state.hasFailedFirstRead) {
      return SrFailureView(failure: state.failure!, onRetry: cubit.load);
    }

    // A Vendor with nothing recorded. A real, reachable state, and worded as a
    // fact rather than as a problem — and deliberately not as a denial, which is
    // the opposite claim.
    if (state.isEmpty) {
      return const SrEmptyState(
        icon: Icons.history_toggle_off_rounded,
        tone: SrTone.slate,
        title: VendorAuditLogCopy.emptyTitle,
        description: VendorAuditLogCopy.emptyBody,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A refresh that failed over rows already on screen says so without
        // throwing the rows away.
        if (state.isStale) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: VendorAuditLogCopy.staleTitle,
            message: VendorAuditLogCopy.staleBody,
          ),
          const SizedBox(height: SrSpacing.lg),
        ],
        _LoadedCount(count: state.loadedCount),
        const SizedBox(height: SrSpacing.md),
        _Feed(events: state.events),
        const SizedBox(height: SrSpacing.xxl),
        _Footer(state: state, cubit: cubit),
      ],
    );
  }
}

/// How many events are currently held.
///
/// Labelled "loaded", never "total". The contract returns no total, and
/// presenting a loaded count as one would understate a history by however many
/// pages have not been asked for.
class _LoadedCount extends StatelessWidget {
  const _LoadedCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Text(
      VendorAuditLogCopy.loadedCount(count),
      style: SrTypography.caption.copyWith(color: sr.textMuted),
    );
  }
}

/// The feed itself: the events in the backend's order, under a heading for each
/// local calendar day.
///
/// Nothing is re-sorted, grouped by anything but the day, or filtered. The
/// backend's `occurred_at desc, audit_log_id desc` is total and is what the
/// cursor depends on, so the order on screen is the order the next page
/// continues from.
class _Feed extends StatelessWidget {
  const _Feed({required this.events});

  final List<VendorAuditLogEntry> events;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    DateTime? currentDay;

    for (final VendorAuditLogEntry entry in events) {
      if (currentDay == null || !isSameLocalDay(currentDay, entry.occurredAt)) {
        currentDay = entry.occurredAt;
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: SrSpacing.xl));
        }
        children.add(VendorAuditLogDayHeading(day: entry.occurredAt));
        children.add(const SizedBox(height: SrSpacing.md));
      } else {
        children.add(const SizedBox(height: SrSpacing.md));
      }

      children.add(
        VendorAuditLogTile(
          // The audit log id is unique and stable, so a refresh that returns the
          // same rows reuses their elements instead of rebuilding the feed.
          key: ValueKey<String>(entry.auditLogId),
          entry: entry,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// What sits under the feed: the way further back, or the end of it.
///
/// Exactly one of three things, and never two: an older-page control, the
/// end-of-history line, or — while the end is unknown and nothing is loadable —
/// nothing at all.
class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.cubit});

  final VendorAuditLogState state;
  final VendorAuditLogCubit cubit;

  @override
  Widget build(BuildContext context) {
    if (state.showsEndOfHistory) {
      return const _EndOfHistory();
    }
    if (!state.canLoadMore) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // An older page that failed is a smaller event than a failed refresh:
        // everything above stays, and only this request is retried. The button
        // below keeps its own label so the retry is the same action, not a
        // second one.
        if (state.loadMoreFailure != null) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: VendorAuditLogCopy.loadMoreFailedTitle,
            message: VendorAuditLogCopy.loadMoreFailedBody,
          ),
          const SizedBox(height: SrSpacing.lg),
        ],
        Center(
          child: Semantics(
            button: true,
            label: state.loadMoreFailure != null
                ? VendorAuditLogCopy.retryLoadMore
                : VendorAuditLogCopy.loadMore,
            child: SrButton(
              label: state.loadMoreFailure != null
                  ? VendorAuditLogCopy.retryLoadMore
                  : VendorAuditLogCopy.loadMore,
              variant: SrButtonVariant.outline,
              icon: Icons.history_rounded,
              loading: state.isLoadingMore,
              loadingLabel: VendorAuditLogCopy.loadingMore,
              // Disabled while any read is in flight, so a repeated press
              // cannot issue two requests for the same page.
              onPressed: state.isBusy ? null : cubit.loadMore,
            ),
          ),
        ),
      ],
    );
  }
}

/// The end of the recorded history.
///
/// Stated as a fact about *this Vendor's* record rather than as a claim that
/// nothing else ever happened: events filed against a Retailer organization are
/// not in this feed by design.
class _EndOfHistory extends StatelessWidget {
  const _EndOfHistory();

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      label:
          '${VendorAuditLogCopy.endOfHistoryTitle}. '
          '${VendorAuditLogCopy.endOfHistoryBody}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: SrSpacing.xxs),
            child: Icon(
              Icons.vertical_align_bottom_rounded,
              size: 16,
              color: sr.textMuted,
            ),
          ),
          const SizedBox(width: SrSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  VendorAuditLogCopy.endOfHistoryTitle,
                  style: SrTypography.caption.copyWith(
                    color: sr.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SrSpacing.xxs),
                Text(
                  VendorAuditLogCopy.endOfHistoryBody,
                  style: SrTypography.caption.copyWith(color: sr.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
