part of 'vendor_product_create_cubit.dart';

/// Where a create has reached.
///
/// One enum rather than a sealed hierarchy, matching the receipt submission
/// state's reasoning: every phase shares the same surrounding data — the five
/// typed values outlive a refusal and must not be thrown away to recover from one.
enum VendorProductCreatePhase {
  /// The form is open. Also where a refusal returns to, because a refusal wrote
  /// nothing and another attempt is legitimate.
  editing,

  /// `create_vendor_product` is in flight.
  submitting,

  /// The product exists and its id is known. Terminal: nothing re-arms the
  /// button, because a second call would create a second product.
  created,

  /// The product exists and its id is **not** known.
  ///
  /// Terminal for the same reason, and more emphatically: pressing Create again
  /// would either duplicate the product or be refused by the unique index as a
  /// duplicate code, and neither is a useful thing to do to somebody who has
  /// already succeeded. The catalogue is the way forward.
  unconfirmed,
}

/// Everything the create screen renders from.
///
/// No raw backend map appears here, and neither does a product entity: a create
/// has nothing to show *about* a product, because the write returns only an id and
/// the canonical row is read and rendered by the detail screen.
final class VendorProductCreateState extends Equatable {
  const VendorProductCreateState({
    this.values = const VendorProductFormValues(),
    this.phase = VendorProductCreatePhase.editing,
    this.fieldErrors = const <VendorProductField, String>{},
    this.failure,
    this.createdProductId,
  });

  /// The five values, exactly as typed until a submission normalizes them.
  final VendorProductFormValues values;

  final VendorProductCreatePhase phase;

  /// One message per offending field.
  ///
  /// Produced by this application's own validator, or derived from a duplicate the
  /// backend attributed to a field. **Never** a Postgres message: no table,
  /// column, constraint, function name or SQLSTATE can reach a field label through
  /// this map.
  final Map<VendorProductField, String> fieldErrors;

  /// A refusal that belongs to the form rather than to one field — a denial, an
  /// expired session, a rejected value the backend did not attribute, an outage.
  /// A discriminant, never the backend's text.
  final Failure? failure;

  /// The id `create_vendor_product` returned. Present only in
  /// [VendorProductCreatePhase.created].
  ///
  /// An address and nothing more. It is used to read the canonical product and to
  /// navigate; it is never displayed, because an internal identifier on screen is
  /// noise and the product code is the identifier a person uses.
  final String? createdProductId;

  /// Whether the Create action may fire.
  ///
  /// False while submitting — the duplicate-tap guard's visible half, which the
  /// cubit enforces again so a stale widget cannot get past it — and false in both
  /// terminal phases, where the product already exists.
  bool get canSubmit => switch (phase) {
    VendorProductCreatePhase.editing => true,
    VendorProductCreatePhase.submitting ||
    VendorProductCreatePhase.created ||
    VendorProductCreatePhase.unconfirmed => false,
  };

  bool get isSubmitting => phase == VendorProductCreatePhase.submitting;

  /// The field a form should move focus to after a refused submission.
  ///
  /// Enum order, so focus lands on the first offending control in reading order
  /// rather than on whichever message happened to be computed first.
  VendorProductField? get firstInvalidField {
    for (final VendorProductField field in VendorProductField.values) {
      if (fieldErrors.containsKey(field)) {
        return field;
      }
    }
    return null;
  }

  VendorProductCreateState copyWith({
    VendorProductFormValues? values,
    VendorProductCreatePhase? phase,
    Map<VendorProductField, String>? fieldErrors,
    Failure? failure,
    bool clearFailure = false,
    String? createdProductId,
  }) {
    return VendorProductCreateState(
      values: values ?? this.values,
      phase: phase ?? this.phase,
      fieldErrors: fieldErrors ?? this.fieldErrors,
      failure: clearFailure ? null : (failure ?? this.failure),
      createdProductId: createdProductId ?? this.createdProductId,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    values,
    phase,
    fieldErrors,
    failure,
    createdProductId,
  ];
}
