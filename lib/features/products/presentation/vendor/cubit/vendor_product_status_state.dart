part of 'vendor_product_status_cubit.dart';

/// Where a status change has reached.
enum VendorProductStatusPhase {
  /// No status change is in progress. The action sits at rest.
  idle,

  /// `set_vendor_product_status` is in flight.
  submitting,

  /// The change settled as something the product screens must re-read.
  ///
  /// Reached from a plain success and from the unconfirmed case alike, because the
  /// row is committed in both. The visible status still changes only when the
  /// canonical re-read says so.
  applied,

  /// The change did not happen. The previous status is still correct.
  failed,
}

/// One status decision in progress.
final class VendorProductStatusState extends Equatable {
  const VendorProductStatusState({
    this.productId,
    this.pending,
    this.phase = VendorProductStatusPhase.idle,
    this.failure,
  });

  /// The product this decision is about, or null when there is none.
  ///
  /// Held so a screen can tell a busy action from a busy *other* action: two
  /// products can be opened in sequence while one request is still settling, and an
  /// action must not spin for a decision that was never about it.
  final String? productId;

  /// The change being applied. Two possible values and no third — the response
  /// enum's forward-compatibility `unknown` is not expressible here.
  final VendorProductStatusChange? pending;

  final VendorProductStatusPhase phase;

  /// Why the change did not happen. A discriminant, never the backend's text: a
  /// denial covers an unauthorized caller, an unknown product and a foreign product
  /// identically, exactly as SQL does, and says nothing about whether the product
  /// exists.
  final Failure? failure;

  /// Whether a request is in flight. The duplicate-confirmation guard's visible
  /// half; the cubit enforces the same rule again.
  bool get isBusy => phase == VendorProductStatusPhase.submitting;

  /// Whether this state is about [id].
  bool describes(String id) => productId == id;

  /// Whether a request for [id] specifically is in flight, so a second product's
  /// action never spins for a decision that was not about it.
  bool isBusyFor(String id) => isBusy && describes(id);

  /// Whether a failure for [id] specifically is outstanding.
  bool hasFailureFor(String id) =>
      phase == VendorProductStatusPhase.failed && describes(id);

  VendorProductStatusState copyWith({
    String? productId,
    VendorProductStatusChange? pending,
    VendorProductStatusPhase? phase,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return VendorProductStatusState(
      productId: productId ?? this.productId,
      pending: pending ?? this.pending,
      phase: phase ?? this.phase,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[productId, pending, phase, failure];
}
