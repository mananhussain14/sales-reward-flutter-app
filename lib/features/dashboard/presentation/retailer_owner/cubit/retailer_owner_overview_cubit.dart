import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/retailer_owner_overview.dart';
import '../../../domain/repositories/retailer_owner_overview_repository.dart';

part 'retailer_owner_overview_state.dart';

/// The calling Retailer Owner's portal overview.
///
/// Backed by repeated calls to `public.get_retailer_owner_portal_context()`,
/// which resolves the organization from `auth.uid()` and **accepts nothing at
/// all**. There is no filter, no period, no identity and no organization to
/// pass — so nothing on this screen can widen what comes back, and nothing can
/// narrow it either.
///
/// ## Two operations, and each one's failure is a different event
///
/// * [load] — the first read. A failure here is the whole screen, and retrying
///   it is the only thing worth offering.
/// * [refresh] — the same read again. A failure here must **not** throw away the
///   values already on screen: they are still the last thing the backend
///   actually said, and blanking an overview because a re-read failed would
///   replace real figures with nothing.
///
/// ## The overview is replaced whole, never merged
///
/// The backend answers all seven values in one statement, so they describe one
/// instant. [_fetch] therefore swaps the entire [RetailerOwnerOverview] on
/// success and never updates a field in place. Merging would splice two reads
/// taken at different moments into one overview — pairing, say, a shop count
/// from before an onboarding with a status from after it, and looking entirely
/// plausible.
///
/// ## Ineligible is not a failure, and never a zeroed overview
///
/// Zero rows is a successful answer meaning "there is no Owner overview for
/// you". It clears any previously held overview — which matters on the
/// `Owner A → Owner B` path, where B may be ineligible and must not be shown A's
/// organization — and it is **not retryable**, because a second identical call
/// returns the same nothing.
final class RetailerOwnerOverviewCubit
    extends Cubit<RetailerOwnerOverviewState> {
  RetailerOwnerOverviewCubit(this._repository)
    : super(const RetailerOwnerOverviewState());

  final RetailerOwnerOverviewRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a read
  /// that lands after a session change cannot repopulate a cleared overview —
  /// and with it, the previous Retailer's name, statuses and shop counts.
  ///
  /// Advanced by every request and by [clear], so a stale first read and a stale
  /// refresh are both dropped on arrival.
  int _token = 0;

  /// The token an in-flight read would have to carry to be accepted. Exposed for
  /// the isolation tests, which assert that a stale answer is dropped rather
  /// than merely arriving late.
  int get requestToken => _token;

  /// Reads the overview, showing the full loading state.
  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads the overview in place.
  ///
  /// Deliberately does not blank the values first: a refresh should update the
  /// figures, not make them flash empty and fill in again. The refresh is still
  /// *visible* — [RetailerOwnerOverviewState.isRefreshing] drives both the
  /// button spinner and the pull-to-refresh indicator.
  ///
  /// With nothing loaded yet — a refresh after a failed first read, or a pull on
  /// an empty screen — it shows the loading state instead, because there is
  /// nothing on screen for it to preserve.
  Future<void> refresh() => _fetch(showLoading: state.overview == null);

  Future<void> _fetch({required bool showLoading}) async {
    // Repeated taps must not produce simultaneous requests. One in-flight read
    // at a time, and a second call is a no-op rather than a queued duplicate —
    // two answers to the same question could arrive out of order and leave the
    // older one on screen.
    if (state.isRefreshing) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        phase: showLoading
            ? RetailerOverviewPhase.loading
            : RetailerOverviewPhase.ready,
        isRefreshing: true,
        clearProblem: true,
      ),
    );

    final RetailerOverviewResult result = await _repository.overview();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case RetailerOverviewLoaded(:final RetailerOwnerOverview overview):
        emit(
          state.copyWith(
            phase: RetailerOverviewPhase.ready,
            // The whole snapshot, atomically. No field is carried over from the
            // previous read.
            overview: overview,
            isRefreshing: false,
            clearProblem: true,
          ),
        );

      case RetailerOverviewIneligible():
        // A successful answer with no content. The previously held overview is
        // dropped rather than kept: on an Owner A → Owner B switch, keeping it
        // would leave A's organization on screen under B's session — which is
        // exactly the leak the isolation rules exist to prevent.
        emit(
          const RetailerOwnerOverviewState(
            phase: RetailerOverviewPhase.ineligible,
          ),
        );

      case RetailerOverviewFailed(:final RetailerOverviewProblem problem):
        emit(
          state.copyWith(
            phase: RetailerOverviewPhase.failed,
            problem: problem,
            isRefreshing: false,
            // The values already on screen stay exactly as they are. They are
            // still the last thing the backend actually said, and discarding
            // them because a re-read failed would replace a real overview with
            // nothing — while converting them to zeros would replace it with a
            // lie.
          ),
        );
    }
  }

  /// Drops the overview held in memory, along with the loading state, the
  /// refresh state and the problem.
  ///
  /// Called when the signed-in person or the resolved Retailer changes. Every
  /// value is private to one organization — its name, its trading status, this
  /// person's membership status and how many shops it runs — so the snapshot
  /// goes as a whole rather than being pruned.
  ///
  /// Advancing the token first means an answer already in flight for the
  /// previous identity cannot refill the screen after it has been emptied,
  /// whichever of the two reads it was.
  void clear() {
    _token++;
    emit(const RetailerOwnerOverviewState());
  }
}
