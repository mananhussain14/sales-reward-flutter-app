import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../domain/entities/vendor_product_draft.dart';
import '../../../domain/entities/vendor_product_field.dart';
import '../../../domain/entities/vendor_product_input.dart';
import '../../../domain/repositories/vendor_product_repository.dart';
import '../../../domain/repositories/vendor_product_write_result.dart';

part 'vendor_product_create_state.dart';

/// Drives one `create_vendor_product` call, from an empty form to a product id.
///
/// ## The flow, in order
///
/// 1. The five fields are typed. Nothing is sent while typing, and nothing typed
///    is rewritten under the cursor.
/// 2. [submit] normalizes all five once, validates them for immediate feedback,
///    and stops there if anything is wrong.
/// 3. `create_vendor_product(p_product_code, p_product_name, p_barcode, p_brand,
///    p_description)` — five values, and no organization, tenant, user, profile,
///    role, permission, status or assignment argument, because the function has no
///    parameter for one.
/// 4. On the returned id: the catalogue is invalidated and the **canonical
///    product** is read through `get_vendor_product_detail`, which is what the
///    screen then shows. This cubit never assembles a product from the form — the
///    backend normalizes every field, so the stored values can legitimately differ
///    from what was typed, and echoing the form would present a guess as a record.
///
/// ## What it never does
///
/// * **It never creates twice.** [VendorProductCreateState.canSubmit] is false
///   while a call is in flight, and false again once one has succeeded — there is
///   no server-side idempotency here beyond the unique index, so a second call
///   with a different code would create a second product.
/// * **It never retries a succeeded create.** A create whose id could not be read
///   leaves [VendorProductCreatePhase.unconfirmed], which offers the catalogue and
///   not the button: the product exists, and pressing Create again would either
///   duplicate it or be refused as a duplicate code.
/// * **It never turns an outage into a denial**, or the reverse.
/// * **It never decides a create succeeded.** Only the repository's own success
///   case does, and only the canonical read says what was stored.
/// * **It never treats client-side validation as authority.** Every rule it
///   applies is applied again in SQL, and a value it accepts can still be refused.
final class VendorProductCreateCubit extends Cubit<VendorProductCreateState> {
  VendorProductCreateCubit(
    this._repository, {
    this.onProductCreated,
    this.onCatalogueStale,
  }) : super(const VendorProductCreateState());

  final VendorProductRepository _repository;

  /// Called once, with the new product's id, the moment a create succeeds.
  ///
  /// The shell wires this to the detail cubit's canonical read and to the
  /// catalogue's refresh. A callback rather than references to those cubits, so
  /// this class depends on nothing it does not use and a test can prove the
  /// read-after-write was requested without building two more cubits.
  final void Function(String productId)? onProductCreated;

  /// Called when the catalogue may have changed but no product id is available —
  /// the unconfirmed case. The catalogue is the only authority on what exists, so
  /// it is re-read rather than guessed at.
  final void Function()? onCatalogueStale;

  /// Discriminates the answer this cubit is waiting for, so a create issued under
  /// one identity can never populate a form — or navigate a screen — belonging to
  /// another. Advanced by [clear], which is what makes a session change drop an
  /// in-flight write rather than let it land.
  int _token = 0;

  /// Returns to a blank form.
  ///
  /// Called when the create route mounts. A no-op while a call is in flight, so a
  /// rebuild cannot discard a submission that is already on its way.
  void start() {
    if (state.phase == VendorProductCreatePhase.submitting) {
      return;
    }
    _token++;
    emit(const VendorProductCreateState());
  }

  void productCodeChanged(String value) => _edit(
    VendorProductField.productCode,
    (VendorProductFormValues v) => v.copyWith(productCode: value),
  );

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

