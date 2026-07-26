import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../domain/entities/vendor_product_detail.dart';
import '../../../domain/entities/vendor_product_edit.dart';
import '../../../domain/entities/vendor_product_field.dart';
import '../../../domain/entities/vendor_product_input.dart';
import '../../../domain/repositories/vendor_product_repository.dart';
import '../../../domain/repositories/vendor_product_write_result.dart';
import 'vendor_product_write_notice.dart';

part 'vendor_product_edit_state.dart';

/// Drives one `update_vendor_product` call over one already-loaded product.
///
/// ## The form is seeded from the canonical product, never from the route
///
/// [seed] takes a [VendorProductDetail] — a row `get_vendor_product_detail`
/// returned — and nothing else. The route contributes an **id** and no content, so
/// a link cannot pre-fill a name, a barcode, a brand or a description, and a
/// tampered URL cannot put a value into a form that is then saved back as though a
/// person had typed it.
///
/// That also settles the malformed-id case without a special path: a form is only
/// seeded once a canonical read returned a row, and a malformed id can never
/// return one, so a mistyped URL reaches the same non-leaking "not available"
/// screen the detail route reaches and no write is reachable from it. The
/// repository guards the id again at the boundary that talks to PostgREST.
///
/// ## The product code is shown and never sent
///
/// [VendorProductEditState.productCode] exists so the screen can show which
/// product is being edited, as read-only context. It is a *label*: there is no
/// setter for it, [VendorProductEdit] has no field for it, and
/// `update_vendor_product` has no parameter for it. The code is the canonical key
/// that assignments are made against and a future receipt-matching step will
/// resolve, so re-keying an entry in place would silently change what every
/// downstream reference means — which is why the storage migration enforces it
/// with a trigger and why a miscoded product is replaced rather than renamed.
///
/// ## The status is not here either
///
/// `update_vendor_product` never touches `status`, so there is no status control,
/// no status value and no status parameter anywhere in this cubit. Activating and
/// deactivating is a separate action with a separate RPC.
///
/// ## A no-op save is a success
///
/// A submission in which none of the four values differs from what is stored
/// writes nothing, moves no `updated_at` and records no audit row — and returns
/// exactly what a real change returns. The contract makes the two deliberately
/// indistinguishable, so nothing here tries to tell them apart, no Save is disabled
/// on the strength of a local comparison, and the acknowledgement is worded to be
/// true either way.
final class VendorProductEditCubit extends Cubit<VendorProductEditState> {
  VendorProductEditCubit(this._repository, {this.onProductWritten})
    : super(const VendorProductEditState());

  final VendorProductRepository _repository;

  /// Called once when a save settles as something the product screens must
  /// re-read: the shell wires it to the detail cubit's canonical refresh and to
  /// the catalogue's.
  ///
  /// A callback rather than references to those cubits, so this class depends on
  /// nothing it does not use and a test can prove the read-after-write was
  /// requested without building two more cubits.
  final void Function(VendorProductWriteNotice notice)? onProductWritten;

  int _token = 0;

  /// Fills the form from a canonical product row.
  ///
  /// Idempotent for the product it is already showing, so a rebuild or a router
  /// refresh cannot discard half-typed edits by re-seeding them. A **different**
  /// product always starts a fresh form, and so does the same product after
  /// [clear].
  ///
  /// A no-op while a save is in flight or has settled: re-seeding then would
  /// either race the submission or silently replace what was just saved.
  void seed(VendorProductDetail detail) {
    if (state.productId == detail.productId &&
        state.phase != VendorProductEditPhase.initial) {
      return;
    }
    if (state.phase == VendorProductEditPhase.submitting) {
      return;
    }

    _token++;
    emit(
      VendorProductEditState(
        productId: detail.productId,
        productCode: detail.productCode,
        phase: VendorProductEditPhase.editing,
        // A null optional seeds an empty control, not the phrase the detail screen
        // renders for one: "Not recorded" is how this client displays an absent
        // value and must never become a value it stores.
        values: VendorProductFormValues(
          productName: detail.productName,
          barcode: detail.barcode ?? '',
          brand: detail.brand ?? '',
          description: detail.description ?? '',
        ),
      ),
    );
  }

  void productNameChanged(String value) => _edit(
    VendorProductField.productName,
    (VendorProductFormValues v) => v.copyWith(productName: value),
  );

  void barcodeChanged(String value) => _edit(
    VendorProductField.barcode,
    (VendorProductFormValues v) => v.copyWith(barcode: value),
  );

  void brandChanged(String value) => _edit(
    VendorProductField.brand,
    (VendorProductFormValues v) => v.copyWith(brand: value),
  );

