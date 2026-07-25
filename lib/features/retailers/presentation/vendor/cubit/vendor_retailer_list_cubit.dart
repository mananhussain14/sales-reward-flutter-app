import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../domain/entities/vendor_retailer_status.dart';
import '../../../domain/entities/vendor_retailer_summary.dart';
import '../../../domain/repositories/vendor_retailer_repository.dart';
import '../../../domain/repositories/vendor_retailer_result.dart';

part 'vendor_retailer_list_state.dart';

/// The Retailers connected to the caller's own Vendor organization.
///
/// Backed by exactly **one** call to `public.list_vendor_retailers()`, which
/// takes zero arguments and derives the Vendor from `auth.uid()`. There is no
/// page parameter, no filter argument and no id to pass — so nothing on this
/// screen can widen what comes back, and no other Vendor's Retailer can appear
/// on it.
///
/// ## Search and filtering are local, and that is a consequence of the contract
///
/// The RPC is unpaginated and returns the Vendor's whole directory in one
/// response, so filtering the loaded rows is filtering the complete trusted
/// answer — not a partial view that a server-side filter would have to complete.
/// Sending a search term or a status to the backend would also mean inventing
/// parameters the deployed function does not have.
///
/// **No pagination is invented here.** When the backend grows cursor
/// parameters, this cubit gains them; until then a page counter would be a
/// client-side fiction over a fixed list.
///
/// ## One shop read is never issued from this screen
///
/// [VendorRetailerSummary.shopCount] and [VendorRetailerSummary.activeShopCount]
/// are computed in SQL by a lateral aggregate. Calling
/// `list_vendor_retailer_shops()` per row to count them would reintroduce
/// precisely the row-transfer defect the backend milestone removed.
final class VendorRetailerListCubit extends Cubit<VendorRetailerListState> {
  VendorRetailerListCubit(this._repository)
    : super(const VendorRetailerListState());

  final VendorRetailerRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for.
  ///
  /// Every read captures the token it started under and compares it before
  /// emitting, so a response that lands after [clear] — after the signed-in
  /// person changed — is dropped instead of refilling a directory that has just
  /// been emptied. `isClosed` alone does not cover that: the cubit is owned by
  /// the Vendor shell and outlives a session change, so it is very much still
  /// open when the previous identity's answer arrives.
  int _token = 0;

  /// Reads the directory, showing the full loading state.
  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads the directory in place.
  ///
  /// Deliberately does not blank the list: a refresh should update rows, not
  /// make the screen flash empty and fill in again. The refresh is still
  /// *visible* — [VendorRetailerListState.isRefreshing] drives the button
  /// spinner and the pull-to-refresh indicator.
  Future<void> refresh() => _fetch(showLoading: state.retailers.isEmpty);

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
            ? VendorRetailerListPhase.loading
            : VendorRetailerListPhase.ready,
        isRefreshing: true,
        clearFailure: true,
      ),
    );

    final VendorRetailerResult<List<VendorRetailerSummary>> result =
        await _repository.retailers();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
        :final List<VendorRetailerSummary> value,
      ):
        emit(
          state.copyWith(
            phase: VendorRetailerListPhase.ready,
            retailers: value,
            isRefreshing: false,
            clearFailure: true,
          ),
        );

      case VendorRetailerReadFailure<List<VendorRetailerSummary>>(
        :final Failure failure,
      ):
        emit(
          state.copyWith(
            phase: VendorRetailerListPhase.failed,
            failure: failure,
            isRefreshing: false,
            // The rows already on screen are still the last thing the backend
            // said. Discarding them because a refresh failed would replace a
            // real directory with an empty one.
          ),
        );
    }
  }

  /// Narrows the loaded rows by Retailer name, case-insensitively.
  void search(String term) => emit(state.copyWith(searchTerm: term));

  /// Narrows the loaded rows by **relationship** status.
  ///
  /// Relationship status rather than Retailer status because it is the fact this
  /// Vendor owns: "which of my relationships are suspended" is a question about
  /// this Vendor's own records, where the Retailer company's status is a fact
  /// about somebody else. Null clears the filter.
  void filterByRelationshipStatus(VendorRetailerStatus? status) => emit(
    state.copyWith(statusFilter: status, clearStatusFilter: status == null),
  );

  /// Clears the search term and the status filter, leaving the loaded rows.
  void clearFilters() =>
      emit(state.copyWith(searchTerm: '', clearStatusFilter: true));

  /// Drops every Retailer held in memory, along with the search term and the
  /// status filter.
  ///
  /// Called when the signed-in person changes. A search term can itself carry
  /// private information — it is usually a fragment of a Retailer's name — so
  /// clearing the rows without clearing the term would leave one Vendor's
  /// business relationships legible to the next person on the device.
  void clear() {
    // Advanced before the state is emptied, so a read already in flight for the
    // previous identity cannot repopulate the directory when it lands.
    _token++;
    emit(const VendorRetailerListState());
  }
}
