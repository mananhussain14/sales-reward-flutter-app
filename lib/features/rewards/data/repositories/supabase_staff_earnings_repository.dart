import '../../../../core/errors/retailer_read_problem.dart';
import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/campaign_earnings_summary.dart';
import '../../domain/entities/campaign_reward_record.dart';
import '../../domain/entities/campaign_target_progress.dart';
import '../../domain/repositories/staff_earnings_repository.dart';
import '../datasources/staff_earnings_rpc_data_source.dart';
import '../models/earnings_parsers.dart';

/// The real [StaffEarningsRepository].
///
/// Structurally the twin of `SupabaseStaffCampaignRepository` — call, parse,
/// classify — over three **different** RPCs on a **different** permission.
///
/// ## It reproduces no authorization logic
///
/// No profile id, no Retailer id, no shop, no role, no permission check, and no
/// inspection of the signed-in user. The backend resolves the caller through
/// `sales_staff_earnings_profile()` on every one of the three calls, and that
/// helper takes no arguments — so there is nothing this class could supply even
/// if it wanted to.
///
/// ## It computes no reward
///
/// Nothing here multiplies a rate by units, applies a cap, decides whether a
/// target was reached or decides who a bonus belongs to. Every such value is a
/// column the deployed contract already returned, and the only arithmetic in the
/// whole feature is a subtraction of two stored amounts used to *describe* a
/// difference on screen.
///
/// ## No error text ever escapes
///
/// A thrown read is classified into a [RetailerReadProblem] by
/// [classifyRetailerReadError], which discriminates on **type and SQLSTATE
/// only** and never reads a message. A Postgres message names tables, columns,
/// functions and policies; none of them reaches this application, let alone a
/// screen.
final class SupabaseStaffEarningsRepository implements StaffEarningsRepository {
  const SupabaseStaffEarningsRepository({
    required StaffEarningsRpcDataSource rpc,
    Duration timeout = retailerReadTimeout,
  }) : _rpc = rpc,
       _timeout = timeout;

  final StaffEarningsRpcDataSource _rpc;
  final Duration _timeout;

  @override
  Future<StaffCampaignRewardsResult> getMyCampaignRewards({
    required int limit,
    DateTime? beforeAwardedAt,
    String? beforeRewardId,
  }) async {
    // The all-or-nothing cursor, enforced before the request is built. The
    // deployed guard would answer a half cursor with the FIRST page, which a
    // screen appending it would render as duplicated rows — so half a cursor is
    // reset to none rather than sent.
    final bool hasWholeCursor =
        beforeAwardedAt != null && beforeRewardId != null;

    final Object? raw;
    try {
      raw = await _rpc
          .fetchRewards(
            limit: limit,
            beforeAwardedAt: hasWholeCursor ? beforeAwardedAt : null,
            beforeRewardId: hasWholeCursor ? beforeRewardId : null,
          )
          .timeout(_timeout);
    } on Object catch (error) {
      return StaffCampaignRewardsFailed(classifyRetailerReadError(error));
    }

    try {
      final List<CampaignRewardRecord> rewards =
          EarningsParsers.parseCampaignRewards(raw);
      return StaffCampaignRewardsLoaded(
        rewards: rewards,
        // A full page MAY have another behind it. The contract clamps `p_limit`
        // to at most 100, so a page longer than what was asked for would mean
        // the deployed function is not the one this build expects; `>=` rather
        // than `==` keeps that case from reading as "no more".
        hasMore: rewards.length >= limit,
      );
    } on RpcFormatException {
      return const StaffCampaignRewardsFailed(RetailerReadProblem.malformed);
    }
  }

  @override
  Future<StaffEarningsSummaryResult> getMyCampaignEarningsSummary() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchSummary().timeout(_timeout);
    } on Object catch (error) {
      return StaffEarningsSummaryFailed(classifyRetailerReadError(error));
    }

    final CampaignEarningsSummary? summary;
    try {
      summary = EarningsParsers.parseEarningsSummary(raw);
    } on RpcFormatException {
      return const StaffEarningsSummaryFailed(RetailerReadProblem.malformed);
    }

    if (summary == null) {
      // Zero rows. The caller is not an active Sales Staff member of exactly
      // one active Retailer holding STAFF_EARNINGS_VIEW. Deliberately NOT
      // degraded to a summary of zeros: "you have earned nothing" and "this
      // surface is not yours" are different statements, and only one of them is
      // true here.
      return const StaffEarningsSummaryUnavailable();
    }

    return StaffEarningsSummaryLoaded(summary);
  }

  @override
  Future<StaffCampaignTargetProgressResult>
  getMyCampaignTargetProgress() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchTargetProgress().timeout(_timeout);
    } on Object catch (error) {
      return StaffCampaignTargetProgressFailed(
        classifyRetailerReadError(error),
      );
    }

    try {
      final List<CampaignTargetProgress> progress =
          EarningsParsers.parseCampaignTargetProgress(raw);
      return StaffCampaignTargetProgressLoaded(progress);
    } on RpcFormatException {
      return const StaffCampaignTargetProgressFailed(
        RetailerReadProblem.malformed,
      );
    }
  }
}
