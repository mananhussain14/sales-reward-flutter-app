import 'package:supabase_flutter/supabase_flutter.dart';

/// The Sales Staff reward-history RPC, named exactly once in the application.
const String staffCampaignRewardsRpc = 'get_my_campaign_rewards';

/// The Sales Staff earnings-summary RPC, named exactly once.
const String staffEarningsSummaryRpc = 'get_my_campaign_earnings_summary';

/// The Sales Staff target-progress RPC, named exactly once.
const String staffCampaignTargetProgressRpc = 'get_my_campaign_target_progress';

/// The page-size parameter of [staffCampaignRewardsRpc].
const String rewardLimitParam = 'p_limit';

/// The `awarded_at` half of the keyset cursor.
const String rewardBeforeAwardedAtParam = 'p_before_awarded_at';

/// The `campaign_reward_id` half of the keyset cursor.
const String rewardBeforeRewardIdParam = 'p_before_reward_id';

/// Invokes one page of `get_my_campaign_rewards()`.
///
/// ## Three arguments, and not one of them names a person
///
/// A page size and two cursor values the previous page returned. There is no
/// **profile**, **beneficiary**, **Retailer**, **Vendor**, **shop**,
/// **organization**, **campaign** or **date-range** parameter, because the
/// deployed function declares none: it filters on
/// `beneficiary_profile_id = sales_staff_earnings_profile()`, and that helper
/// takes no arguments at all.
///
/// There is no **offset** parameter either. The contract is keyset-paginated on
/// `(awarded_at, campaign_reward_id)` precisely so that a reward arriving while
/// a seller scrolls cannot make a later page repeat or skip a row.
typedef StaffCampaignRewardsInvoker =
    Future<Object?> Function({
      required int limit,
      DateTime? beforeAwardedAt,
      String? beforeRewardId,
    });

/// Invokes one of the two zero-argument earnings reads.
///
/// The typedef takes nothing because both functions take nothing. Nothing about
/// the identity can be nominated, and there is no parameter through which a
/// seller could try.
typedef StaffEarningsInvoker = Future<Object?> Function();

/// The production reward-history invoker.
///
/// ## The cursor is sent whole or not at all
///
/// The deployed predicate is guarded by
/// `p_before_awarded_at is null or p_before_reward_id is null or (...)`, so a
/// request carrying one half of the cursor returns the **first** page — which a
/// screen appending it would render as duplicated rows. Passing one without the
/// other is therefore normalised to passing neither, here, at the one place the
/// map is built.
///
/// Both keys are always present in the payload, with an explicit `null` on the
/// first page, so the wire shape does not change between the first request and
/// the rest.
StaffCampaignRewardsInvoker supabaseStaffCampaignRewardsInvoker(
  SupabaseClient client,
) {
  return ({
    required int limit,
    DateTime? beforeAwardedAt,
    String? beforeRewardId,
  }) {
    final bool hasWholeCursor =
        beforeAwardedAt != null && beforeRewardId != null;
    return client.rpc<Object?>(
      staffCampaignRewardsRpc,
      params: <String, Object?>{
        rewardLimitParam: limit,
        // Serialised as UTC, so the value the backend compares is the same
        // instant the previous page returned regardless of the device's zone.
        rewardBeforeAwardedAtParam: hasWholeCursor
            ? beforeAwardedAt.toUtc().toIso8601String()
            : null,
        rewardBeforeRewardIdParam: hasWholeCursor ? beforeRewardId : null,
      },
    );
  };
}

/// The production summary invoker. **No `params` map is passed, not even an
/// empty one.**
StaffEarningsInvoker supabaseStaffEarningsSummaryInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(staffEarningsSummaryRpc);
}

/// The production target-progress invoker. Zero arguments, like the summary.
StaffEarningsInvoker supabaseStaffCampaignTargetProgressInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(staffCampaignTargetProgressRpc);
}

/// The three Sales Staff earnings reads.
///
/// A **separate** data source from the campaign one, naming three different
/// functions on a different permission — `STAFF_EARNINGS_VIEW` rather than
/// `STAFF_CAMPAIGNS_VIEW`. The two share nothing, so widening either cannot
/// widen the other.
///
/// **No table is ever read here, and no write exists.** In particular nothing in
/// this file names `campaign_rewards`, `campaign_subject_accumulators`,
/// `campaign_sale_evaluations`, `campaign_sale_item_qualifications`,
/// `verified_sales` or any organization membership table: every one of them is
/// default-deny for the browser roles, RPC is the only way in, and the
/// accumulator in particular *"must never be read as proof that somebody was
/// paid"*.
///
/// **No service-role client.** All three functions derive their authority from
/// `auth.uid()`, so a service-role connection has no identity for them to
/// resolve and could only ever be refused.
final class StaffEarningsRpcDataSource {
  const StaffEarningsRpcDataSource({
    required StaffCampaignRewardsInvoker rewards,
    required StaffEarningsInvoker summary,
    required StaffEarningsInvoker targetProgress,
  }) : _rewards = rewards,
       _summary = summary,
       _targetProgress = targetProgress;

  /// Builds the data source against a live, **authenticated** client.
  factory StaffEarningsRpcDataSource.forClient(SupabaseClient client) {
    return StaffEarningsRpcDataSource(
      rewards: supabaseStaffCampaignRewardsInvoker(client),
      summary: supabaseStaffEarningsSummaryInvoker(client),
      targetProgress: supabaseStaffCampaignTargetProgressInvoker(client),
    );
  }

  final StaffCampaignRewardsInvoker _rewards;
  final StaffEarningsInvoker _summary;
  final StaffEarningsInvoker _targetProgress;

  /// One page of the caller's own reward history.
  Future<Object?> fetchRewards({
    required int limit,
    DateTime? beforeAwardedAt,
    String? beforeRewardId,
  }) {
    return _rewards(
      limit: limit,
      beforeAwardedAt: beforeAwardedAt,
      beforeRewardId: beforeRewardId,
    );
  }

  /// The caller's own earnings totals.
  Future<Object?> fetchSummary() => _summary();

  /// The caller's progress towards each visible target campaign.
  Future<Object?> fetchTargetProgress() => _targetProgress();
}
