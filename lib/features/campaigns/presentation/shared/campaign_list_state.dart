part of 'campaign_list_cubit.dart';

/// Where the campaign list read has reached.
enum CampaignListPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// Campaigns are on screen — possibly zero, which is a real answer.
  ready,

  /// The read did not produce an answer.
  failed,
}

/// The loaded campaign list, and how it got there.
///
/// Immutable, and holds **no raw Supabase map** — every value is a parsed
/// domain type wrapped in a role-neutral [CampaignPresentation].
final class CampaignListState extends Equatable {
  const CampaignListState({
    required this.audience,
    this.phase = CampaignListPhase.initial,
    this.campaigns,
    this.problem,
    this.isRefreshing = false,
  });

  /// Which role is reading. Fixed for the life of the cubit and preserved
  /// across [CampaignListCubitBase.clear], because a cubit does not change
  /// which contract it reads — a different role gets a different cubit in a
  /// different shell.
  final CampaignAudience audience;

  final CampaignListPhase phase;

  /// The campaigns, or null when none has been read.
  ///
  /// Null is **not** an empty list and is never rendered as one. A list that
  /// could not be read has no campaigns at all; a Retailer that nobody targets
  /// has a real, successful empty answer.
  final List<CampaignPresentation>? campaigns;

  /// Why the read failed. A discriminant; never backend text.
  final RetailerReadProblem? problem;

  final bool isRefreshing;

  /// The campaigns grouped into the headings a list renders, empty sections
  /// omitted.
  ///
  /// Computed rather than stored, so there is exactly one grouping rule and no
  /// way for a stored copy to fall out of step with the campaigns beside it.
  List<CampaignSection> get sections =>
      groupCampaignsIntoSections(campaigns ?? const <CampaignPresentation>[]);

  /// The backend genuinely returned nothing.
  bool get isEmpty =>
      phase == CampaignListPhase.ready && (campaigns?.isEmpty ?? false);

  /// A refresh failed while earlier rows are still on screen. They stay, and
  /// the screen says they may be out of date.
  bool get isStale => phase == CampaignListPhase.failed && campaigns != null;

  /// Nothing was ever loaded and the read failed. The whole screen becomes the
  /// problem view: an unreadable answer must never be shown as an empty list.
  bool get hasFailedOutright =>
      phase == CampaignListPhase.failed && campaigns == null;

  bool get isInitialLoading =>
      phase == CampaignListPhase.loading && campaigns == null;

  CampaignListState copyWith({
    CampaignListPhase? phase,
    List<CampaignPresentation>? campaigns,
    RetailerReadProblem? problem,
    bool? isRefreshing,
    bool clearProblem = false,
  }) {
    return CampaignListState(
      audience: audience,
      phase: phase ?? this.phase,
      campaigns: campaigns ?? this.campaigns,
      // Explicit, because `copyWith(problem: null)` cannot be told from "leave
      // it alone" in Dart.
      problem: clearProblem ? null : (problem ?? this.problem),
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    audience,
    phase,
    campaigns,
    problem,
    isRefreshing,
  ];
}
