part of 'vendor_product_edit_cubit.dart';

/// Where an edit has reached.
enum VendorProductEditPhase {
  /// No product is seeded. The screen is waiting on the canonical read, or that
  /// read answered "not available".
  initial,

  /// The form is open. Also where a refusal returns to, because a refusal wrote
  /// nothing.
  editing,

  /// `update_vendor_product` is in flight.
  submitting,

  /// The save settled as something the product screens must re-read.
  ///
  /// Reached both from a plain success and from the unconfirmed case, because the
  /// row is committed in both and the difference is only in how much this client
  /// can vouch for — which the notice carries, and which the canonical re-read
  /// then answers. Terminal: nothing re-arms Save, because the screen leaves for
  /// the product.
  saved,
}

/// Everything the edit screen renders from.
final class VendorProductEditState extends Equatable {
  const VendorProductEditState({
    this.productId,
    this.productCode = '',
    this.values = const VendorProductFormValues(),
    this.phase = VendorProductEditPhase.initial,
    this.fieldErrors = const <VendorProductField, String>{},
    this.failure,
  });

  /// The product being edited, from the canonical row rather than from the route.
  /// Null until [VendorProductEditCubit.seed] has run.
  final String? productId;

  /// The immutable product code, for read-only context.
  ///
  /// Read from the canonical row. There is no setter and no request field for it:
  /// it is on screen so a person knows which product they are editing, and it is
  /// never submitted.
  final String productCode;

  /// The four editable values, exactly as typed until a submission normalizes
  /// them.
  ///
  /// [VendorProductFormValues.productCode] is deliberately left empty here — the
  /// code lives in [productCode], outside the editable set, so nothing that
  /// assembles a request from these values can reach it.
  final VendorProductFormValues values;

  final VendorProductEditPhase phase;

  /// One message per offending field. This application's own words; never a
  /// Postgres message, table, column, constraint or SQLSTATE.
  final Map<VendorProductField, String> fieldErrors;

  /// A refusal that belongs to the form rather than to one field — a denial (which
  /// covers an unknown, foreign or malformed id identically), an expired session, a
  /// rejected value the backend did not attribute, an outage. A discriminant, never
  /// the backend's text.
  final Failure? failure;

  bool get isSeeded => productId != null;

  bool get isSubmitting => phase == VendorProductEditPhase.submitting;

  /// Whether Save may fire.
  ///
  /// True whenever the form is open, including when nothing has been changed: a
  /// no-op save is a silent success in SQL, and disabling Save on the strength of a
  /// local comparison would risk refusing a save the backend would have written —
  /// the one place a client-side normalization difference could cost somebody their
  /// change.
  bool get canSubmit => phase == VendorProductEditPhase.editing;

  /// The field a form should move focus to after a refused submission, in reading
  /// order.
  VendorProductField? get firstInvalidField {
    for (final VendorProductField field in VendorProductField.values) {
      if (fieldErrors.containsKey(field)) {
        return field;
      }
    }
    return null;
  }

  VendorProductEditState copyWith({
    String? productId,
    String? productCode,
    VendorProductFormValues? values,
    VendorProductEditPhase? phase,
    Map<VendorProductField, String>? fieldErrors,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return VendorProductEditState(
      productId: productId ?? this.productId,
      productCode: productCode ?? this.productCode,
      values: values ?? this.values,
      phase: phase ?? this.phase,
      fieldErrors: fieldErrors ?? this.fieldErrors,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    productId,
    productCode,
    values,
    phase,
    fieldErrors,
    failure,
  ];
}
