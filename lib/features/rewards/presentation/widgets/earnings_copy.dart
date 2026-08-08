import '../../../../core/utils/date_format.dart';
import '../../../campaigns/domain/entities/campaign_measurement.dart';
import '../../../campaigns/domain/entities/campaign_reward.dart';
import '../../../campaigns/presentation/shared/campaign_copy.dart';
import '../../domain/entities/campaign_reward_record.dart';
import '../../domain/entities/campaign_target_progress.dart';

/// Every string the earnings and target-progress screens render.
///
/// Centralised for the same reason `CampaignCopy` is: **no copy on these screens
/// may be derived from a backend response.** Each string is a fixed literal or a
/// function of parsed, validated values, so a Postgres message, a SQLSTATE, a
/// stack trace, a UUID or an internal enum token cannot reach a screen through
/// any of them.
///
/// No `.code` is ever interpolated. A reader is never shown `TARGET_BONUS`,
/// `RETAILER_TEAM` or `INDIVIDUAL_STAFF`.
///
/// ## Nothing here is a balance
///
/// Not one string in this file calls a number a wallet balance, an available
/// balance, redeemable coins, paid coins, withdrawable coins, a payout or a
/// credit — because none of those exists. [walletNotice] says so outright on the
/// screen itself, so the absence reads as "not built yet" rather than as a
/// missing feature the reader should go looking for.
abstract final class EarningsCopy {
  // -- Screen chrome --------------------------------------------------------

  /// The page title. Also the accessible name of the navigation destination,
  /// whose visible label is shortened to fit a bottom bar.
  static const String title = 'My campaign earnings';

  /// The short form, for the bottom navigation bar.
  static const String navLabel = 'Earnings';

  static const String description =
      'The campaign rewards you have earned, newest first.';

  static const String loading = 'Loading your earnings…';
  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';

  // -- The one notice that qualifies every number on the screen -------------

  /// Required wording, rendered once, above the totals.
  ///
  /// It states two facts a reader would otherwise get wrong: these coins are
  /// **earned**, and there is nowhere to spend them yet. No ledger, wallet,
  /// redemption or payout object exists in the deployed schema, and implying one
  /// would be inventing money.
  static const String walletNotice =
      'These are campaign rewards earned. Wallet, payout and redemption '
      'features are not available yet.';

  // -- Summary --------------------------------------------------------------

  static const String summarySectionTitle = 'Your totals';

  static const String totalCoinsLabel = 'Total campaign coins earned';
  static const String currentMonthLabel = 'Coins earned this month';
  static const String rewardedSalesLabel = 'Rewarded sales';
  static const String rewardedCampaignsLabel = 'Rewarded campaigns';
  static const String latestRewardLabel = 'Latest reward date';

  static const String totalCoinsHint =
      'Every campaign reward awarded to you, added up.';
  static const String rewardedSalesHint =
      'Sales that produced at least one campaign reward.';
  static const String rewardedCampaignsHint =
      'Campaigns that have rewarded you at least once.';

  /// Names the exact window the backend measured, so "this month" is a stated
  /// period rather than an assumption about the device's clock.
  ///
  /// The end bound is exclusive in the contract, so the last day shown is the
  /// day before it.
  static String currentMonthHint(DateTime startUtc, DateTime endUtc) {
    final DateTime lastDay = endUtc.subtract(const Duration(days: 1));
    return 'Awarded between ${formatDayDate(startUtc)} and '
        '${formatDayDate(lastDay)}, measured in UTC.';
  }

  /// No reward has ever been awarded. Said in words rather than left blank or
  /// filled with a dash.
  static const String latestRewardNever = 'No rewards yet';

  static String latestRewardValue(DateTime? awardedAt) =>
      awardedAt == null ? latestRewardNever : formatDayDate(awardedAt);

  // -- Reward history -------------------------------------------------------

  static const String historySectionTitle = 'Reward history';

  static const String historyEmptyTitle = 'No campaign rewards yet';

