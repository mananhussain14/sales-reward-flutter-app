part of 'retailer_shops_cubit.dart';

/// Where the shop read has reached.
enum RetailerShopsPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// Rows are on screen — possibly zero of them, which is a real answer.
  ready,

  /// The read did not produce an answer. With rows held this means a *refresh*
  /// failed and they are stale; with none it means the first read failed.
  failed,
}

/// The loaded estate, and how it got there.
///
/// Immutable, and holds **no raw Supabase map** — every value is a parsed domain
/// type. The map never leaves the data layer.
final class RetailerShopsState extends Equatable {
  const RetailerShopsState({
    this.phase = RetailerShopsPhase.initial,
    this.shops,
    this.problem,
    this.isRefreshing = false,
    this.searchTerm = '',
  });

  final RetailerShopsPhase phase;

  /// The rows, or null when none has been read.
  ///
  /// Null is **not** an empty estate and is never rendered as one. A list that
  /// could not be read has no rows at all; a Retailer with no shops has a real,
  /// successful empty answer. The screen must tell those apart, which is why
  /// this is nullable rather than defaulting to `[]`.
  final List<RetailerShop>? shops;

  /// Why the first read or a refresh failed. A discriminant; never the backend's
  /// own message, SQLSTATE, or any part of its response body.
  final RetailerReadProblem? problem;

  /// True while a read is in flight, first or subsequent. Also the
  /// duplicate-request guard.
  final bool isRefreshing;

  /// The local filter. Applied to rows already read; never sent anywhere.
  final String searchTerm;

  /// The rows to render, after the local filter.
  ///
  /// Matches **name, code and city** — exactly the fields the contract returns
  /// that a person would search by. Country is excluded deliberately: a
  /// two-letter code produces surprising matches against unrelated names, and
  /// status is a badge rather than a search term.
  ///
  /// Case-insensitive, and trimmed so a stray space does not empty the list.
  List<RetailerShop> get visibleShops {
    final List<RetailerShop> all = shops ?? const <RetailerShop>[];
    final String needle = searchTerm.trim().toLowerCase();
    if (needle.isEmpty) {
      return all;
    }
    return all
        .where((RetailerShop shop) {
          return shop.name.toLowerCase().contains(needle) ||
              (shop.code?.toLowerCase().contains(needle) ?? false) ||
              (shop.city?.toLowerCase().contains(needle) ?? false);
        })
        .toList(growable: false);
  }

  /// A search is active and hid everything — distinct from having no shops at
  /// all, and shown with different copy and a way back.
  bool get isSearchEmpty =>
      searchTerm.trim().isNotEmpty &&
      visibleShops.isEmpty &&
      (shops?.isNotEmpty ?? false);

  /// The backend genuinely returned nothing.
  bool get isEmpty =>
      phase == RetailerShopsPhase.ready && (shops?.isEmpty ?? false);

  /// Rows are on screen but the last refresh did not succeed.
  bool get isStale => phase == RetailerShopsPhase.failed && shops != null;

  /// The whole screen is a failure — the first read did not land.
  bool get hasFailedOutright =>
      phase == RetailerShopsPhase.failed && shops == null;

  /// The skeleton should be shown: a first read with nothing yet to display.
  bool get isInitialLoading =>
      phase == RetailerShopsPhase.loading && shops == null;

  RetailerShopsState copyWith({
    RetailerShopsPhase? phase,
    List<RetailerShop>? shops,
    RetailerReadProblem? problem,
    bool? isRefreshing,
    String? searchTerm,
    bool clearProblem = false,
  }) {
    return RetailerShopsState(
      phase: phase ?? this.phase,
      shops: shops ?? this.shops,
      // Explicit rather than inferred from null: `copyWith(problem: null)`
      // cannot be told from "leave it alone" in Dart, and a stale problem
      // surviving a successful refresh would leave an error notice above fresh
      // rows.
      problem: clearProblem ? null : (problem ?? this.problem),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      searchTerm: searchTerm ?? this.searchTerm,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    shops,
    problem,
    isRefreshing,
    searchTerm,
  ];
}