  /// Validates, then creates.
  ///
  /// The first line is the duplicate-submit guard: a second call while one is in
  /// flight — or after one has succeeded — returns immediately, so two taps can
  /// never become two products.
  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }

    // Normalized once, here, and this is the only place it happens. The values a
    // person is typing are left alone until they ask for something to be done
    // with them, exactly as the web's action normalizes the submitted form rather
    // than each keystroke.
    final VendorProductFormValues normalized = state.values.normalized;
    final Map<VendorProductField, String> errors = validateVendorProductInput(
      normalized,
      VendorProductInputMode.create,
    );

    if (errors.isNotEmpty) {
      // Nothing is sent. The normalized values are adopted so the form shows what
      // would have been submitted — the web echoes the same canonical values back
      // for the same reason — and so a message about length or shape describes the
      // string it was actually computed from.
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
        phase: VendorProductCreatePhase.submitting,
        fieldErrors: const <VendorProductField, String>{},
        clearFailure: true,
      ),
    );

    final VendorProductWriteResult<String> result = await _repository
        .createProduct(
          VendorProductDraft(
            productCode: normalized.productCode,
            productName: normalized.productName,
            // Optional and clearable: an empty field is null on the wire, never
            // `''` and never a placeholder phrase.
            barcode: VendorProductInput.optionalOrNull(normalized.barcode),
            brand: VendorProductInput.optionalOrNull(normalized.brand),
            description: VendorProductInput.optionalOrNull(
              normalized.description,
            ),
          ),
        );

    if (isClosed || token != _token) {
      // A session change, or a second submission this one was superseded by.
      // Dropping the answer here is what stops one Vendor's create from
      // navigating another Vendor's session to a product they cannot read.
      return;
    }

    switch (result) {
      case VendorProductWriteSuccess<String>(:final String value):
        emit(
          state.copyWith(
            phase: VendorProductCreatePhase.created,
            createdProductId: value,
          ),
        );
        // The catalogue is invalidated and the canonical product is read, in that
        // order, by whoever owns those. Nothing here builds a product row.
        onProductCreated?.call(value);

      case VendorProductWriteUnconfirmed<String>():
        // The product EXISTS — the function commits or raises, never both — and
        // its id could not be read. Reported as a success that cannot be opened,
        // never as a failure, and never with the button re-armed.
        emit(state.copyWith(phase: VendorProductCreatePhase.unconfirmed));
        onCatalogueStale?.call();

      case VendorProductWriteFailure<String>(:final Failure failure):
        // Nothing was written: every refusal rolls the whole function back. So the
        // form comes back with its values intact and another attempt available.
        emit(_refused(failure));
    }
  }

  /// Drops the form, its validation, its progress, its errors and its success.
  ///
  /// Called when the signed-in person changes. Every one of those is private: a
  /// half-typed product code and description are this Vendor's unreleased
  /// catalogue data, and a created product's id is an address in their tenant.
  ///
  /// Advancing the token first means a create already in flight for the previous
  /// person cannot repopulate this form, cannot report a duplicate against their
  /// catalogue, and cannot navigate the new person to their product.
  void clear() {
    _token++;
    emit(const VendorProductCreateState());
  }

  void _edit(
    VendorProductField field,
    VendorProductFormValues Function(VendorProductFormValues) change,
  ) {
    if (state.phase == VendorProductCreatePhase.submitting ||
        state.phase == VendorProductCreatePhase.created ||
        state.phase == VendorProductCreatePhase.unconfirmed) {
      return;
    }

    // Editing the field a message is about clears that message, and clears the
    // form-level one too: neither describes what would happen now.
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

  /// The state a refusal produces: a field message where the backend attributed
  /// one, and a form-level discriminant otherwise.
  VendorProductCreateState _refused(Failure failure) {
    if (failure is DuplicateFailure) {
      final VendorProductField? field = VendorProductField.fromKey(
        failure.field,
      );
      if (field != null) {
        return state.copyWith(
          phase: VendorProductCreatePhase.editing,
          fieldErrors: <VendorProductField, String>{
            field: duplicateMessageFor(field),
          },
          clearFailure: true,
        );
      }
    }
    return state.copyWith(
      phase: VendorProductCreatePhase.editing,
      failure: failure,
      fieldErrors: const <VendorProductField, String>{},
    );
  }
}