  /// Required wording.
  static const String historyEmptyBody =
      'You have not earned any campaign rewards yet.';

  /// What actually has to happen, so the empty state is encouraging without
  /// promising anything.
  ///
  /// It names verification and evaluation as the two things that decide, and
  /// says outright that not every receipt qualifies — because eligibility
  /// depends on the product, the campaign and the sale, and none of those is
  /// settled by submitting a photograph. Telling a seller their next receipt
  /// will earn them coins would be the one motivating sentence on this screen
  /// that is not true.
  static const String historyEmptyHint =
      'Rewards appear here after an eligible sale is verified and the campaign '
      'is evaluated. Not every invoice / receipt qualifies.';

  /// The action offered from the empty state: the ordinary submission flow,
  /// and nothing new.
  static const String historyEmptyAction = 'Add invoice / receipt';

  /// Required wording for the pagination control.
  static const String loadOlder = 'Load older rewards';
  static const String loadingOlder = 'Loading older rewards…';

  /// Shown when the last page came back short — there is nothing behind it.
  static const String historyEnd = 'That is your whole reward history.';

  /// A page failed while earlier rewards are still on screen. They stay.
  static const String olderFailedTitle = 'Older rewards did not load';
  static const String olderFailedBody =
      'The rewards already listed are unchanged. Try loading older rewards '
      'again.';

  /// The summary failed while the history loaded, or the other way round.
  /// Neither erases the other.
  static const String summaryFailedTitle = 'Your totals did not load';
  static const String summaryFailedBody =
      'The rewards listed below are unaffected. Refresh to try the totals '
      'again.';

  // -- One reward -----------------------------------------------------------

  static const String saleDateLabel = 'Sale date';
  static const String awardedAtLabel = 'Awarded';
  static const String receiptLabel = 'Invoice / receipt';
  static const String shopLabel = 'Shop';
  static const String qualifyingProductsLabel = 'Qualifying products';
  static const String qualifyingUnitsLabel = 'Qualifying units';
  static const String uncappedLabel = 'Before the campaign maximum';
  static const String finalRewardLabel = 'Coins earned';
  static const String targetLabel = 'Target';
  static const String configuredBonusLabel = 'Configured bonus';

  /// The badge on a reward, naming which rule paid it. Never the backend token.
  static String ruleLabel(CampaignRewardRuleType type) => switch (type) {
    CampaignRewardRuleType.perUnitCoins => 'Per unit',
    CampaignRewardRuleType.targetBonus => 'Target bonus',
  };

  /// Whether the campaign measured this seller or the whole team, on a reward.
  static String rewardScopeLabel(CampaignPerformanceScope scope) =>
      switch (scope) {
        CampaignPerformanceScope.individualStaff => 'Individual target',
        CampaignPerformanceScope.retailerTeam => 'Retailer team target',
      };

  /// Required wording for a partially capped reward.
  ///
  /// Both stored amounts are shown beside it; this sentence only names the
  /// reason the second is lower than the first. Nothing is recomputed — the
  /// database recorded both numbers and the difference between them.
  static const String reducedByCap = 'Reduced by the campaign maximum.';

  /// `n` qualifying units, singular-aware.
  static String qualifyingUnitsValue(int units) =>
      '${formatCampaignNumber(units)} ${units == 1 ? 'unit' : 'units'}';

  /// `n` qualifying products, singular-aware.
  static String qualifyingProductsValue(int count) =>
      '${formatCampaignNumber(count)} ${count == 1 ? 'product' : 'products'}';

  /// `2,500 coins`; `1 coin`. The unit is appended exactly once, here, so no
  /// caller can produce "coins coins".
  static String coins(int amount) =>
      '${formatCampaignNumber(amount)} ${amount == 1 ? 'coin' : 'coins'}';

  /// `25 units`; `1 unit`. Appended exactly once, for the same reason.
  static String units(int amount) =>
      '${formatCampaignNumber(amount)} ${amount == 1 ? 'unit' : 'units'}';

