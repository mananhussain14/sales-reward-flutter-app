import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/result/read_result.dart';
import '../../../domain/entities/vendor_user_status.dart';
import '../../../domain/entities/vendor_user_summary.dart';
import '../../../domain/repositories/vendor_user_repository.dart';

part 'vendor_user_list_state.dart';

/// The users of the caller's own Vendor organization.
///
/// Backed by exactly **one** call to `public.list_vendor_users()`, which takes
/// zero arguments and derives the Vendor from `auth.uid()`. There is no page
/// parameter, no filter argument and no id to pass — so nothing on this screen
/// can widen what comes back, and no other Vendor's user can appear on it.
///
/// ## Search and filtering are local, and that is a consequence of the contract
///
/// The RPC is unpaginated, has no search or filter parameter by design, and
/// returns the Vendor's whole directory in one response — so filtering the
/// loaded rows is filtering the complete trusted answer, not a partial view a
/// server-side filter would have to complete. Sending a search term or a status
/// would also mean inventing parameters the deployed function does not have.
///
/// **No pagination is invented here.** When the backend grows cursor
/// parameters, this cubit gains them; until then a page counter would be a
/// client-side fiction over a fixed list.
///
/// ## Roles arrive with the row, and are never fetched
///
/// [VendorUserSummary.roleNames] comes from a correlated `array_agg` in the same
/// statement. There is no per-user role read, no `member_roles` query and no
/// permission lookup — those would be N+1 over a join the backend already did,
/// and a second place for the ACTIVE-role filter to be got wrong.
final class VendorUserListCubit extends Cubit<VendorUserListState> {
  VendorUserListCubit(this._repository) : super(const VendorUserListState());

  final VendorUserRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a read
  /// that lands after a session change cannot repopulate a cleared directory.
  int _token = 0;

  /// Reads the directory, showing the full loading state.
  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads the directory in place.
  ///
  /// Deliberately does not blank the list: a refresh should update rows, not
  /// make the screen flash empty and fill in again. The refresh is still
  /// *visible* — [VendorUserListState.isRefreshing] drives the button spinner
  /// and the pull-to-refresh indicator.
  Future<void> refresh() => _fetch(showLoading: state.users.isEmpty);

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
            ? VendorUserListPhase.loading
            : VendorUserListPhase.ready,
        isRefreshing: true,
        clearFailure: true,
      ),
    );

    final ReadResult<List<VendorUserSummary>> result = await _repository
        .users();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<List<VendorUserSummary>>(
        :final List<VendorUserSummary> value,
      ):
        emit(
          state.copyWith(
            phase: VendorUserListPhase.ready,
            users: value,
            isRefreshing: false,
            clearFailure: true,
          ),
        );

      case ReadFailure<List<VendorUserSummary>>(:final Failure failure):
        emit(
          state.copyWith(
            phase: VendorUserListPhase.failed,
            failure: failure,
            isRefreshing: false,
            // The rows already on screen are still the last thing the backend
            // said. Discarding them because a refresh failed would replace a
            // real directory with an empty one.
          ),
        );
    }
  }

  /// Narrows the loaded rows by display name, case-insensitively.
  void search(String term) => emit(state.copyWith(searchTerm: term));

  /// Narrows by the person's own **profile** status. Null clears the filter.
  void filterByProfileStatus(VendorUserStatus? status) => emit(
    state.copyWith(profileFilter: status, clearProfileFilter: status == null),
  );

  /// Narrows by their **membership** status in this Vendor. Null clears it.
  ///
  /// Offered separately from the profile filter because the two are independent
  /// facts: a person whose profile is ACTIVE can hold a SUSPENDED membership
  /// here, and collapsing the two filters would make that case unreachable.
  void filterByMembershipStatus(VendorUserStatus? status) => emit(
    state.copyWith(
      membershipFilter: status,
      clearMembershipFilter: status == null,
    ),
  );

  /// Clears the search term and both status filters, leaving the loaded rows.
  void clearFilters() => emit(
    state.copyWith(
      searchTerm: '',
      clearProfileFilter: true,
      clearMembershipFilter: true,
    ),
  );

  /// Drops every user held in memory, along with the search term, both filters
  /// and any failure.
  ///
  /// Called when the signed-in person changes. A search term can itself carry
  /// private information — it is usually a fragment of a colleague's name — so
  /// clearing the rows without clearing the term would leave one Vendor's staff
  /// legible to the next person on the device. Advancing the token first means
  /// an answer already in flight for the previous person cannot refill the list
  /// after it has been emptied.
  void clear() {
    _token++;
    emit(const VendorUserListState());
  }
}
