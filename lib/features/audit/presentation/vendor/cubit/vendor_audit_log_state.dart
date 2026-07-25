part of 'vendor_audit_log_cubit.dart';

/// Where the first page of the history has reached.
///
/// Deliberately about the **first** page only. Whether an older page is loading
/// or failed is a separate pair of fields, because those events say nothing
/// about the rows already on screen.
enum VendorAuditLogPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// A history is on screen.
  ready,

  /// The read did not produce an answer. With rows loaded this means a *refresh*
  /// failed and the feed is stale; with none it means the first read failed.
  failed,
}

/// The loaded slice of the Vendor's audit history, and how it got there.
final class VendorAuditLogState extends Equatable {
  const VendorAuditLogState({
    this.phase = VendorAuditLogPhase.initial,
    this.events = const <VendorAuditLogEntry>[],
    this.failure,
    this.loadMoreFailure,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.hasReachedEnd = false,
  });

  final VendorAuditLogPhase phase;

  /// Every row loaded so far, **in the backend's order** (`occurred_at desc,
  /// audit_log_id desc` — newest first, and total, so two events written in one
  /// transaction cannot swap places between requests).
  ///
  /// Never re-sorted here. A second sort would be a second definition of the
  /// history order, it would immediately disagree with the web page showing the
  /// same rows, and — because the cursor is taken from the final element — it
  /// would move the next page's boundary.
  final List<VendorAuditLogEntry> events;

  /// Why the first read or a refresh failed. A discriminant; never the backend's
  /// own message.
  final Failure? failure;

  /// Why the most recent *older-page* read failed. Kept apart from [failure]
  /// because it is a smaller event: the rows above it are unaffected, and only
  /// the older request is worth retrying.
  final Failure? loadMoreFailure;

  /// True while a first read or a refresh is in flight.
  final bool isRefreshing;

  /// True while an older page is in flight.
  final bool isLoadingMore;

  /// True once a page came back shorter than the page size that was asked for —
  /// the only signal the contract offers for "there is nothing older".
  ///
  /// Recomputed on every successful read, including a refresh: a history that
  /// had reached its end can grow.
  final bool hasReachedEnd;

  /// Whether any read is in flight. One at a time, so a repeated tap cannot
  /// produce simultaneous requests and a refresh cannot race an older page whose
  /// cursor is about to be discarded.
  bool get isBusy => isRefreshing || isLoadingMore;

  /// A successful read that returned nothing — a Vendor with no recorded
  /// activity yet.
  ///
  /// A real, reachable state, and worded differently from a failure: the backend
  /// answered perfectly. On an audit surface that distinction is load-bearing,
  /// because "you may not read this history" and "this Vendor has recorded
  /// nothing" are opposite claims.
  bool get isEmpty => phase == VendorAuditLogPhase.ready && events.isEmpty;

  /// Rows are on screen but the last refresh did not succeed.
  bool get isStale => phase == VendorAuditLogPhase.failed && events.isNotEmpty;

  /// The first read failed with nothing to show.
  bool get hasFailedFirstRead =>
      phase == VendorAuditLogPhase.failed && events.isEmpty;

  /// Whether an "older activity" affordance should be offered at all.
  ///
  /// Only with rows loaded and no end reached. It is *not* hidden while a load
  /// is in flight — the control stays put and shows its own progress, so the
  /// foot of the list does not jump under a reader's thumb.
  bool get canLoadMore => events.isNotEmpty && !hasReachedEnd;

  /// Whether the end-of-history line belongs on screen: something was loaded,
  /// and there is nothing older.
  bool get showsEndOfHistory => events.isNotEmpty && hasReachedEnd;

  /// How many events are currently loaded.
  ///
  /// Strictly the number **held**, and it is labelled as such wherever it is
  /// shown. It is emphatically not a total: no total exists in the contract, and
  /// presenting a loaded count as one would understate a history by however many
  /// pages have not been asked for.
  int get loadedCount => events.length;

  VendorAuditLogState copyWith({
    VendorAuditLogPhase? phase,
    List<VendorAuditLogEntry>? events,
    Failure? failure,
    bool clearFailure = false,
    Failure? loadMoreFailure,
    bool clearLoadMoreFailure = false,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? hasReachedEnd,
  }) {
    return VendorAuditLogState(
      phase: phase ?? this.phase,
      events: events ?? this.events,
      failure: clearFailure ? null : (failure ?? this.failure),
      loadMoreFailure: clearLoadMoreFailure
          ? null
          : (loadMoreFailure ?? this.loadMoreFailure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    events,
    failure,
    loadMoreFailure,
    isRefreshing,
    isLoadingMore,
    hasReachedEnd,
  ];
}