  /// The shortened receipt reference, labelled.
  ///
  /// A **reference**, never a link: there is no authorized Sales Staff route
  /// that opens a receipt from a reward, and adding one would be a different
  /// feature. The whole submission id is never rendered.
  static String receiptReferenceValue(CampaignRewardRecord reward) =>
      reward.receiptReference;

  /// One reward, as a single screen-reader utterance in visual order.
  static String rewardSemanticLabel(CampaignRewardRecord reward) {
    final StringBuffer buffer = StringBuffer(reward.campaignName)
      ..write('. ')
      ..write(ruleLabel(reward.ruleType))
      ..write('. ')
      ..write(finalRewardLabel)
      ..write(': ')
      ..write(coins(reward.rewardCoins))
      ..write('. ');

    if (reward.wasReducedByCap) {
      buffer
        ..write(uncappedLabel)
        ..write(': ')
        ..write(coins(reward.coinsUncapped))
        ..write('. ')
        ..write(reducedByCap)
        ..write(' ');
    }

    buffer
      ..write(saleDateLabel)
      ..write(': ')
      ..write(formatDayDate(reward.saleAt))
      ..write('. ')
      ..write(receiptLabel)
      ..write(': ')
      ..write(reward.receiptReference)
      ..write('.');
    return buffer.toString();
  }

  // -- Target progress ------------------------------------------------------

  static const String progressSectionTitle = 'Target progress';

  /// Required wording. `INDIVIDUAL_STAFF` — the units are this seller's own.
  static const String personalProgressLabel = 'Your progress';

  /// Required wording. `RETAILER_TEAM` — the units are the whole Retailer's.
  static const String teamProgressLabel = 'Team progress';

  static String progressLabel(CampaignPerformanceScope scope) =>
      switch (scope) {
        CampaignPerformanceScope.individualStaff => personalProgressLabel,
        CampaignPerformanceScope.retailerTeam => teamProgressLabel,
      };

  /// Says whose sales the number above counts, so a team figure is never read
  /// as a personal one.
  static String progressExplanation(CampaignPerformanceScope scope) =>
      switch (scope) {
        CampaignPerformanceScope.individualStaff =>
          'This counts your own eligible sales towards the campaign target.',
        CampaignPerformanceScope.retailerTeam =>
          'Team progress includes eligible sales by the whole Retailer team, '
              'not only your own.',
      };

  /// `12 of 25 units`. Both numbers are stored values; nothing is derived.
  ///
  /// **Never rounded to fit the ring.** A seller who has sold 9 units against a
  /// target of 8 reads `9 of 8 units`, because the numerator is a fact and the
  /// indicator beside it is only a drawing.
  static String progressValue(CampaignTargetProgress progress) =>
      '${formatCampaignNumber(progress.progressUnits)} of '
      '${units(progress.targetUnits)}';

  /// `67%` — the clamped display ratio as whole percent.
  ///
  /// Shown **beside** [progressValue] and never instead of it. A percentage on
  /// its own hides the denominator, and the denominator is the target.
  static String progressPercentValue(CampaignTargetProgress progress) =>
      '${progress.completionPercent}%';

  /// The spoken form, so a reader hears "67 percent" rather than "67 modulo".
  static String progressPercentSpoken(CampaignTargetProgress progress) =>
      '${progress.completionPercent} percent';

  /// How far along, as a sentence. Only meaningful before the target is met.
  static String progressPercentSentence(CampaignTargetProgress progress) =>
      switch (progress.performanceScope) {
        CampaignPerformanceScope.individualStaff =>
          'You are ${progressPercentValue(progress)} of the way there.',
        CampaignPerformanceScope.retailerTeam =>
          'Your Retailer is ${progressPercentValue(progress)} of the way '
              'there.',
      };

  static const String targetNotReached = 'Target not reached yet';
  static const String targetReached = 'Target reached';

