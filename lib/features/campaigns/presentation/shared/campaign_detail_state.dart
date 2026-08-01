part of 'campaign_detail_cubit.dart';

/// Where the campaign detail read has reached.
enum CampaignDetailPhase {
  /// No campaign has been opened yet.
  initial,

  /// A read is in flight.
  loading,

  /// A campaign is on screen.
  ready,

  /// The backend answered, and the answer was "nothing here for you".
  ///
  /// Deliberately **not** [failed]: it is a settled answer rather than an
  /// outage, so the screen offers a way back rather than a retry.
  notFound,

  /// The read did not complete.
  failed,
}

/// One campaign, its products, and how they got there.
final class CampaignDetailState extends Equatable {
  const CampaignDetailState({
    required this.audience,
    this.campaignId,
    this.phase = CampaignDetailPhase.initial,
    this.campaign,
    this.products = const <CampaignProduct>[],
    this.problem,
  });

  /// Which role is reading. Fixed for the life of the cubit.
  final CampaignAudience audience;

  /// The id currently open, or null before one is.
  ///
  /// Held so [CampaignDetailCubitBase.open] can be idempotent and
  /// [CampaignDetailCubitBase.refresh] knows what to re-read. **Never
  /// rendered**: it is an address, and a UUID on a screen is noise a reader
  /// cannot act on.
  final String? campaignId;

  final CampaignDetailPhase phase;

  /// The campaign, or null in every phase but [CampaignDetailPhase.ready].
  final CampaignPresentation? campaign;

  /// The products this campaign counts for the reading Retailer.
  ///
  /// Empty is a real answer — the zero-eligible-product state — and never a
  /// substitute for a failed read: the repository reports a failed product read
  /// as a failure, so an empty list here always came from the backend.
  final List<CampaignProduct> products;

  /// Why the read failed. A discriminant; never backend text.
  final RetailerReadProblem? problem;

  bool get isLoading => phase == CampaignDetailPhase.loading;

  CampaignDetailState copyWith({
    CampaignDetailPhase? phase,
    CampaignPresentation? campaign,
    List<CampaignProduct>? products,
    RetailerReadProblem? problem,
  }) {
    return CampaignDetailState(
      audience: audience,
      campaignId: campaignId,
      phase: phase ?? this.phase,
      campaign: campaign ?? this.campaign,
      products: products ?? this.products,
      problem: problem ?? this.problem,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    audience,
    campaignId,
    phase,
    campaign,
    products,
    problem,
  ];
}
