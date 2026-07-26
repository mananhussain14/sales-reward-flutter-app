import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/result/read_result.dart';
import '../../../data/datasources/vendor_audit_log_rpc_data_source.dart';
import '../../../domain/entities/vendor_audit_log_entry.dart';
import '../../../domain/repositories/vendor_audit_log_repository.dart';

part 'vendor_audit_log_state.dart';

/// The calling Vendor's recorded administrative history, newest first.
///
/// Backed by repeated calls to `public.list_vendor_audit_logs(...)`, which
/// derives the Vendor from `auth.uid()` and accepts nothing but a page size and
/// a two-part cursor. There is no filter argument, no search term and no
/// identity to pass — so nothing on this screen can widen what comes back, and
/// nothing can narrow it at the server either.
///
/// ## Three operations, and each one's failure is a different event
///
/// * [load] — the first page. A failure here is the whole screen, and retrying
///   it is the only thing worth offering.
/// * [refresh] — the newest page again, with **no cursor**. A failure here must
///   not throw away the rows already on screen: they are still the last thing
///   the backend actually said, and blanking a history because a re-read failed
///   would be worse than showing a stale one with a notice.
/// * [loadMore] — the page strictly older than the final loaded row. A failure
///   here is smaller still: everything already loaded stays, and only the
///   *older* request is retried.
///
/// Keeping them apart is why the state carries two failures rather than one. A
/// load-more that failed says nothing about the rows above it, and a refresh
/// that failed says nothing about whether more history exists below.
///
/// ## Pagination is keyset, and the cursor is never invented
///
/// The cursor is always [cursorFrom] the **final row of the currently loaded
/// list** — both halves, from the same row. It is never an offset, never a page
/// number, never a timestamp on its own and never an id on its own. `created_at`
/// defaults to `now()`, which is the *transaction* timestamp, so two events
/// written in one transaction tie exactly; a timestamp-only cursor over a tied
/// pair would either re-emit both rows or skip both.
///
/// **The end of the history is a short or empty page, and nothing else.** No
/// total count exists — an exact `COUNT` over an append-only table that grows
/// forever costs a full scan per page and is stale the moment it is computed —
/// so none is displayed and none is inferred.
final class VendorAuditLogCubit extends Cubit<VendorAuditLogState> {
  VendorAuditLogCubit(this._repository) : super(const VendorAuditLogState());

  final VendorAuditLogRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a read
  /// that lands after a session change cannot repopulate a cleared history —
  /// and, with it, the previous Vendor's activity, colleagues' names and
  /// Retailer names.
  ///
  /// Advanced by every request and by [clear], so a stale first page, a stale
  /// refresh and a stale older page are all dropped on arrival.
  int _token = 0;

  /// Reads the newest page, showing the full loading state.
  Future<void> load() => _fetchNewest(showLoading: true);

  /// Re-reads the newest page in place.
  ///
  /// Deliberately does not blank the list first: a refresh should update the
  /// feed, not make it flash empty and fill in again. The refresh is still
  /// *visible* — [VendorAuditLogState.isRefreshing] drives the button spinner
  /// and the pull-to-refresh indicator.
  ///
  /// The refreshed page **replaces** the loaded collection rather than being
  /// merged onto it, and the end-of-history flag is recomputed from that page
  /// alone. Appending a newest-page read onto a paged tail would splice two
  /// reads taken at different instants into one list whose cursor no longer
  /// describes its own final row.
  Future<void> refresh() => _fetchNewest(showLoading: state.events.isEmpty);