  /// The encouraging line, and the one place on the indicator where the tone
  /// changes with the state.
  ///
  /// Every branch is decided by the two stored booleans and a subtraction of
  /// two stored unit counts. Nothing here promises a reward, predicts one, or
  /// tells a reader they were paid when the bonus went elsewhere.
  static String progressHeadline(CampaignTargetProgress progress) {
    if (!progress.targetReached) {
      final int remaining = progress.unitsRemaining;
      if (remaining == 0) {
        // Counted up to the target, but the backend has not recorded it as
        // reached. Said plainly rather than guessed at: evaluation is the
        // database's, and it may simply not have run yet.
        return 'This target has not been recorded as reached yet.';
      }
      final String more =
          '${formatCampaignNumber(remaining)} more eligible '
          '${remaining == 1 ? 'unit' : 'units'}';
      return switch (progress.performanceScope) {
        CampaignPerformanceScope.individualStaff =>
          '$more to reach your target.',
        CampaignPerformanceScope.retailerTeam =>
          '$more to reach the team target.',
      };
    }

    if (progress.bonusAwardedToMe) {
      return 'Target reached — reward recorded.';
    }
    if (progress.performanceScope.isTeam) {
      return 'The team has reached the target.';
    }
    return 'This target has been reached.';
  }

  /// What the state line says, from the two stored booleans and nothing else.
  static String progressStatus(CampaignTargetProgress progress) {
    if (!progress.targetReached) {
      return targetNotReached;
    }
    return targetReached;
  }

  /// The bonus line, which is the one sentence on this screen that makes a
  /// claim about money.
  ///
  /// Four cases, all decided by two stored booleans:
  ///
  /// * not reached → what reaching it would pay, stated as the configured
  ///   offer;
  /// * reached and the bonus is this seller's → said plainly;
  /// * reached by the **team** and the bonus went to somebody else → the exact
  ///   required sentence, which never says the reader earned it;
  /// * reached under an individual target with no bonus recorded for the reader
  ///   → the award is stated as not recorded, without guessing why.
  static String bonusSentence(CampaignTargetProgress progress) {
    final String bonus = coins(progress.configuredRewardCoins);

    if (!progress.targetReached) {
      return switch (progress.performanceScope) {
        CampaignPerformanceScope.individualStaff =>
          'Reaching this target qualifies you for the configured $bonus '
              'reward.',
        CampaignPerformanceScope.retailerTeam =>
          'When your Retailer reaches this target, contributing Sales Staff '
              'share the configured $bonus reward according to the campaign '
              'rules.',
      };
    }

    if (progress.bonusAwardedToMe) {
      return 'You were awarded the target bonus for this campaign. The exact '
          'amount is in your reward history.';
    }

    if (progress.performanceScope.isTeam) {
      // Required wording, verbatim. It must never read as though the current
      // user was paid: `bonus_awarded_to_me` is reconstructed from the
      // existence of a TARGET_BONUS reward whose beneficiary is the caller, and
      // it is false here.
      return teamBonusAwardedElsewhere;
    }

    return 'This target has been reached. No target bonus is recorded for you '
        'on this campaign.';
  }

  /// Required wording, exactly as specified.
  static const String teamBonusAwardedElsewhere =
      'Your team reached this target. The bonus for crossing it was awarded to '
      'another team member.';

  /// The screen-reader label for a progress indicator.
  ///
  /// Carries the label, the current value, the target, the percentage and the
  /// state, so the ring is never the only channel — a circular indicator on its
  /// own announces a bare percentage, which says nothing about whose units they
  /// are or how many are left.
  ///
  /// The numerator and denominator come **first** and the percentage second:
  /// "12 of 25 units, 48 percent" is the order the visible block reads in, and
  /// the percentage is the derived value of the two.
  static String progressSemanticLabel(CampaignTargetProgress progress) {
    return '${progressLabel(progress.performanceScope)}: '
        '${progressValue(progress)}, ${progressPercentSpoken(progress)}. '
        '${progressStatus(progress)}. ${progressHeadline(progress)} '
        '${bonusSentence(progress)}';
  }
}
