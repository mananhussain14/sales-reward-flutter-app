import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/result/read_result.dart';
import '../../../domain/entities/vendor_product_status.dart';
import '../../../domain/entities/vendor_product_summary.dart';
import '../../../domain/repositories/vendor_product_repository.dart';

part 'vendor_product_list_state.dart';

/// The calling Vendor's product catalogue.
///
/// Backed by exactly **one** call to `public.list_vendor_products()`, which
/// takes zero arguments and derives the Vendor from `auth.uid()`. There is no
/// page parameter, no filter argument and no id to pass — so nothing on this
/// screen can widen what comes back, and nothing can narrow it at the server
/// either.
///
/// ## Search and filtering are local, and that is a consequence of the contract
///
/// The RPC is unpaginated, has no search or filter parameter by design, and
/// returns the whole catalogue in one response — so filtering the loaded rows is
/// filtering the complete trusted answer, not a partial view a server-side
/// filter would have to complete. Sending a search term or a status would also
/// mean inventing parameters the deployed function does not have; the backend
/// audit is explicit that a *status* parameter in particular would put a status
/// value in a caller's hands, which the contract deliberately refuses.
///
/// **No pagination is invented here.** A page counter over a list the client
/// already holds in full would be a fiction, and one over a list it does not
/// would need a cursor the RPC does not accept.
///
/// ## Counts arrive with the row, and are never fetched
///
/// [VendorProductSummary.activeAssignmentCount] is a correlated `count(*)`
/// computed in the same statement. There is no per-product assignment read
/// anywhere in this cubit — that would be N+1 over work the backend already did,
/// and a second place for the counting rule to be got wrong.
///
/// The **total** assignment count is deliberately not available here, because
/// the list does not return one. A screen that wanted to show it would have to
/// invent it, so no screen does.
final class VendorProductListCubit extends Cubit<VendorProductListState> {
  VendorProductListCubit(this._repository)
    : super(const VendorProductListState());

  final VendorProductRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a read
  /// that lands after a session change cannot repopulate a cleared catalogue —
  /// and, with it, the previous Vendor's products.
  int _token = 0;

  /// Reads the catalogue, showing the full loading state.
  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads the catalogue in place.
  ///
  /// Deliberately does not blank the list: a refresh should update rows, not
  /// make the screen flash empty and fill in again. The refresh is still
  /// *visible* — [VendorProductListState.isRefreshing] drives the button spinner
  /// and the pull-to-refresh indicator.
  Future<void> refresh() => _fetch(showLoading: state.products.isEmpty);

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
            ? VendorProductListPhase.loading
            : VendorProductListPhase.ready,
        isRefreshing: true,
        clearFailure: true,
      ),
    );

    final ReadResult<List<VendorProductSummary>> result = await _repository
        .products();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<List<VendorProductSummary>>(
        :final List<VendorProductSummary> value,
      ):
        emit(
          state.copyWith(
            phase: VendorProductListPhase.ready,
            products: value,
            isRefreshing: false,
            clearFailure: true,
          ),
        );

      case ReadFailure<List<VendorProductSummary>>(:final Failure failure):
        emit(
          state.copyWith(
            phase: VendorProductListPhase.failed,
            failure: failure,
            isRefreshing: false,
            // The rows already on screen are still the last thing the backend
            // said. Discarding them because a refresh failed would replace a
            // real catalogue with an empty one.
          ),
        );
    }
  }

  /// Narrows the loaded rows by name, code, barcode or brand,
  /// case-insensitively.
  void search(String term) => emit(state.copyWith(searchTerm: term));

  /// Narrows by product status. Null clears the filter.
  void filterByStatus(VendorProductStatus? status) => emit(
    state.copyWith(statusFilter: status, clearStatusFilter: status == null),
  );

  /// Clears the search term and the status filter, leaving the loaded rows.
  void clearFilters() =>
      emit(state.copyWith(searchTerm: '', clearStatusFilter: true));

  /// Drops every product held in memory, along with the search term, the
  /// filter, the refresh state and any failure.
  ///
  /// Called when the signed-in person changes. A product catalogue is private
  /// Vendor data in its entirety — names, codes, barcodes, brands and
  /// assignment counts — so all of it goes. A search term goes with it: it is
  /// something the previous person typed, it is a fragment of a product name or
  /// code, and leaving it behind would show the next person a filtered view they
  /// did not ask for.
  ///
  /// Advancing the token first means an answer already in flight for the
  /// previous person cannot refill the list after it has been emptied.
  void clear() {
    _token++;
    emit(const VendorProductListState());
  }
}
