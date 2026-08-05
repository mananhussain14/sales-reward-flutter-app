part of 'campaign_target_progress_cubit.dart';

/// Where the target-progress read has reached.
enum CampaignTargetProgressPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// Progress is available — possibly for zero campaigns, which is a real
  /// answer.
  ready,

  /// The read did not produce an answer.
  failed,
}

/// The target progress, keyed by campaign, and how it got there.
///
/// Immutable, and holds **no raw Supabase map** — every value is a parsed
/// [CampaignTargetProgress].
final class CampaignTargetProgressState extends Equatable {
  const CampaignTargetProgressState({
    this.phase = CampaignTargetProgressPhase.initial,
    this.byCampaignId,
    this.problem,
    this.isRefreshing = false,
  });

  final CampaignTargetProgressPhase phase;

  /// The progress rows by campaign id, or null when none has been read.
  ///
  /// Null is **not** an empty map and is never rendered as one. "We could not
  /// read your progress" and "no campaign has a target" are opposite claims —
  /// the second draws no indicator because there is nothing to draw, the first
  /// says so.
  final Map<String, CampaignTargetProgress>? byCampaignId;

  /// Why the read failed. A discriminant; never backend text.
  final RetailerReadProblem? problem;

  final bool isRefreshing;

  /// The progress for one campaign, or null when that campaign has no target —
  /// or when nothing has been read.
  ///
  /// **Joined on the campaign id and never on the name.** Two campaigns may
  /// share a name; only the id is unique, and it is the key both contracts
  /// return.
  CampaignTargetProgress? forCampaign(String campaignId) =>
      byCampaignId?[campaignId];

  /// Nothing was ever read and the read failed.
  ///
  /// What the campaign list uses to decide whether to say that progress is
  /// missing. It never stops the list rendering: the campaigns came from a
  /// different contract behind a different cubit, and they are still true.
  bool get hasFailedOutright =>
      phase == CampaignTargetProgressPhase.failed && byCampaignId == null;

  CampaignTargetProgressState copyWith({
    CampaignTargetProgressPhase? phase,
    Map<String, CampaignTargetProgress>? byCampaignId,
    RetailerReadProblem? problem,
    bool? isRefreshing,
    bool clearProblem = false,
  }) {
    return CampaignTargetProgressState(
      phase: phase ?? this.phase,
      byCampaignId: byCampaignId ?? this.byCampaignId,
      // Explicit, because `copyWith(problem: null)` cannot be told from "leave
      // it alone" in Dart.
      problem: clearProblem ? null : (problem ?? this.problem),
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    byCampaignId,
    problem,
    isRefreshing,
  ];
}
