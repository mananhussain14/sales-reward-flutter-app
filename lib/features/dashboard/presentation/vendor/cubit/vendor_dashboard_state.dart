part of 'vendor_dashboard_cubit.dart';

/// Where the summary read has reached.
enum VendorDashboardPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// A summary is on screen.
  ready,

  /// The read did not produce an answer. With a summary held this means a
  /// *refresh* failed and the figures are stale; with none it means the first
  /// read failed.
  failed,
}

/// The loaded Vendor dashboard summary, and how it got there.
final class VendorDashboardState extends Equatable {
  const VendorDashboardState({
    this.phase = VendorDashboardPhase.initial,
    this.summary,
    this.failure,
    this.isRefreshing = false,
  });

  final VendorDashboardPhase phase;

  /// The four counts as one snapshot, or null when none has been read.
  ///
  /// Null is **not** zero and is never rendered as zero. A summary that could not
  /// be read has no figures at all; a Vendor with nothing has four real counts, two
  /// of which happen to be `0`. The screen must be able to tell those apart, which
  /// is why the whole snapshot is nullable rather than the individual counts.
  final VendorDashboardSummary? summary;

  /// Why the first read or a refresh failed. A discriminant; never the backend's
  /// own message.
  final Failure? failure;

  /// True while a read is in flight, first or subsequent.
  ///
  /// Also the duplicate-request guard: one read at a time, so a repeated tap on
  /// Refresh and a pull-to-refresh landing together cannot produce two calls.
  final bool isRefreshing;

  /// Figures are on screen but the last refresh did not succeed.
  ///
  /// A non-blocking state: the cards stay, and the notice sits above them.
  bool get isStale => phase == VendorDashboardPhase.failed && summary != null;

  /// The first read failed with nothing to show. The whole screen is the failure.
  bool get hasFailedFirstRead =>
      phase == VendorDashboardPhase.failed && summary == null;

  /// Whether the loading skeleton should stand in for the whole screen.
  ///
  /// Only before anything has ever been read. A refresh over figures already on
  /// screen keeps them, because they are still the last thing the backend
  /// actually said.
  bool get isFirstLoad =>
      phase == VendorDashboardPhase.initial ||
      (phase == VendorDashboardPhase.loading && summary == null);

  VendorDashboardState copyWith({
    VendorDashboardPhase? phase,
    VendorDashboardSummary? summary,
    Failure? failure,
    bool clearFailure = false,
    bool? isRefreshing,
  }) {
    return VendorDashboardState(
      phase: phase ?? this.phase,
      // Replaced whole or kept whole. There is deliberately no per-count setter:
      // the four figures are one snapshot from one statement, and a state that
      // could update one of them would be a state that could show two moments at
      // once.
      summary: summary ?? this.summary,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }

  @override
  List<Object?> get props => <Object?>[phase, summary, failure, isRefreshing];
}
