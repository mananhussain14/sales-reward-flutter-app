part of 'vendor_product_assignment_cubit.dart';

/// Where the candidate-Retailer read has reached.
///
/// Tracked separately from [VendorProductAssignmentPhase] because the two are
/// independent: a write can be in flight while no picker is open, and a picker
/// can be open while nothing is being written.
enum VendorProductAssignmentCandidatesPhase {
  /// No picker is open, and nothing has been composed.
  initial,

  /// `list_vendor_retailers()` is in flight.
  loading,

  /// The candidates are composed and current as of that read.
  ready,

  /// The Retailer directory did not answer. **Not** an empty directory: a denial
  /// and "you manage no Retailers" are opposite claims.
  failed,
}

/// Where an assignment transition has reached.
enum VendorProductAssignmentPhase {
  /// Nothing is being written. The actions sit at rest.
  idle,

  /// One of the two assignment RPCs is in flight.
  submitting,

  /// The transition settled as something the Product screens must re-read.
  ///
  /// Reached from a plain success and from the unconfirmed case alike, because
  /// the row is committed in both. What the assignment now looks like still
  /// changes only when the canonical reads say so.
  applied,

  /// The transition did not happen. The assignment is exactly as it was.
  failed,
}

/// One assignment surface: the choices it offers, and the decision in progress.
final class VendorProductAssignmentState extends Equatable {
  const VendorProductAssignmentState({
    this.productId,
    this.candidatesPhase = VendorProductAssignmentCandidatesPhase.initial,
    this.candidates = const <VendorProductAssignmentCandidate>[],
    this.candidatesFailure,
    this.searchTerm = '',
    this.pendingRetailerOrganizationId,
    this.pendingAction,
    this.phase = VendorProductAssignmentPhase.idle,
    this.failure,
    this.notice,
  });

  /// The Product this surface is about, or null when there is none.
  ///
  /// Held so a screen can tell a busy action from a busy *other* action: two
  /// Products can be opened in sequence while one request is still settling, and
  /// an action must not spin for a decision that was never about it.
  final String? productId;

  final VendorProductAssignmentCandidatesPhase candidatesPhase;

  /// Every Retailer the picker may offer, in `retailer_name,
  /// retailer_organization_id` order — the same total order both backend reads
  /// use.
  ///
  /// **Not filtered by eligibility.** An ineligible Retailer stays on the list
  /// with a neutral explanation, because a person looking for a Retailer that is
  /// simply absent learns nothing, and one who finds it with a reason learns why.
  final List<VendorProductAssignmentCandidate> candidates;

  /// Why the Retailer directory could not be read. A discriminant; never the
  /// backend's message.
  final Failure? candidatesFailure;

  /// The picker's local search term. Private data in its own right — it is
  /// usually a fragment of a Retailer's name — which is why it is cleared with
  /// everything else on a session change.
  final String searchTerm;

  /// The Retailer organization the in-flight or just-settled transition
  /// addresses, or null when there is none.
  final String? pendingRetailerOrganizationId;

  /// What that transition is doing. Three possible values, over two RPCs.
  final VendorProductAssignmentAction? pendingAction;

  final VendorProductAssignmentPhase phase;

  /// Why the transition did not happen. A discriminant, never the backend's
  /// text: one denial covers an unauthorized caller, an unknown or foreign
  /// Product, and an unknown, foreign, suspended or unrelated Retailer
  /// identically, exactly as SQL does, and says nothing about whether any of
  /// them exists.
  final Failure? failure;

  /// The transition that landed, so the screen can acknowledge it truthfully.
  final VendorProductWriteNotice? notice;

  /// The candidates matching [searchTerm], in the composed order.
  ///
  /// An empty term matches everything: an empty search is not a filter.
  List<VendorProductAssignmentCandidate> get visibleCandidates => candidates
      .where(
        (VendorProductAssignmentCandidate candidate) =>
            candidate.matches(searchTerm),
      )
      .toList(growable: false);

