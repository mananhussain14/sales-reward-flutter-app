import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../domain/entities/receipt_product.dart';
import '../../../domain/entities/receipt_product_proposal_snapshot.dart';
import '../../../domain/entities/receipt_product_selection.dart';
import '../../../domain/entities/selected_receipt_product.dart';
import '../../../domain/repositories/receipt_repository.dart';
import '../../../domain/repositories/receipt_result.dart';

part 'receipt_product_selection_state.dart';

/// The Sales Staff product proposal, while it is still being built.
///
/// ## Why this is its own cubit
///
/// The receipt-review cubit is already 1,151 lines and owns extraction, the
/// currency lookup, the transaction draft and the confirmation. Product
/// selection is a self-contained problem with its own catalogue read, its own
/// search and its own validation, and proving it independently is cheaper than
/// proving it entangled. The submission integration is a separate, later step;
/// this cubit deliberately performs **no** write and knows nothing about
/// `confirm_receipt_with_products`.
///
/// ## One catalogue read, then everything is local
///
/// `list_my_receipt_products()` is called once. Search, selection, quantity and
/// removal never touch the network again — a request per keystroke or per tap
/// would put real latency between a person and a stepper for no gain, and the
/// catalogue cannot change under them mid-form in a way this screen could
/// usefully react to. The database re-checks every product's eligibility at
/// submission time anyway, which is where a stale catalogue is actually caught.
///
/// ## The catalogue is the only door
///
/// Selection takes a [ReceiptProduct] that came from that read. There is no
/// method here accepting a product id, a name or free text, so a product this
/// Retailer is not entitled to cannot enter the list — and the RPC would refuse
/// it regardless.
final class ReceiptProductSelectionCubit
    extends Cubit<ReceiptProductSelectionState> {
  ReceiptProductSelectionCubit(this._repository)
    : super(const ReceiptProductSelectionState());

  final ReceiptRepository _repository;

  /// Reads the authorized catalogue once.
  ///
  /// A failure degrades this section alone: it never blanks a selection the
  /// staff member has already built, because those products were legitimate
  /// when they were chosen and the submission will re-check them anyway.
  Future<void> loadCatalogue() async {
    if (state.phase == ReceiptProductSelectionPhase.loading) {
      return;
    }

    emit(
      state.copyWith(
        phase: ReceiptProductSelectionPhase.loading,
        clearFailure: true,
        clearNotice: true,
      ),
    );

    final ReceiptResult<List<ReceiptProduct>> result = await _repository
        .receiptProducts();

    if (isClosed) {
      return;
    }

    switch (result) {
      case ReceiptReadSuccess<List<ReceiptProduct>>(
        :final List<ReceiptProduct> value,
      ):
        emit(
          state.copyWith(
            phase: ReceiptProductSelectionPhase.ready,
            catalogue: value,
            clearFailure: true,
          ),
        );
      case ReceiptReadFailure<List<ReceiptProduct>>(:final Failure failure):
        emit(
          state.copyWith(
            phase: ReceiptProductSelectionPhase.failed,
            failure: failure,
          ),
        );
    }
  }

  /// Re-reads the catalogue after a failure. The same one call, never a loop.
  Future<void> retryCatalogue() => loadCatalogue();

  /// Filters locally. Never a request.
  void search(String query) {
    if (query == state.query) {
      return;
    }
    emit(state.copyWith(query: query, clearNotice: true));
  }

  /// Adds a catalogue product at quantity 1.
  ///
  /// Refuses silently in exactly two cases, each of which raises a notice the UI
  /// must surface rather than swallow:
  ///
  /// * the product is already selected — the existing line keeps its position
  ///   **and its quantity**, because quietly incrementing a number nobody typed
  ///   is how a proposal stops matching what a person meant;
  /// * the list already holds 50 — the 51st is refused and nothing is evicted.
  void select(ReceiptProduct product) {
    if (state.isReadOnly) {
      return;
    }

    final int? existingLine = state.selection.lineNumberOf(product.productId);
    if (existingLine != null) {
      emit(
        state.copyWith(
          notice: ReceiptProductSelectionNotice.alreadySelected,
          noticeProductId: product.productId,
        ),
      );
      return;
    }

    if (state.selection.isFull) {
      emit(
        state.copyWith(
          notice: ReceiptProductSelectionNotice.limitReached,
          noticeProductId: product.productId,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        selection: state.selection.add(product),
        clearNotice: true,
      ),
    );
  }

  void remove(String productId) {
    if (state.isReadOnly) {
      return;
    }
    emit(
      state.copyWith(
        selection: state.selection.remove(productId),
        clearNotice: true,
      ),
    );
  }

  void increment(String productId) {
    if (state.isReadOnly) {
      return;
    }
    emit(
      state.copyWith(
        selection: state.selection.increment(productId),
        clearNotice: true,
      ),
    );
  }

  void decrement(String productId) {
    if (state.isReadOnly) {
      return;
    }
    emit(
      state.copyWith(
        selection: state.selection.decrement(productId),
        clearNotice: true,
      ),
    );
  }

  /// Sets one line's quantity. Out-of-range values are ignored, not clamped:
  /// silently turning 250 into 100 would submit a number nobody chose.
  void setQuantity(String productId, int quantity) {
    if (state.isReadOnly) {
      return;
    }
    emit(
      state.copyWith(
        selection: state.selection.setQuantity(productId, quantity),
        clearNotice: true,
      ),
    );
  }

  /// Clears a transient notice once the UI has shown it.
  void dismissNotice() {
    if (state.notice == null) {
      return;
    }
    emit(state.copyWith(clearNotice: true));
  }

  /// Freezes or unfreezes every mutation.
  ///
  /// The capability the submission step will use: while an immutable write is
  /// in flight, and permanently once it has settled, nothing may change the
  /// list. Enforced here as well as in the widgets, so a stray callback cannot
  /// mutate a proposal that is already on its way to the database.
  void setReadOnly({required bool readOnly}) {
    if (state.isReadOnly == readOnly) {
      return;
    }
    emit(state.copyWith(isReadOnly: readOnly, clearNotice: true));
  }
}
