import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/retailer_read_problem.dart';
import '../../../domain/entities/retailer_assigned_product.dart';
import '../../../domain/repositories/retailer_product_repository.dart';

part 'retailer_products_state.dart';

/// The products currently assigned to the calling Retailer.
///
/// Backed by repeated calls to `list_retailer_assigned_products()`, which scopes
/// itself from `auth.uid()` and **accepts nothing at all** — no Retailer, no
/// Vendor, no status, no page.
///
/// Shared by both Retailer shells, because the contract is identical for the
/// Owner and the Manager: the same resolver, the same permission, the same rows.
///
/// ## Search is local
///
/// [searchChanged] filters rows **already read** and issues no request, so a
/// term never reaches the backend and can never become a predicate the database
/// evaluates.
///
/// ## The list is replaced whole, never merged
///
/// A refresh swaps the entire list. This client deliberately does not carry
/// `product_id`, so there is nothing to merge *by* — and matching on display
/// fields would silently pair two products that look alike.
final class RetailerProductsCubit extends Cubit<RetailerProductsState> {
  RetailerProductsCubit(this._repository)
    : super(const RetailerProductsState());

  final RetailerProductRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a read
  /// that lands after a session change cannot repopulate a cleared catalogue.
  int _token = 0;

  /// Exposed for the isolation tests.
  int get requestToken => _token;

  Future<void> load() => _fetch(showLoading: true);

  Future<void> refresh() => _fetch(showLoading: state.products == null);

  /// Loads only if nothing has been read yet — what makes "opening the tab reads
  /// once" and "returning to a loaded tab reads nothing" both true.
  Future<void> loadOnce() {
    if (state.phase != RetailerProductsPhase.initial) {
      return Future<void>.value();
    }
    return load();
  }

  Future<void> _fetch({required bool showLoading}) async {
    if (state.isRefreshing) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        phase: showLoading
            ? RetailerProductsPhase.loading
            : RetailerProductsPhase.ready,
        isRefreshing: true,
        clearProblem: true,
      ),
    );

    final RetailerProductsResult result = await _repository.products();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case RetailerProductsLoaded(
        :final List<RetailerAssignedProduct> products,
      ):
        emit(
          state.copyWith(
            phase: RetailerProductsPhase.ready,
            products: products,
            isRefreshing: false,
            clearProblem: true,
          ),
        );

      case RetailerProductsFailed(:final RetailerReadProblem problem):
        emit(
          state.copyWith(
            phase: RetailerProductsPhase.failed,
            problem: problem,
            isRefreshing: false,
            // Rows already on screen stay. They are still the last thing the
            // backend actually said.
          ),
        );
    }
  }

  /// Filters the rows already held. Issues no request.
  void searchChanged(String term) {
    emit(state.copyWith(searchTerm: term));
  }

  /// Drops the catalogue, the search term, the loading and refresh state and the
  /// problem.
  ///
  /// Called when the signed-in person or the resolved Retailer changes. Which
  /// products a Vendor assigns to a Retailer is a commercial fact about that
  /// relationship, and the search term is private too, being a fragment of a
  /// product name or brand.
  void clear() {
    _token++;
    emit(const RetailerProductsState());
  }
}