  /// Whether every loaded candidate was filtered out by the search term.
  ///
  /// Distinct from a Vendor with no Retailers at all, which is a different
  /// sentence entirely.
  bool get hasNoMatches =>
      candidatesPhase == VendorProductAssignmentCandidatesPhase.ready &&
      candidates.isNotEmpty &&
      visibleCandidates.isEmpty;

  /// A real, successful "this Vendor manages no Retailers".
  bool get hasNoCandidates =>
      candidatesPhase == VendorProductAssignmentCandidatesPhase.ready &&
      candidates.isEmpty;

  bool get isLoadingCandidates =>
      candidatesPhase == VendorProductAssignmentCandidatesPhase.loading;

  /// Whether a write is in flight. The duplicate-confirmation guard's visible
  /// half; the cubit enforces the same rule again.
  bool get isBusy => phase == VendorProductAssignmentPhase.submitting;

  /// Whether this state is about [id].
  bool describes(String id) => productId == id;

  /// Whether a transition is in flight for one specific pairing, so a second
  /// row's action never spins for a decision that was not about it.
  bool isBusyForPairing(String id, String retailerOrganizationId) =>
      isBusy &&
      describes(id) &&
      pendingRetailerOrganizationId == retailerOrganizationId;

  /// Whether a failure for [id] specifically is outstanding.
  bool hasFailureFor(String id) =>
      phase == VendorProductAssignmentPhase.failed && describes(id);

  /// The acknowledgement to show for [id], or null when there is none.
  ///
  /// Bound to the Product it was about, so an acknowledgement can never outlive
  /// its subject and start describing whatever the reader opened next.
  VendorProductWriteNotice? noticeFor(String id) =>
      describes(id) ? notice : null;

  /// This state with the picker's contents dropped, and everything else kept.
  ///
  /// Used when the picker closes and after a transition settles: eligibility
  /// described the moment before, and a reopened picker must ask again.
  VendorProductAssignmentState withoutCandidates() =>
      VendorProductAssignmentState(
        productId: productId,
        pendingRetailerOrganizationId: pendingRetailerOrganizationId,
        pendingAction: pendingAction,
        phase: phase,
        failure: failure,
        notice: notice,
      );

  /// This state with the write outcome dropped, and the picker kept.
  VendorProductAssignmentState withoutResult() => VendorProductAssignmentState(
    productId: productId,
    candidatesPhase: candidatesPhase,
    candidates: candidates,
    candidatesFailure: candidatesFailure,
    searchTerm: searchTerm,
  );

  VendorProductAssignmentState copyWith({
    String? productId,
    VendorProductAssignmentCandidatesPhase? candidatesPhase,
    List<VendorProductAssignmentCandidate>? candidates,
    Failure? candidatesFailure,
    bool clearCandidatesFailure = false,
    String? searchTerm,
    String? pendingRetailerOrganizationId,
    VendorProductAssignmentAction? pendingAction,
    VendorProductAssignmentPhase? phase,
    Failure? failure,
    bool clearFailure = false,
    VendorProductWriteNotice? notice,
    bool clearNotice = false,
  }) {
    return VendorProductAssignmentState(
      productId: productId ?? this.productId,
      candidatesPhase: candidatesPhase ?? this.candidatesPhase,
      candidates: candidates ?? this.candidates,
      candidatesFailure: clearCandidatesFailure
          ? null
          : (candidatesFailure ?? this.candidatesFailure),
      searchTerm: searchTerm ?? this.searchTerm,
      pendingRetailerOrganizationId:
          pendingRetailerOrganizationId ?? this.pendingRetailerOrganizationId,
      pendingAction: pendingAction ?? this.pendingAction,
      phase: phase ?? this.phase,
      failure: clearFailure ? null : (failure ?? this.failure),
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    productId,
    candidatesPhase,
    candidates,
    candidatesFailure,
    searchTerm,
    pendingRetailerOrganizationId,
    pendingAction,
    phase,
    failure,
    notice,
  ];
}
