part of 'vendor_product_list_cubit.dart';

/// Where the catalogue read has reached.
enum VendorProductListPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// A catalogue is on screen.
  ready,

  /// The read did not produce an answer.
  failed,
}

/// The Vendor's product catalogue, plus the local narrowing applied to it.
final class VendorProductListState extends Equatable {
  const VendorProductListState({
    this.phase = VendorProductListPhase.initial,
    this.products = const <VendorProductSummary>[],
    this.failure,
    this.isRefreshing = false,
    this.searchTerm = '',
    this.statusFilter,
  });

  final VendorProductListPhase phase;

  /// Every row the backend returned, **in the backend's order**
  /// (`created_at desc, product_id desc` — newest first). Never re-sorted here:
  /// a second sort would be a second definition of the order, and it would
  /// immediately disagree with the web catalogue showing the same rows.
  final List<VendorProductSummary> products;

  /// Why the read failed. A discriminant; never the backend's own message.
  final Failure? failure;

  /// True while a read is in flight, including a silent refresh over an
  /// already-populated catalogue.
  final bool isRefreshing;

  /// The local search term. Applied case-insensitively across name, code,
  /// barcode and brand.
  final String searchTerm;

  /// The local status filter, or null for "all".
  final VendorProductStatus? statusFilter;

  /// Whether anything is currently narrowing the list.
  bool get hasFilters => searchTerm.trim().isNotEmpty || statusFilter != null;

  /// The rows to render.
  ///
  /// With no search and no filter this is [products] itself — the backend's
  /// order, untouched. `where` preserves order, so a narrowed list is a
  /// subsequence of it rather than a re-ranking, and clearing the narrowing
  /// restores the original order exactly.
  ///
  /// The search matches the four fields a reader can actually see on a card:
  /// **name, code, barcode and brand**. The description is excluded on purpose —
  /// matching a paragraph would surface rows whose reason for matching is
  /// invisible in the result.
  List<VendorProductSummary> get visibleProducts {
    if (!hasFilters) {
      return products;
    }
    final String needle = searchTerm.trim().toLowerCase();
    return products
        .where((VendorProductSummary product) {
          final bool matchesTerm =
              needle.isEmpty || product.searchHaystack.contains(needle);
          final bool matchesStatus =
              statusFilter == null || product.status == statusFilter;
          return matchesTerm && matchesStatus;
        })
        .toList(growable: false);
  }

  /// A successful read that returned nothing — a Vendor with no products yet.
  ///
  /// A real, reachable state, and worded differently from a failure: the
  /// backend answered perfectly.
  bool get isEmpty => phase == VendorProductListPhase.ready && products.isEmpty;

  /// Rows exist, but none survives the current narrowing. A different state
  /// from [isEmpty], and worded differently on screen.
  bool get hasNoMatches => products.isNotEmpty && visibleProducts.isEmpty;

  /// How many products the catalogue holds, before any narrowing.
  int get totalCount => products.length;

  /// Products whose stored status is `ACTIVE`.
  ///
  /// Counted by a positive test against a single status, so a token this build
  /// does not recognise is counted as neither active nor inactive rather than
  /// being folded into one of them. The total is therefore always honest and
  /// the breakdown never claims to be exhaustive.
  int get activeCount =>
      products.where((VendorProductSummary p) => p.status.isActive).length;

  /// Products whose stored status is `INACTIVE`.
  int get inactiveCount => products
      .where(
        (VendorProductSummary p) => p.status == VendorProductStatus.inactive,
      )
      .length;

  /// The total number of **active Retailer assignments** across the catalogue.
  ///
  /// A sum of `active_assignment_count`, so a Retailer holding four products
  /// contributes four. It is deliberately labelled as assignments rather than as
  /// Retailers: the number of *distinct* Retailers is a different question, and
  /// the list contract does not answer it.
  ///
  /// There is no catalogue-wide **total** assignment figure, because the list
  /// does not return `assignment_count` for any row and summing something the
  /// backend did not send would be inventing it.
  int get totalActiveAssignments => products.fold<int>(
    0,
    (int sum, VendorProductSummary p) => sum + p.activeAssignmentCount,
  );

  /// The statuses actually present in the loaded rows, in the enum's
  /// declaration order.
  ///
  /// Filter chips are built from this rather than from the enum, so the screen
  /// never offers a filter that can only ever produce an empty list — and never
  /// implies the backend uses a status it has not sent.
  /// [VendorProductStatus.unknown] is included when a future token actually
  /// arrived, because hiding those rows behind no chip at all would make them
  /// unreachable.
  List<VendorProductStatus> get presentStatuses {
    final Set<VendorProductStatus> present = products
        .map((VendorProductSummary p) => p.status)
        .toSet();
    return VendorProductStatus.values
        .where(present.contains)
        .toList(growable: false);
  }

  VendorProductListState copyWith({
    VendorProductListPhase? phase,
    List<VendorProductSummary>? products,
    Failure? failure,
    bool clearFailure = false,
    bool? isRefreshing,
    String? searchTerm,
    VendorProductStatus? statusFilter,
    bool clearStatusFilter = false,
  }) {
    return VendorProductListState(
      phase: phase ?? this.phase,
      products: products ?? this.products,
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
    products,
    failure,
    isRefreshing,
    searchTerm,
    statusFilter,
  ];
}
