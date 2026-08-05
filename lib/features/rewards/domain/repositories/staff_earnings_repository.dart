import '../../../../core/errors/retailer_read_problem.dart';
import '../entities/campaign_earnings_summary.dart';
import '../entities/campaign_reward_record.dart';
import '../entities/campaign_target_progress.dart';

/// How many rewards one page holds.
///
/// Fixed, and **not** a user-controlled value: there is no page-size control on
/// any screen and nothing reads a preference. The deployed contract clamps
/// `p_limit` to `1..100` and defaults it to 50, so 20 sits comfortably inside
/// the ceiling and is what a phone can render without a long scroll.
const int campaignRewardPageSize = 20;

/// The outcome of the earnings **summary** read.
sealed class StaffEarningsSummaryResult {
  const StaffEarningsSummaryResult();
}

/// The one row. Possibly all zeros, which is a real answer.
final class StaffEarningsSummaryLoaded extends StaffEarningsSummaryResult {
  const StaffEarningsSummaryLoaded(this.summary);

  final CampaignEarningsSummary summary;
}

/// **Zero rows.**
///
/// The contract returns early with no row when
/// `sales_staff_earnings_profile()` is null — which collapses signed out, no
/// profile, a suspended profile or membership, an inactive organization, a
/// Vendor organization, a role without `STAFF_EARNINGS_VIEW`, zero qualifying
/// Retailers **and** more than one, all into the same silence.
///
/// It is deliberately distinct from [StaffEarningsSummaryLoaded] with zeros: a
/// seller who has earned nothing gets a row of zeros, and a caller who may not
/// read earnings at all gets no row. Rendering the second as the first would
/// tell somebody they had earned zero coins when the truth is that this surface
/// is not theirs.
final class StaffEarningsSummaryUnavailable extends StaffEarningsSummaryResult {
  const StaffEarningsSummaryUnavailable();
}

/// The read did not produce an answer.
final class StaffEarningsSummaryFailed extends StaffEarningsSummaryResult {
  const StaffEarningsSummaryFailed(this.problem);

  final RetailerReadProblem problem;
}

/// The outcome of one **page** of reward history.
sealed class StaffCampaignRewardsResult {
  const StaffCampaignRewardsResult();
}

/// The page, already parsed and in the backend's own order.
final class StaffCampaignRewardsLoaded extends StaffCampaignRewardsResult {
  const StaffCampaignRewardsLoaded({
    required this.rewards,
    required this.hasMore,
  });

  /// Newest first, exactly as `order by w.awarded_at desc, w.id desc` returned
  /// them. Nothing re-sorts them.
  final List<CampaignRewardRecord> rewards;

  /// Whether another page **may** exist.
  ///
  /// True when the page came back full. That is a possibility rather than a
  /// promise — a history whose length is an exact multiple of the page size
  /// yields one final request that returns nothing — and it is the only honest
  /// answer a keyset read can give without a second round trip. The screen
  /// handles the empty last page by hiding the button, so the cost of the
  /// imprecision is one request and no wrong claim.
  final bool hasMore;
}

/// The page did not load. Never an empty page: "we could not read your rewards"
/// and "you have none" are opposite claims.
final class StaffCampaignRewardsFailed extends StaffCampaignRewardsResult {
  const StaffCampaignRewardsFailed(this.problem);

  final RetailerReadProblem problem;
}

/// The outcome of the **target progress** read.
sealed class StaffCampaignTargetProgressResult {
  const StaffCampaignTargetProgressResult();
}

/// The progress rows. Empty is a real answer — the seller's Retailer has no
/// `TARGET_BONUS` campaign running or starting soon.
final class StaffCampaignTargetProgressLoaded
    extends StaffCampaignTargetProgressResult {
  const StaffCampaignTargetProgressLoaded(this.progress);

  final List<CampaignTargetProgress> progress;

  /// The rows keyed by campaign, ready to join against the campaign list.
  ///
  /// The contract guarantees at most one row per campaign — it joins
  /// `campaign_rules ... and r.sequence = 1` and
  /// `campaign_rule_tiers ... and t.tier_number = 1` — so a later row for the
  /// same id would mean the deployed function is not the one this build
  /// expects. The map keeps the first, which is the one the backend ordered
  /// first.
  Map<String, CampaignTargetProgress> get byCampaignId {
    final Map<String, CampaignTargetProgress> byId =
        <String, CampaignTargetProgress>{};
    for (final CampaignTargetProgress row in progress) {
      byId.putIfAbsent(row.campaignId, () => row);
    }
    return byId;
  }
}

/// The read did not produce an answer.
final class StaffCampaignTargetProgressFailed
    extends StaffCampaignTargetProgressResult {
  const StaffCampaignTargetProgressFailed(this.problem);

  final RetailerReadProblem problem;
}

/// A Sales Staff member's read-only view of what they have **earned**.
///
/// ## A separate interface from the campaign one, mirroring two permissions
///
/// `STAFF_EARNINGS_VIEW` is deliberately separate from `STAFF_CAMPAIGNS_VIEW`:
/// *"Seeing which campaigns are running is a different question from seeing what
/// you personally earned, and a future role that should see one without the
/// other must be expressible without a code change."* Two interfaces here mirror
/// two permissions there, so widening either cannot widen the other by an edit
/// that type-checks.
///
/// ## The signatures are the security property
///
/// Not one method takes a profile, an auth user id, a Retailer, a Vendor, an
/// organization, a shop, a role or a permission. The only values transmitted
/// are a **page size** and a **cursor into the caller's own history**, and the
/// cursor is two values the previous page already returned.
///
/// The backend resolves who is asking through `sales_staff_earnings_profile()`,
/// which *"takes NO ARGUMENTS. There is no profile, Retailer, Vendor, shop or
/// permission parameter for a caller to supply, so nothing about the identity
/// can be nominated."*
///
/// ## Read-only, and no wallet
///
/// There is no redeem, withdraw, transfer, claim, payout or adjustment method
/// here, and none is disabled: no such contract exists in the deployed schema,
/// and no ledger or balance object exists for one to act on.
abstract interface class StaffEarningsRepository {
  /// `public.get_my_campaign_rewards(p_limit, p_before_awarded_at,
  /// p_before_reward_id)`.
  ///
  /// The first page passes **null** for both cursor values. An older page passes
  /// both, taken from the last row already shown.
  ///
  /// The two cursor arguments are all-or-nothing: an implementation that
  /// received one without the other must send neither, because the contract's
  /// own guard would otherwise return the first page again and the screen would
  /// append rows it is already showing.
  Future<StaffCampaignRewardsResult> getMyCampaignRewards({
    required int limit,
    DateTime? beforeAwardedAt,
    String? beforeRewardId,
  });

  /// `public.get_my_campaign_earnings_summary()` — zero arguments.
  Future<StaffEarningsSummaryResult> getMyCampaignEarningsSummary();

  /// `public.get_my_campaign_target_progress()` — zero arguments.
  ///
  /// Returns a row only for `TARGET_BONUS` campaigns the caller can already see,
  /// under the same targeting, published-version join and `ACTIVE`/`SCHEDULED`
  /// filter as `list_my_staff_campaigns()`. This client restates none of that.
  Future<StaffCampaignTargetProgressResult> getMyCampaignTargetProgress();
}
