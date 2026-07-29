part of 'vendor_retailer_lifecycle_cubit.dart';

/// Where a lifecycle change has reached.
enum VendorRetailerLifecyclePhase {
  /// No change is in progress. The action sits at rest.
  idle,

  /// `set_vendor_retailer_status` is in flight.
  submitting,

  /// The change settled as something the Retailer screens must re-read.
  ///
  /// Reached from a plain success and from the unconfirmed case alike, because
  /// the transaction committed in both. The visible statuses still change only
  /// when the canonical re-read says so.
  applied,

  /// The change did not happen. The previous statuses are still correct.
  failed,
}

/// One lifecycle decision in progress.
final class VendorRetailerLifecycleState extends Equatable {
  const VendorRetailerLifecycleState({
    this.relationshipId,
    this.pending,
    this.phase = VendorRetailerLifecyclePhase.idle,
    this.failure,
  });

  /// The Retailer this decision is about, or null when there is none.
  ///
  /// Held so a screen can tell a busy action from a busy *other* action: two
  /// Retailers can be opened in sequence while one request is still settling,
  /// and an action must not spin for a decision that was never about it.
  final String? relationshipId;

  /// The action being applied. Derived from the canonical pair before it reached
  /// this state, so a screen cannot substitute a different direction here.
  final VendorRetailerLifecycleAction? pending;

  final VendorRetailerLifecyclePhase phase;

  /// Why the change did not happen. A discriminant, never the backend's text: a
  /// denial covers an unauthorized caller, an unknown relationship and another
  /// Vendor's relationship identically, exactly as SQL does, and says nothing
  /// about whether any of them exists.
  final Failure? failure;

  /// Whether a request is in flight. The duplicate-submission guard's visible
  /// half; the cubit enforces the same rule again.
  bool get isBusy => phase == VendorRetailerLifecyclePhase.submitting;

  /// Whether this state is about [id].
  bool describes(String id) => relationshipId == id;

  /// Whether a request for [id] specifically is in flight, so a second
  /// Retailer's action never spins for a decision that was not about it.
  bool isBusyFor(String id) => isBusy && describes(id);

  /// Whether a failure for [id] specifically is outstanding.
  bool hasFailureFor(String id) =>
      phase == VendorRetailerLifecyclePhase.failed && describes(id);

  VendorRetailerLifecycleState copyWith({
    String? relationshipId,
    VendorRetailerLifecycleAction? pending,
    VendorRetailerLifecyclePhase? phase,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return VendorRetailerLifecycleState(
      relationshipId: relationshipId ?? this.relationshipId,
      pending: pending ?? this.pending,
      phase: phase ?? this.phase,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[relationshipId, pending, phase, failure];
}
