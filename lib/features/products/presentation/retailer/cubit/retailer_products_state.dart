part of 'retailer_products_cubit.dart';

/// Where the assigned-product read has reached.
enum RetailerProductsPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// Rows are on screen — possibly zero, which is a real answer.
  ready,

  /// The read did not produce an answer.
  failed,
}

/// The loaded assigned catalogue, and how it got there.
///
/// Immutable, and holds **no raw Supabase map** — every value is a parsed domain
/// type.
final class RetailerProductsState extends Equatable {
  const RetailerProductsState({
    this.phase = RetailerProductsPhase.initial,
    this.products,
    this.problem,
    this.isRefreshing = false,
    this.searchTerm = '',
  });

  final RetailerProductsPhase phase;

  /// The rows, or null when none has been read.
  ///
  /// Null is **not** an empty catalogue and is never rendered as one. A list
  /// that could not be read has no rows at all; a Retailer with no assignments
  /// has a real, successful empty answer.
  final List<RetailerAssignedProduct>? products;

  /// Why the read failed. A discriminant; never backend text.
  final RetailerReadProblem? problem;

  final bool isRefreshing;

  /// The local filter. Applied to rows already read; never sent anywhere.
  final String searchTerm;

  /// The rows to render, after the local filter.
  ///
  /// Matches **name, code, brand and barcode** — the four fields a person would
  /// look a product up by, and exactly the searchable ones the contract returns.
  /// Description is excluded: it is free prose, so matching it produces hits a
  /// user cannot see the reason for in a card that truncates it.
  List<RetailerAssignedProduct> get visibleProducts {
    final List<RetailerAssignedProduct> all =
        products ?? const <RetailerAssignedProduct>[];
    final String needle = searchTerm.trim().toLowerCase();
    if (needle.isEmpty) {
      return all;
    }
    return all
        .where((RetailerAssignedProduct product) {
          return product.productName.toLowerCase().contains(needle) ||
              product.productCode.toLowerCase().contains(needle) ||
              (product.brand?.toLowerCase().contains(needle) ?? false) ||
              (product.barcode?.toLowerCase().contains(needle) ?? false);
        })
        .toList(growable: false);
  }

  /// A search is active and hid everything — distinct from having no products.
  bool get isSearchEmpty =>
      searchTerm.trim().isNotEmpty &&
      visibleProducts.isEmpty &&
      (products?.isNotEmpty ?? false);

  /// The backend genuinely returned nothing.
  bool get isEmpty =>
      phase == RetailerProductsPhase.ready && (products?.isEmpty ?? false);

  bool get isStale => phase == RetailerProductsPhase.failed && products != null;

  bool get hasFailedOutright =>
      phase == RetailerProductsPhase.failed && products == null;

  bool get isInitialLoading =>
      phase == RetailerProductsPhase.loading && products == null;

  RetailerProductsState copyWith({
    RetailerProductsPhase? phase,
    List<RetailerAssignedProduct>? products,
    RetailerReadProblem? problem,
    bool? isRefreshing,
    String? searchTerm,
    bool clearProblem = false,
  }) {
    return RetailerProductsState(
      phase: phase ?? this.phase,
      products: products ?? this.products,
      // Explicit, because `copyWith(problem: null)` cannot be told from "leave
      // it alone" in Dart.
      problem: clearProblem ? null : (problem ?? this.problem),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      searchTerm: searchTerm ?? this.searchTerm,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    products,
    problem,
    isRefreshing,
    searchTerm,
  ];
}
