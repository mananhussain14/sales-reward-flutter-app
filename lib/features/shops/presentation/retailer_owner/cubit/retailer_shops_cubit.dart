import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/retailer_read_problem.dart';
import '../../../domain/entities/retailer_shop.dart';
import '../../../domain/repositories/retailer_shop_repository.dart';

part 'retailer_shops_state.dart';

/// The calling Retailer Owner's shop estate.
///
/// Backed by repeated calls to `list_retailer_owner_portal_shops()`, which
/// scopes itself from `auth.uid()` and **accepts nothing at all**. There is no
/// filter, no page, no identity and no organization to pass — so nothing on this
/// screen can widen what comes back, and nothing can narrow it either.
///
/// ## Search is local, and that is a contract decision
///
/// [searchChanged] filters rows **already read**. It issues no request, so a
/// search term never reaches the backend and can never become a predicate the
/// database evaluates. That keeps the tenant scope exactly where it belongs and
/// makes the search box incapable of widening a result set.
///
/// It also means search is honest about what it covers: it can only match what
/// the contract returned — name, code and city — and it says so rather than
/// implying a full-text search over data the client never received.
///
/// ## The list is replaced whole, never merged
///
/// A refresh swaps the entire list. There is no id in this contract, so there is
/// nothing to merge *by*: patching a row in place would require matching it, and
/// matching on display fields would silently pair two shops that look alike.
final class RetailerShopsCubit extends Cubit<RetailerShopsState> {
  RetailerShopsCubit(this._repository) : super(const RetailerShopsState());

  final RetailerShopRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a read
  /// that lands after a session change cannot repopulate a cleared list — and
  /// with it, the previous Retailer's shop names, codes and cities.
  ///
  /// Advanced by every request and by [clear].
  int _token = 0;

  /// Exposed for the isolation tests, which assert a stale answer is dropped
  /// rather than merely arriving late.
  int get requestToken => _token;

  /// Reads the estate, showing the full loading state.
  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads in place, keeping the current rows on screen while it runs.
  ///
  /// With nothing loaded yet it shows the loading state instead, because there
  /// is nothing on screen for it to preserve.
  Future<void> refresh() => _fetch(showLoading: state.shops == null);

  /// Loads only if nothing has been read yet.
  ///
  /// The shell creates this cubit lazily on first entry to the tab, so this is
  /// what makes "opening a tab reads once" and "returning to a loaded tab reads
  /// nothing" both true without the page needing to know which case it is in.
  Future<void> loadOnce() {
    if (state.phase != RetailerShopsPhase.initial) {
      return Future<void>.value();
    }
    return load();
  }

  Future<void> _fetch({required bool showLoading}) async {
    // One in-flight read at a time. A second call is a no-op rather than a
    // queued duplicate — two answers to the same question could arrive out of
    // order and leave the older one on screen.
    if (state.isRefreshing) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        phase: showLoading
            ? RetailerShopsPhase.loading
            : RetailerShopsPhase.ready,
        isRefreshing: true,
        clearProblem: true,
      ),
    );

    final RetailerShopsResult result = await _repository.shops();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case RetailerShopsLoaded(:final List<RetailerShop> shops):
        emit(
          state.copyWith(
            phase: RetailerShopsPhase.ready,
            shops: shops,
            isRefreshing: false,
            clearProblem: true,
          ),
        );

      case RetailerShopsFailed(:final RetailerReadProblem problem):
        emit(
          state.copyWith(
            phase: RetailerShopsPhase.failed,
            problem: problem,
            isRefreshing: false,
            // Rows already on screen stay exactly as they are. They are still
            // the last thing the backend actually said, and discarding them
            // because a re-read failed would replace a real estate with nothing.
          ),
        );
    }
  }

  /// Filters the rows already held. Issues no request.
  void searchChanged(String term) {
    emit(state.copyWith(searchTerm: term));
  }

  /// Drops the estate, the search term, the loading and refresh state and the
  /// problem.
  ///
  /// Called when the signed-in person or the resolved Retailer changes. Every
  /// value is private to one organization — the names, codes and cities of its
  /// trading locations — and the search term is private too, being a fragment of
  /// one of them.
  ///
  /// Advancing the token first means an answer already in flight for the
  /// previous identity cannot refill the list after it has been emptied.
  void clear() {
    _token++;
    emit(const RetailerShopsState());
  }
}
