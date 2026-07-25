part of 'vendor_user_detail_cubit.dart';

/// Where the detail read has reached.
enum VendorUserDetailPhase {
  /// Nothing is open.
  initial,

  /// `get_vendor_user_detail` is in flight.
  loading,

  /// One authorized membership is on screen.
  ready,

  /// The backend returned **zero rows**.
  ///
  /// One state for an unknown id, another Vendor's id, a Retailer-owned
  /// membership id and a malformed id alike. Not an error, not an outage, and
  /// not retryable: the backend answered, and it will answer the same way again.
  notFound,

  /// The read did not produce an answer — a denial, an expired session, a
  /// timeout, or a body that could not be understood.
  failed,
}

/// One open Vendor user.
final class VendorUserDetailState extends Equatable {
  const VendorUserDetailState({
    this.membershipId,
    this.phase = VendorUserDetailPhase.initial,
    this.detail,
    this.failure,
  });

  /// The membership currently open, or null when nothing is.
  ///
  /// Held so a retry knows what to re-read, and so [VendorUserDetailCubit.open]
  /// can recognise a repeat. It is **not** rendered as a primary field: an
  /// internal identifier on screen is noise to a Vendor and a hint to anyone
  /// else looking at the device.
  final String? membershipId;

  final VendorUserDetailPhase phase;

  /// The loaded row, present only in [VendorUserDetailPhase.ready].
  final VendorUserDetail? detail;

  /// Why the read failed. A discriminant; never the backend's message.
  final Failure? failure;

  bool get isLoading => phase == VendorUserDetailPhase.loading;

  VendorUserDetailState copyWith({
    String? membershipId,
    VendorUserDetailPhase? phase,
    VendorUserDetail? detail,
    Failure? failure,
  }) {
    return VendorUserDetailState(
      membershipId: membershipId ?? this.membershipId,
      phase: phase ?? this.phase,
      detail: detail ?? this.detail,
      failure: failure ?? this.failure,
    );
  }

  @override
  List<Object?> get props => <Object?>[membershipId, phase, detail, failure];
}
