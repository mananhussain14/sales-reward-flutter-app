import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/result/read_result.dart';
import '../../../domain/entities/vendor_dashboard_summary.dart';
import '../../../domain/repositories/vendor_dashboard_repository.dart';

part 'vendor_dashboard_state.dart';

/// The calling Vendor's dashboard summary.
///
/// Backed by repeated calls to `public.get_vendor_admin_dashboard_summary()`,
/// which derives the Vendor from `auth.uid()` and **accepts nothing at all**.
/// There is no filter, no period, no identity and no organization to pass — so
/// nothing on this screen can widen what comes back, and nothing can narrow it
/// either.
///
/// ## Two operations, and each one's failure is a different event
///
/// * [load] — the first read. A failure here is the whole screen, and retrying it
///   is the only thing worth offering.
/// * [refresh] — the same read again. A failure here must **not** throw away the
///   figures already on screen: they are still the last thing the backend
///   actually said, and blanking a dashboard because a re-read failed would
///   replace four real numbers with nothing.
///
/// ## The summary is replaced whole, never merged
///
/// The backend answers all four counts in one statement, so they describe one
/// instant. [_fetch] therefore swaps the entire [VendorDashboardSummary] on
/// success and never updates a field in place. Merging would splice two reads
/// taken at different moments into one overview — and because two of the four
/// figures are deployment-wide while two are this Vendor's, a merged snapshot
/// could pair one organization's members with another moment's catalogue and look
/// entirely plausible.
///
/// ## A denial is never zeros
///
/// A refused read leaves [VendorDashboardState.summary] exactly as it was — null
/// on a first read, so the screen shows the shared denial state rather than four
/// zero cards. "You may not read this summary" and "this Vendor has nothing" are
/// opposite claims, and the backend deliberately does not distinguish *which*
/// gate refused, so neither does this.
final class VendorDashboardCubit extends Cubit<VendorDashboardState> {
  VendorDashboardCubit(this._repository) : super(const VendorDashboardState());

  final VendorDashboardRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a read that
  /// lands after a session change cannot repopulate a cleared dashboard — and
  /// with it, the previous Vendor's member count and recorded-event total.
  ///
  /// Advanced by every request and by [clear], so a stale first read and a stale
  /// refresh are both dropped on arrival.
  int _token = 0;

  /// Reads the summary, showing the full loading state.
  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads the summary in place.
  ///
  /// Deliberately does not blank the cards first: a refresh should update the
  /// figures, not make them flash empty and fill in again. The refresh is still
  /// *visible* — [VendorDashboardState.isRefreshing] drives the button spinner and
  /// the pull-to-refresh indicator.
  ///
  /// With nothing loaded yet — a refresh after a failed first read, or a pull on
  /// an empty screen — it shows the loading state instead, because there is
  /// nothing on screen for it to preserve.
  Future<void> refresh() => _fetch(showLoading: state.summary == null);

  Future<void> _fetch({required bool showLoading}) async {
    // Repeated taps must not produce simultaneous requests. One in-flight read at
    // a time, and a second call is a no-op rather than a queued duplicate — two
    // answers to the same question could arrive out of order and leave the older
    // one on screen.
    if (state.isRefreshing) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        phase: showLoading
            ? VendorDashboardPhase.loading
            : VendorDashboardPhase.ready,
        isRefreshing: true,
        clearFailure: true,
      ),
    );

    final ReadResult<VendorDashboardSummary> result = await _repository
        .summary();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<VendorDashboardSummary>(
        :final VendorDashboardSummary value,
      ):
        emit(
          state.copyWith(
            phase: VendorDashboardPhase.ready,
            // The whole snapshot, atomically. No field is carried over from the
            // previous read.
            summary: value,
            isRefreshing: false,
            clearFailure: true,
          ),
        );

      case ReadFailure<VendorDashboardSummary>(:final Failure failure):
        emit(
          state.copyWith(
            phase: VendorDashboardPhase.failed,
            failure: failure,
            isRefreshing: false,
            // The figures already on screen stay exactly as they are. They are
            // still the last thing the backend actually said, and discarding them
            // because a re-read failed would replace real counts with nothing —
            // while converting them to zeros would replace them with a lie.
          ),
        );
    }
  }

  /// Drops the summary held in memory, along with the loading state, the refresh
  /// state and the failure.
  ///
  /// Called when the signed-in person changes. Two of the four counts are private
  /// Vendor data — how many people work in the organization, and how much has
  /// happened in it — so the snapshot goes as a whole rather than being pruned to
  /// the two global figures. A half-cleared summary would be a shape no backend
  /// answer ever produces.
  ///
  /// Advancing the token first means an answer already in flight for the previous
  /// person cannot refill the cards after they have been emptied, whichever of the
  /// two reads it was.
  void clear() {
    _token++;
    emit(const VendorDashboardState());
  }
}