  Future<void> _fetchNewest({required bool showLoading}) async {
    // Repeated taps must not produce simultaneous requests, and a refresh must
    // not race an older-page read whose cursor is about to be discarded. One
    // in-flight read at a time, and a second call is a no-op rather than a
    // queued duplicate.
    if (state.isBusy) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        phase: showLoading
            ? VendorAuditLogPhase.loading
            : VendorAuditLogPhase.ready,
        isRefreshing: true,
        clearFailure: true,
        // A retry of the *older* page is meaningless once the list is about to
        // be replaced, so its failure goes with it.
        clearLoadMoreFailure: true,
      ),
    );

    final ReadResult<List<VendorAuditLogEntry>> result = await _repository
        .auditLogs();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<List<VendorAuditLogEntry>>(
        :final List<VendorAuditLogEntry> value,
      ):
        final List<VendorAuditLogEntry> page = _deduplicate(value, <String>{});
        emit(
          state.copyWith(
            phase: VendorAuditLogPhase.ready,
            events: page,
            isRefreshing: false,
            clearFailure: true,
            // Recomputed from the returned page, never carried over. A history
            // that had reached its end can grow, and a refresh is exactly when
            // this client finds out.
            hasReachedEnd: _isFinalPage(value),
          ),
        );

      case ReadFailure<List<VendorAuditLogEntry>>(:final Failure failure):
        emit(
          state.copyWith(
            phase: VendorAuditLogPhase.failed,
            failure: failure,
            isRefreshing: false,
            // The rows already on screen are still the last thing the backend
            // said. Discarding them because a refresh failed would replace a
            // real history with an empty one — and "nothing has happened" and
            // "we could not re-read" are opposite claims.
          ),
        );
    }
  }

  /// Reads the page strictly older than the final loaded row.
  ///
  /// A no-op when the history has already ended, when nothing is loaded yet
  /// (there is no row to take a cursor from), and while any read is in flight —
  /// so a repeated tap or a scroll that fires twice cannot produce two requests
  /// for the same page.
  Future<void> loadMore() async {
    if (state.isBusy || state.hasReachedEnd || state.events.isEmpty) {
      return;
    }

    final int token = ++_token;
    // Both halves, from the same row, taken at the moment of the request. Never
    // remembered across a refresh: a replaced list has a different final row.
    final VendorAuditLogCursor cursor = cursorFrom(state.events.last);

    emit(state.copyWith(isLoadingMore: true, clearLoadMoreFailure: true));

    final ReadResult<List<VendorAuditLogEntry>> result = await _repository
        .auditLogs(before: cursor);

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<List<VendorAuditLogEntry>>(
        :final List<VendorAuditLogEntry> value,
      ):
        emit(
          state.copyWith(
            events: <VendorAuditLogEntry>[
              ...state.events,
              // Defensive only. The backend's strict `<` against a unique
              // composite key cannot return a row already above the cursor, so
              // this filter should never remove anything — but appending a
              // duplicate would break the list's keys and, because the cursor
              // comes from the final row, could stall paging on a repeating
              // page. It is a guard, not the authority: the ordering and the
              // page boundary are decided in SQL.
              ..._deduplicate(
                value,
                state.events
                    .map((VendorAuditLogEntry e) => e.auditLogId)
                    .toSet(),
              ),
            ],
            isLoadingMore: false,
            clearLoadMoreFailure: true,
            hasReachedEnd: _isFinalPage(value),
          ),
        );

      case ReadFailure<List<VendorAuditLogEntry>>(:final Failure failure):
        emit(
          state.copyWith(
            loadMoreFailure: failure,
            isLoadingMore: false,
            // Everything already loaded stays exactly where it is, and
            // `hasReachedEnd` stays false — a failed read is not evidence that
            // the history ended.
          ),
        );
    }
  }

  /// Drops every audit event held in memory, along with the cursor position,
  /// the end-of-history flag, both in-flight flags and both failures.
  ///
  /// Called when the signed-in person changes. An audit history is private
  /// Vendor data in its entirety — it names colleagues, Retailers, shops,
  /// products and the moments each was touched — so all of it goes.
  ///
  /// Advancing the token first means an answer already in flight for the
  /// previous person cannot refill the feed after it has been emptied, whichever
  /// of the three reads it was.
  void clear() {
    _token++;
    emit(const VendorAuditLogState());
  }

  /// Whether [page] is the last one.
  ///
  /// A page shorter than the size that was asked for can only mean the history
  /// is exhausted: the function returns `limit` rows whenever `limit` rows
  /// remain, and refuses an out-of-range limit rather than clamping it — which
  /// is exactly what makes a short page unambiguous here. An empty page is the
  /// same statement with nothing left at all.
  ///
  /// Nothing else is treated as an ending. A failed read is not one, and neither
  /// is a full page that happens to be the last.
  static bool _isFinalPage(List<VendorAuditLogEntry> page) =>
      page.length < vendorAuditLogPageSize;

  /// [page] with any row whose id is already in [seen] removed, order preserved.
  ///
  /// Order is never recomputed. The backend's `occurred_at desc,
  /// audit_log_id desc` is total and is what the cursor depends on, so a client
  /// that re-sorted would take its next cursor from the wrong row.
  static List<VendorAuditLogEntry> _deduplicate(
    List<VendorAuditLogEntry> page,
    Set<String> seen,
  ) {
    final Set<String> ids = <String>{...seen};
    return page
        .where((VendorAuditLogEntry entry) => ids.add(entry.auditLogId))
        .toList(growable: false);
  }
}