  void descriptionChanged(String value) => _edit(
    VendorProductField.description,
    (VendorProductFormValues v) => v.copyWith(description: value),
  );

  /// Validates, then saves.
  ///
  /// The first line is the duplicate-submit guard: a second call while one is in
  /// flight returns immediately, so two taps are one write.
  Future<void> submit() async {
    final String? productId = state.productId;
    if (productId == null || !state.canSubmit) {
      return;
    }

    final VendorProductFormValues normalized = state.values.normalized;
    // `update` mode, so the product code is not validated: validating a value the
    // form cannot send would be a rule with no subject, and any message it
    // produced would describe a field nobody can change.
    final Map<VendorProductField, String> errors = validateVendorProductInput(
      normalized,
      VendorProductInputMode.update,
    );

    if (errors.isNotEmpty) {
      emit(
        state.copyWith(
          values: normalized,
          fieldErrors: errors,
          clearFailure: true,
        ),
      );
      return;
    }

    final int token = ++_token;
    emit(
      state.copyWith(
        values: normalized,
        phase: VendorProductEditPhase.submitting,
        fieldErrors: const <VendorProductField, String>{},
        clearFailure: true,
      ),
    );

    final VendorProductWriteResult<void>
    result = await _repository.updateProduct(
      productId,
      VendorProductEdit(
        productName: normalized.productName,
        // Emptied optionals arrive as null, which is how the backend clears them.
        // All four are sent on every save because the RPC writes all four: an
        // omitted one would clear a stored value nobody asked to clear.
        barcode: VendorProductInput.optionalOrNull(normalized.barcode),
        brand: VendorProductInput.optionalOrNull(normalized.brand),
        description: VendorProductInput.optionalOrNull(normalized.description),
        // No product code, and no status. Neither exists on this request type.
      ),
    );

    if (isClosed || token != _token) {
      // A session change, a re-seed, or a submission this one was superseded by.
      // Dropping the answer here is what stops one Vendor's save from reporting a
      // duplicate — or a success — into another Vendor's session.
      return;
    }

    switch (result) {
      case VendorProductWriteSuccess<void>():
        emit(state.copyWith(phase: VendorProductEditPhase.saved));
        onProductWritten?.call(VendorProductWriteNotice.updated);

      case VendorProductWriteUnconfirmed<void>():
        // 2xx with a body this build cannot read. The row and its audit row are
        // committed, so this is never reported as a failed save; the canonical
        // re-read is what then says what the product looks like.
        emit(state.copyWith(phase: VendorProductEditPhase.saved));
        onProductWritten?.call(VendorProductWriteNotice.updateUnconfirmed);

      case VendorProductWriteFailure<void>(:final Failure failure):
        // Nothing was written — a refused edit rolls back completely, including a
        // name change that accompanied a duplicate barcode — so the typed values
        // stay and another attempt is legitimate.
        emit(_refused(failure));
    }
  }

  /// Drops the form, its validation, its progress, its errors and its result.
  ///
  /// Called when the signed-in person changes. Half-typed product details are this
  /// Vendor's own catalogue data, and the product id is an address in their tenant.
  /// Advancing the token first means a save already in flight for the previous
  /// person cannot report into the new one's session.
  void clear() {
    _token++;
    emit(const VendorProductEditState());
  }

  void _edit(
    VendorProductField field,
    VendorProductFormValues Function(VendorProductFormValues) change,
  ) {
    if (state.phase != VendorProductEditPhase.editing) {
      return;
    }

    final Map<VendorProductField, String> remaining =
        Map<VendorProductField, String>.of(state.fieldErrors)..remove(field);

    emit(
      state.copyWith(
        values: change(state.values),
        fieldErrors: remaining,
        clearFailure: true,
      ),
    );
  }

  VendorProductEditState _refused(Failure failure) {
    if (failure is DuplicateFailure) {
      final VendorProductField? field = VendorProductField.fromKey(
        failure.field,
      );
      // A duplicate attributed to the product code cannot happen on this path —
      // the code is not a parameter, so an edit cannot collide on it — but the
      // mapping is not special-cased here: if the backend ever attributed one, the
      // honest thing is to say so against that field rather than to swallow it.
      if (field != null) {
        return state.copyWith(
          phase: VendorProductEditPhase.editing,
          fieldErrors: <VendorProductField, String>{
            field: duplicateMessageFor(field),
          },
          clearFailure: true,
        );
      }
    }
    return state.copyWith(
      phase: VendorProductEditPhase.editing,
      failure: failure,
      fieldErrors: const <VendorProductField, String>{},
    );
  }
}
