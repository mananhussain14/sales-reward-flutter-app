part of 'receipt_product_selection_cubit.dart';

/// Where the catalogue read has reached.
enum ReceiptProductSelectionPhase {
  /// Nothing has been read yet.
  initial,

  /// The catalogue read is in flight.
  loading,

  /// A catalogue is available. It may be empty — a Retailer with no assigned
  /// products is a real answer, not a failure and not a denial.
  ready,

  /// The read did not produce an answer. The selection built so far survives.
  failed,
}

/// A transient thing the UI must say out loud.
///
/// Both are refusals that would otherwise look like a dead tap. Neither is an
/// error state: the selection is still perfectly valid, and nothing was lost.
enum ReceiptProductSelectionNotice {
  /// The product is already on the list. Its line keeps its position and its
  /// quantity; the UI points at that line instead of adding a second one.
  alreadySelected,

  /// The list already holds 50 products, which is the database's ceiling.
  limitReached,
}

/// The product proposal as it is being built.
final class ReceiptProductSelectionState extends Equatable {
  const ReceiptProductSelectionState({
    this.phase = ReceiptProductSelectionPhase.initial,
    this.catalogue = const <ReceiptProduct>[],
    this.selection = const ReceiptProductSelection(),
    this.query = '',
    this.failure,
    this.notice,
    this.noticeProductId,
    this.isReadOnly = false,
  });

  final ReceiptProductSelectionPhase phase;

  /// Everything `list_my_receipt_products()` returned, in its own order.
  ///
  /// The backend returns only products ACTIVE and actively assigned to this
  /// Retailer, so an inactive or unassigned one is absent rather than filtered
  /// out here — there is no client-side rule that could be got wrong.
  final List<ReceiptProduct> catalogue;

  /// The chosen products, in selection order.
  final ReceiptProductSelection selection;

  /// The raw search text, exactly as typed. Trimming and case-folding happen in
  /// the matcher, so the field never fights the person using it.
  final String query;

  /// Why the catalogue read failed. A discriminant, never a backend message.
  final Failure? failure;

  final ReceiptProductSelectionNotice? notice;

  /// Which product the [notice] is about, so the UI can point at one line.
  final String? noticeProductId;

  /// True while the proposal may not change.
  final bool isReadOnly;

  bool get isLoading => phase == ReceiptProductSelectionPhase.loading;

  bool get hasFailed => phase == ReceiptProductSelectionPhase.failed;

  /// A real, successful "this Retailer has no products assigned".
  bool get isCatalogueEmpty =>
      phase == ReceiptProductSelectionPhase.ready && catalogue.isEmpty;

  /// The catalogue narrowed by [query], using the entity's own matcher so this
  /// screen cannot drift into a second definition of what "matches" means.
  List<ReceiptProduct> get visibleCatalogue {
    if (query.trim().isEmpty) {
      return catalogue;
    }
    return catalogue
        .where((ReceiptProduct product) => product.matches(query))
        .toList(growable: false);
  }

  /// A search that matched nothing — distinct from an empty catalogue, because
  /// the remedy is different.
  bool get hasNoSearchResults =>
      phase == ReceiptProductSelectionPhase.ready &&
      catalogue.isNotEmpty &&
      query.trim().isNotEmpty &&
      visibleCatalogue.isEmpty;

  bool isSelected(String productId) => selection.contains(productId);

  int? lineNumberOf(String productId) => selection.lineNumberOf(productId);

  List<SelectedReceiptProduct> get selectedProducts => selection.products;

  int get selectedCount => selection.lineCount;

  int get totalQuantity => selection.totalQuantity;

  bool get isFull => selection.isFull;

  bool get hasSelection => selection.isNotEmpty;

  /// The first rule the selection breaks, or null. Never suppressed while
  /// read-only: a settled proposal is still describable.
  ReceiptProductSelectionProblem? get problem => selection.validate();

  /// Whether the selection is in a shape the RPC would accept. It is **not** a
  /// promise the write will succeed — eligibility is the database's call.
  bool get isSubmittable => !isReadOnly && selection.isSubmittable;

  /// One frozen reading of the proposal, for the cubit that owns the write.
  ///
  /// Built on demand and never stored: the value is what travels, so the write
  /// holds a list that cannot change under it however this state moves on. The
  /// catalogue's ids travel with it so "every product came from the catalogue"
  /// is checkable at the other end rather than assumed.
  ReceiptProductProposalSnapshot get snapshot => ReceiptProductProposalSnapshot(
    selection: selection,
    catalogueProductIds: catalogue
        .map((ReceiptProduct product) => product.productId)
        .toSet(),
  );

  ReceiptProductSelectionState copyWith({
    ReceiptProductSelectionPhase? phase,
    List<ReceiptProduct>? catalogue,
    ReceiptProductSelection? selection,
    String? query,
    Failure? failure,
    bool clearFailure = false,
    ReceiptProductSelectionNotice? notice,
    String? noticeProductId,
    bool clearNotice = false,
    bool? isReadOnly,
  }) {
    return ReceiptProductSelectionState(
      phase: phase ?? this.phase,
      catalogue: catalogue ?? this.catalogue,
      selection: selection ?? this.selection,
      query: query ?? this.query,
      failure: clearFailure ? null : (failure ?? this.failure),
      notice: clearNotice ? null : (notice ?? this.notice),
      noticeProductId: clearNotice
          ? null
          : (noticeProductId ?? this.noticeProductId),
      isReadOnly: isReadOnly ?? this.isReadOnly,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    catalogue,
    selection,
    query,
    failure,
    notice,
    noticeProductId,
    isReadOnly,
  ];
}
