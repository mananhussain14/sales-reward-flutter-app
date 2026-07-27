part of 'retailer_owner_overview_cubit.dart';

/// Where the overview read has reached.
enum RetailerOverviewPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// An overview is on screen.
  ready,

  /// The backend answered successfully with **no row**: this account has no
  /// Owner overview.
  ///
  /// A settled, terminal state rather than a failure, and deliberately not
  /// retryable — a second identical call returns the same nothing.
  ineligible,

  /// The read did not produce an answer. With an overview held this means a
  /// *refresh* failed and the values are stale; with none it means the first
  /// read failed.
  failed,
}

/// The loaded Retailer Owner overview, and how it got there.
///
/// Immutable, and holds **no raw Supabase map** — every value is a parsed domain
/// type. The map never leaves the data layer.
final class RetailerOwnerOverviewState extends Equatable {
  const RetailerOwnerOverviewState({
    this.phase = RetailerOverviewPhase.initial,
    this.overview,
    this.problem,
    this.isRefreshing = false,
  });

  final RetailerOverviewPhase phase;

  /// The seven values as one snapshot, or null when none has been read.
  ///
  /// Null is **not** an empty organization and is never rendered as one. An
  /// overview that could not be read has no figures at all; a Retailer with no
  /// shops has a real name, real statuses and two counts that happen to be `0`.
  /// The screen must be able to tell those apart, which is why the whole
  /// snapshot is nullable rather than the individual fields.
  final RetailerOwnerOverview? overview;

  /// Why the first read or a refresh failed. A discriminant; never the backend's
  /// own message, SQLSTATE, or any part of its response body.
  final RetailerOverviewProblem? problem;

  /// True while a read is in flight, first or subsequent.
  ///
  /// Also the duplicate-request guard: one read at a time, so a repeated tap on
  /// Refresh and a pull-to-refresh landing together cannot produce two calls.
  final bool isRefreshing;

  /// Values are on screen but the last refresh did not succeed.
  ///
  /// A non-blocking state: the cards stay, and the notice sits above them.
  bool get isStale => phase == RetailerOverviewPhase.failed && overview != null;

  /// The whole screen is a failure — the first read did not land.
  bool get hasFailedOutright =>
      phase == RetailerOverviewPhase.failed && overview == null;

  /// The skeleton should be shown: a first read with nothing yet to display.
  bool get isInitialLoading =>
      phase == RetailerOverviewPhase.loading && overview == null;

  /// The organization or this membership is not fully active.
  ///
  /// False when there is no overview: an absent row says nothing about a status,
  /// and inferring "inactive" from "not loaded" would state something the
  /// backend never said.
  bool get hasInactiveStatus => overview != null && !overview!.isFullyActive;

  RetailerOwnerOverviewState copyWith({
    RetailerOverviewPhase? phase,
    RetailerOwnerOverview? overview,
    RetailerOverviewProblem? problem,
    bool? isRefreshing,
    bool clearProblem = false,
  }) {
    return RetailerOwnerOverviewState(
      phase: phase ?? this.phase,
      overview: overview ?? this.overview,
      // Explicit rather than inferred from null: `copyWith(problem: null)`
      // cannot be told from "leave it alone" in Dart, and a stale problem
      // surviving a successful refresh would leave an error notice above fresh
      // figures.
      problem: clearProblem ? null : (problem ?? this.problem),
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }

  @override
  List<Object?> get props => <Object?>[phase, overview, problem, isRefreshing];
}
