import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/result/read_result.dart';
import '../../../domain/entities/vendor_role_status.dart';
import '../../../domain/entities/vendor_role_summary.dart';
import '../../../domain/repositories/vendor_role_repository.dart';

part 'vendor_role_list_state.dart';

/// The shared role catalogue, with this Vendor's own assignment counts.
///
/// Backed by exactly **one** call to `public.list_vendor_roles()`, which takes
/// zero arguments and derives the Vendor from `auth.uid()`. There is no page
/// parameter, no filter argument and no id to pass — so nothing on this screen
/// can widen what comes back.
///
/// ## The rows are global; one number on them is not
///
/// Every authorized Vendor reads byte-identical role definitions, because
/// `roles` has no `organization_id` and there is only one set of rows. What is
/// tenant-scoped is [VendorRoleSummary.assignedMemberCount], computed against
/// the calling Vendor alone — which is why [clear] exists and why this cubit is
/// wiped on a session change like any other private state.
///
/// ## Nothing here narrows the catalogue on the client's own initiative
///
/// The three Retailer role definitions are part of the catalogue and are
/// **shown**. There is no scope, kind, `is_system` or `is_custom` column to
/// filter on, and inferring one from a role name would be inventing a taxonomy
/// that would immediately disagree with the web page showing the same six roles.
/// The only narrowing here is the search term and status filter the user
/// themselves applied.
///
/// ## Search and filtering are local, and that is a consequence of the contract
///
/// The RPC is unpaginated, has no search or filter parameter by design, and
/// returns the whole catalogue in one response — so filtering the loaded rows is
/// filtering the complete trusted answer, not a partial view a server-side
/// filter would have to complete. Sending a search term, a status or a role code
/// would also mean inventing parameters the deployed function does not have.
///
/// **No pagination is invented here.** The catalogue is six rows today and grows
/// only when a migration seeds a role; a page counter would be a client-side
/// fiction over a fixed list.
///
/// ## Counts arrive with the row, and are never fetched
///
/// [VendorRoleSummary.permissionCount] and
/// [VendorRoleSummary.assignedMemberCount] are scalar aggregates computed in the
/// same statement. There is no per-role permission read, no per-role member
/// query and no `member_roles` lookup — those would be N+1 over work the backend
/// already did, and a second place for the tenant scoping to be got wrong.
final class VendorRoleListCubit extends Cubit<VendorRoleListState> {
  VendorRoleListCubit(this._repository) : super(const VendorRoleListState());

  final VendorRoleRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a read
  /// that lands after a session change cannot repopulate a cleared catalogue —
  /// and, with it, the previous Vendor's assignment counts.
  int _token = 0;

  /// Reads the catalogue, showing the full loading state.
  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads the catalogue in place.
  ///
  /// Deliberately does not blank the list: a refresh should update rows, not
  /// make the screen flash empty and fill in again. The refresh is still
  /// *visible* — [VendorRoleListState.isRefreshing] drives the button spinner
  /// and the pull-to-refresh indicator.
  Future<void> refresh() => _fetch(showLoading: state.roles.isEmpty);

  Future<void> _fetch({required bool showLoading}) async {
    // Repeated taps must not produce simultaneous requests. One in-flight read
    // at a time, and a second tap is a no-op rather than a queued duplicate.
    if (state.isRefreshing) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        phase: showLoading
            ? VendorRoleListPhase.loading
            : VendorRoleListPhase.ready,
        isRefreshing: true,
        clearFailure: true,
      ),
    );

    final ReadResult<List<VendorRoleSummary>> result = await _repository
        .roles();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<List<VendorRoleSummary>>(
        :final List<VendorRoleSummary> value,
      ):
        emit(
          state.copyWith(
            phase: VendorRoleListPhase.ready,
            roles: value,
            isRefreshing: false,
            clearFailure: true,
          ),
        );

      case ReadFailure<List<VendorRoleSummary>>(:final Failure failure):
        emit(
          state.copyWith(
            phase: VendorRoleListPhase.failed,
            failure: failure,
            isRefreshing: false,
            // The rows already on screen are still the last thing the backend
            // said. Discarding them because a refresh failed would replace a
            // real catalogue with an empty one.
          ),
        );
    }
  }

  /// Narrows the loaded rows by role name, case-insensitively.
  void search(String term) => emit(state.copyWith(searchTerm: term));

  /// Narrows by role status. Null clears the filter.
  void filterByStatus(VendorRoleStatus? status) => emit(
    state.copyWith(statusFilter: status, clearStatusFilter: status == null),
  );

  /// Clears the search term and the status filter, leaving the loaded rows.
  void clearFilters() =>
      emit(state.copyWith(searchTerm: '', clearStatusFilter: true));

  /// Drops every role held in memory, along with the search term, the filter
  /// and any failure.
  ///
  /// Called when the signed-in person changes. The role *definitions* are
  /// global, but [VendorRoleSummary.assignedMemberCount] is private
  /// Vendor-scoped data and travels on the same rows — so the rows go. A search
  /// term goes with them: it is something the previous person typed, and
  /// leaving it behind would show the next person a filtered view they did not
  /// ask for. Advancing the token first means an answer already in flight for
  /// the previous person cannot refill the list after it has been emptied.
  void clear() {
    _token++;
    emit(const VendorRoleListState());
  }
}
