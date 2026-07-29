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
    this.isRefreshing = false,
    this.refreshFailure,
    this.notice,
    this.noticeRelationshipId,
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

  /// Whether a canonical re-read is in flight after a committed lifecycle
  /// write.
  ///
  /// The loaded Retailer stays on screen throughout: a refresh is not a reload,
  /// and blanking a Retailer to re-read two columns would make a saved change
  /// look like a page reset.
  final bool isRefreshing;

  /// Why the canonical re-read failed, if it did.
  ///
  /// **Not** a failed write. The write committed; only this client's picture of
  /// it is stale, which is why the loaded Retailer is kept and a Reload is
  /// offered rather than another attempt at the change.
  final Failure? refreshFailure;

  /// The lifecycle outcome this screen is acknowledging, or null.
  ///
  /// A statement about the past, chosen from the status the database confirmed.
  /// It never decides what is on screen — the re-read detail row does that.
  final VendorRetailerLifecycleNotice? notice;

  /// Which Retailer [notice] belongs to.
  ///
  /// Held so an acknowledgement can never appear under a different Retailer: two
  /// can be opened in sequence while one write is still settling.
  final String? noticeRelationshipId;

  bool get isDetailLoading => phase == VendorRetailerDetailPhase.loading;

  /// Whether an acknowledgement for [id] specifically should be shown.
  VendorRetailerLifecycleNotice? noticeFor(String id) =>
      noticeRelationshipId == id ? notice : null;

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
    bool? isRefreshing,
    Failure? refreshFailure,
    bool clearRefreshFailure = false,
    VendorRetailerLifecycleNotice? notice,
    String? noticeRelationshipId,
    bool clearDetail = false,
    bool clearNotice = false,
  }) {
    return VendorRetailerDetailState(
      relationshipId: relationshipId ?? this.relationshipId,
      phase: phase ?? this.phase,
      detail: clearDetail ? null : (detail ?? this.detail),
      failure: failure ?? this.failure,
      shopsPhase: shopsPhase ?? this.shopsPhase,
      shops: shops ?? this.shops,
      shopsFailure: clearShopsFailure
          ? null
          : (shopsFailure ?? this.shopsFailure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshFailure: clearRefreshFailure
          ? null
          : (refreshFailure ?? this.refreshFailure),
      notice: clearNotice ? null : (notice ?? this.notice),
      noticeRelationshipId: clearNotice
          ? null
          : (noticeRelationshipId ?? this.noticeRelationshipId),
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
    isRefreshing,
    refreshFailure,
    notice,
    noticeRelationshipId,
  ];
}
