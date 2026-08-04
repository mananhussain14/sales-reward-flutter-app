import 'package:equatable/equatable.dart';

import 'receipt_product_selection.dart';
import 'selected_receipt_product.dart';

/// One frozen reading of the product proposal, taken at the instant a person
/// asked for it to be submitted.
///
/// ## Why a snapshot exists at all
///
/// The proposal is built in [ReceiptProductSelectionCubit] and written by
/// [ReceiptReviewCubit], and neither may hold the other: a write cubit that
/// could reach into a selection cubit could also read it *again* halfway
/// through an immutable write, and a selection cubit that could reach the
/// repository would be a second door to the same one-shot RPC.
///
/// So the value travels instead of the reference. The page reads the selection
/// once, wraps it here, and hands it over; from that moment the write owns a
/// list that cannot change under it, whatever the widgets above go on to do.
///
/// ## The catalogue comes with it, and only its ids
///
/// [catalogueProductIds] is what makes "every selected product came from the
/// catalogue this screen loaded" a checkable statement rather than an
/// assumption about which methods a cubit happens to expose. Only the ids
/// travel — no name, code, barcode or brand — because membership is the only
/// question being asked.
///
/// It is a **pre-check and not the authority**: the real rule is "ACTIVE and
/// actively assigned to this Retailer at proposal time", the database applies
/// it inside the same transaction as the write, and a catalogue read that
/// finished a minute ago cannot answer it.
final class ReceiptProductProposalSnapshot extends Equatable {
  const ReceiptProductProposalSnapshot({
    required this.selection,
    required this.catalogueProductIds,
  });

  /// An empty snapshot, which validates as [
  /// ReceiptProductSelectionProblem.noProductsSelected].
  static const ReceiptProductProposalSnapshot empty =
      ReceiptProductProposalSnapshot(
        selection: ReceiptProductSelection(),
        catalogueProductIds: <String>{},
      );

  /// The chosen products, in the order they will be numbered. Order is the
  /// proposal: nothing here sorts, merges or reorders.
  final ReceiptProductSelection selection;

  /// The ids `list_my_receipt_products()` returned for this screen.
  final Set<String> catalogueProductIds;

  /// The first rule this snapshot breaks, or null when it breaks none.
  ///
  /// The selection's own rules come first — empty, over fifty, a quantity out
  /// of range, a duplicate id — and the catalogue membership check is layered
  /// on top, because it is the one question a selection cannot answer alone.
  ReceiptProductSelectionProblem? validate() {
    final ReceiptProductSelectionProblem? problem = selection.validate();
    if (problem != null) {
      return problem;
    }
    for (final SelectedReceiptProduct product in selection.products) {
      if (!catalogueProductIds.contains(product.productId)) {
        return ReceiptProductSelectionProblem.notInCatalogue;
      }
    }
    return null;
  }

  bool get isSubmittable => validate() == null;

  @override
  List<Object?> get props => <Object?>[selection, catalogueProductIds];
}
