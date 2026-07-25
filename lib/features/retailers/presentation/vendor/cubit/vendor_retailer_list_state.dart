part of 'vendor_retailer_list_cubit.dart';

/// Where the directory read has reached.
enum VendorRetailerListPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// A directory is on screen. It may be empty — which is a real answer ("this
  /// Vendor has not onboarded a Retailer yet"), not a failure, and certainly not
  /// a denial.
  ready,

  /// The read did not produce an answer.
  failed,
}

/// The Vendor's Retailer directory, plus the local narrowing applied to it.
final class VendorRetailerListState extends Equatable {
  const VendorRetailerListState({
    this.phase = VendorRetailerListPhase.initial,
    this.retailers = const <VendorRetailerSummary>[],
    this.failure,
    this.isRefreshing = false,
    this.searchTerm = '',
    this.statusFilter,
  });

  final VendorRetailerListPhase phase;

  /// Every row the backend returned, **in the backend's order**
  /// (`retailer_name, relationship_id`). Never re-sorted here.
  final List<VendorRetailerSummary> retailers;

  /// Why the read failed. A discriminant; never the backend's own message.
  final Failure? failure;

  /// True while a read is in flight, including a silent refresh over an
  /// already-populated directory.
  final bool isRefreshing;

  /// The local name search. Applied case-insensitively over [retailers].
  final String searchTerm;

  /// The local relationship-status filter, or null for "all".
  final VendorRetailerStatus? statusFilter;

  /// Whether anything is currently narrowing the list.
  bool get hasFilters => searchTerm.trim().isNotEmpty || statusFilter != null;

  /// The rows to render.
  ///
  /// With no search and no filter this is [retailers] itself — the backend's
  /// order, untouched. `where` preserves order, so a narrowed list is a
  /// subsequence of it rather than a re-ranking.
  List<VendorRetailerSummary> get visibleRetailers {
    if (!hasFilters) {
      return retailers;
    }
    final String needle = searchTerm.trim().toLowerCase();
    return retailers
        .where((VendorRetailerSummary retailer) {
          final bool matchesName =
              needle.isEmpty ||
              retailer.retailerName.toLowerCase().contains(needle);
          final bool matchesStatus =
              statusFilter == null ||
              retailer.relationshipStatus == statusFilter;
          return matchesName && matchesStatus;
        })
        .toList(growable: false);
  }

  /// A real, successful "this Vendor manages no Retailers".
  bool get isEmpty =>
      phase == VendorRetailerListPhase.ready && retailers.isEmpty;

  /// Rows exist, but none of them survives the current narrowing. A different
  /// state from [isEmpty], and worded differently on screen.
  bool get hasNoMatches => retailers.isNotEmpty && visibleRetailers.isEmpty;

  /// How many Retailers this Vendor is connected to, before any narrowing.
  int get totalCount => retailers.length;

  /// The shops across every connected Retailer — a sum of trusted per-row
  /// counts, never a second read.
  int get totalShopCount => retailers.fold<int>(
    0,
    (int sum, VendorRetailerSummary r) => sum + r.shopCount,
  );

  int get totalActiveShopCount => retailers.fold<int>(
    0,
    (int sum, VendorRetailerSummary r) => sum + r.activeShopCount,
  );

  /// The relationship statuses actually present in the loaded rows, in the
  /// enum's declaration order.
  ///
  /// Filter chips are built from this rather than from the enum, so the screen
  /// never offers a filter that can only ever produce an empty list — and never
  /// implies the backend uses a status it has not sent.
  /// [VendorRetailerStatus.unknown] is included when a future token actually
  /// arrived, because hiding those rows behind no chip at all would make them
  /// unreachable.
  List<VendorRetailerStatus> get presentRelationshipStatuses {
    final Set<VendorRetailerStatus> present = retailers
        .map((VendorRetailerSummary r) => r.relationshipStatus)
        .toSet();
    return VendorRetailerStatus.values
        .where(present.contains)
        .toList(growable: false);
  }

  VendorRetailerListState copyWith({
    VendorRetailerListPhase? phase,
    List<VendorRetailerSummary>? retailers,
    Failure? failure,
    bool clearFailure = false,
    bool? isRefreshing,
    String? searchTerm,
    VendorRetailerStatus? statusFilter,
    bool clearStatusFilter = false,
  }) {
    return VendorRetailerListState(
      phase: phase ?? this.phase,
      retailers: retailers ?? this.retailers,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      searchTerm: searchTerm ?? this.searchTerm,
      statusFilter: clearStatusFilter
          ? null
          : (statusFilter ?? this.statusFilter),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    retailers,
    failure,
    isRefreshing,
    searchTerm,
    statusFilter,
  ];
}
