part of 'vendor_retailer_detail_cubit.dart';

/// Where the detail read has reached.
enum VendorRetailerDetailPhase {
  /// Nothing is open.
  initial,

  /// `get_vendor_retailer_detail` is in flight.
  loading,

  /// One authorized relationship is on screen.
  ready,

  /// The backend returned **zero rows**.
  ///
  /// One state for an unknown id, another Vendor's id and a malformed id alike.
  /// Not an error, not an outage, and not retryable: the backend answered, and
  /// it will answer the same way again.
  notFound,

  /// The read did not produce an answer — a denial, an expired session, a
  /// timeout, or a body that could not be understood.
  failed,
}

/// Where the companion shop read has reached.
///
/// Tracked separately from [VendorRetailerDetailPhase] because the two degrade
/// independently: a Retailer whose shops could not be loaded still has a name,
/// statuses, a country and counts that came from a call which succeeded.
enum VendorRetailerShopsPhase { initial, loading, ready, failed }

/// One open Retailer.
final class VendorRetailerDetailState extends Equatable {
  const VendorRetailerDetailState({
    this.relationshipId,
    this.phase = VendorRetailerDetailPhase.initial,
    this.detail,
    this.failure,
    this.shopsPhase = VendorRetailerShopsPhase.initial,
    this.shops = const <VendorRetailerShop>[],
    this.shopsFailure,
  });

  /// The relationship currently open, or null when nothing is.
  ///
  /// Held so a retry knows what to re-read. It is **not** rendered prominently:
  /// an internal identifier on screen is noise to a Vendor and a hint to anyone
  /// else looking at the device.
  final String? relationshipId;

  final VendorRetailerDetailPhase phase;

  /// The loaded row, present only in [VendorRetailerDetailPhase.ready].
  final VendorRetailerDetail? detail;

  /// Why the detail read failed. A discriminant; never the backend's message.
  final Failure? failure;

  final VendorRetailerShopsPhase shopsPhase;

  /// The shops, in the backend's `shop_name, shop_id` order. Not re-sorted.
  final List<VendorRetailerShop> shops;

  final Failure? shopsFailure;

  bool get isDetailLoading => phase == VendorRetailerDetailPhase.loading;

  /// A real, successful "this Retailer has no shops" — distinguishable from
  /// "not yours" only because the detail read came back first.
  bool get hasNoShops =>
      phase == VendorRetailerDetailPhase.ready &&
      shopsPhase == VendorRetailerShopsPhase.ready &&
      shops.isEmpty;

  VendorRetailerDetailState copyWith({
    String? relationshipId,
    VendorRetailerDetailPhase? phase,
    VendorRetailerDetail? detail,
    Failure? failure,
    VendorRetailerShopsPhase? shopsPhase,
    List<VendorRetailerShop>? shops,
    Failure? shopsFailure,
    bool clearShopsFailure = false,
  }) {
    return VendorRetailerDetailState(
      relationshipId: relationshipId ?? this.relationshipId,
      phase: phase ?? this.phase,
      detail: detail ?? this.detail,
      failure: failure ?? this.failure,
      shopsPhase: shopsPhase ?? this.shopsPhase,
      shops: shops ?? this.shops,
      shopsFailure: clearShopsFailure
          ? null
          : (shopsFailure ?? this.shopsFailure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    relationshipId,
    phase,
    detail,
    failure,
    shopsPhase,
    shops,
    shopsFailure,
  ];
}
