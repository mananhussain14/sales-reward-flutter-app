import '../../../../core/parsing/rpc_row.dart';
import '../../../campaigns/domain/entities/campaign_measurement.dart';
import '../../../campaigns/domain/entities/campaign_reward.dart';
import '../../domain/entities/campaign_earnings_summary.dart';
import '../../domain/entities/campaign_reward_record.dart';
import '../../domain/entities/campaign_target_progress.dart';

/// The canonical UUID shape.
///
/// Used to refuse an id the backend could not have produced, so a value that
/// could never be a cursor — or a receipt reference — is caught before it is
/// sent back or rendered.
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The largest integer this application will accept from a `bigint` column.
///
/// `2^53 - 1`. **Not** an arbitrary limit and not the schema's:
///
/// * on the Dart VM an `int` is 64-bit and a `bigint` fits exactly;
/// * on the web an `int` **is** a double, so any value above `2^53 - 1` is
///   silently rounded to the nearest representable one, and a coin total would
///   be wrong by an amount nobody could see.
///
/// Refusing the value on every platform is what makes the two agree. It costs
/// nothing in practice: `campaign_rewards_uncapped_range` caps a single reward's
/// uncapped amount at `5e12`, three orders of magnitude below this, and a
/// lifetime total would have to pass nine quadrillion coins to reach it.
const int rewardSafeIntegerCeiling = 9007199254740991;

/// `campaign_rewards_uncapped_range` — the largest uncapped amount one reward
/// may record. `1e9` coins per unit × `5000` units.
const int rewardUncappedCeiling = 5000000000000;

/// `campaign_rewards_units_range` — the units one sale may contribute.
const int rewardUnitsCeiling = 5000;

/// `campaign_sale_evaluations_item_count_range` — the receipt lines one
/// evaluation may count.
const int rewardItemCountCeiling = 50;

/// Parses the three Sales Staff earnings contracts.
///
/// ## Strict, for the same reason the campaign parser is
///
/// Every branch below throws rather than substituting a default, and the
/// repository turns that into `RetailerReadProblem.malformed` — never an empty
/// list, never a partially populated row, and never "you are not allowed".
///
/// The difference between this surface and a decorative one is what the values
/// mean. These are **amounts of money a person believes they have earned**.
/// There is no neutral rendering of "we could not read what you were paid": the
/// honest options are the right number or no number, and a wrong number is worse
/// than a failed read.
///
/// ## The whole page, or none of it
///
/// One malformed row fails the read. Skipping bad rows would under-report a
/// seller's own earnings, and a history quietly short by one reward is worse
/// than one that honestly failed to load.
///
/// ## What is rejected
///
/// * a body that is not a list, or a row that is not an object;
/// * a missing, null, blank or non-string required text column;
/// * an id that is not UUID-shaped;
/// * an unrecognised `rule_type` or `performance_scope` token;
/// * a numeric column that is not an integer, that arrived as **text**, or that
///   is outside the bounds the deployed `CHECK` constraints enforce;
/// * any integer above [rewardSafeIntegerCeiling], which cannot be represented
///   without loss on every platform this application runs on;
/// * a non-boolean where the contract declares `boolean`;
/// * a reward whose typed half does not match its rule type — a
///   `PER_UNIT_COINS` row carrying a target tier, or a `TARGET_BONUS` row
///   without one;
/// * a `coins_capped_to` that is not strictly below `coins_uncapped`, or a
///   `reward_coins` above it: both are refused by the table, so a row carrying
///   one is not this shape.
///
/// ## What is tolerated
///
/// * an **empty list** → no rewards yet, or no target campaign. A real answer.
/// * **zero rows from the summary** → handled by the repository, not here: it
///   means the caller is not an authorized earnings reader, which is a different
///   answer from a summary of zeros.
/// * an **unrecognised extra key** → ignored; the contract is additive.
/// * a **null `shop_name`** → null. The contract left-joins the shop.
/// * a **null `latest_reward_at`** → null. No reward has been awarded yet.
abstract final class EarningsParsers {
  // -- Reward history -------------------------------------------------------

  /// `get_my_campaign_rewards(integer, timestamptz, uuid)`.
  static List<CampaignRewardRecord> parseCampaignRewards(Object? raw) {
    return RpcRow.asRows(
      raw,
      'campaign rewards',
    ).map(parseCampaignRewardRow).toList(growable: false);
  }

  /// One reward row of the deployed seventeen-column contract.
  ///
  /// Reads fifteen of them. `campaign_id` and `campaign_version_id` are returned
  /// and deliberately not read: neither addresses anything this application can
  /// open from a reward, and a key that is not read cannot be rendered.
  static CampaignRewardRecord parseCampaignRewardRow(Map<String, Object?> row) {
    final String rewardId = _requiredUuid(
      row['campaign_reward_id'],
      'campaign_reward_id',
    );
    final String receiptSubmissionId = _requiredUuid(
      row['receipt_submission_id'],
      'receipt_submission_id',
    );

    final CampaignRewardRuleType? ruleType = CampaignRewardRuleType.tryFromCode(
      RpcRow.requiredString(row['rule_type'], 'rule_type'),
    );
    if (ruleType == null) {
      throw const RpcFormatException('rule_type is not a known rule');
    }

    final CampaignPerformanceScope? scope =
        CampaignPerformanceScope.tryFromCode(
          RpcRow.requiredString(row['performance_scope'], 'performance_scope'),
        );
    if (scope == null) {
      throw const RpcFormatException(
        'performance_scope is not a known measurement',
      );
    }

    final int qualifyingItemCount = _boundedInt(
      row['qualifying_item_count'],
      'qualifying_item_count',
      min: 0,
      max: rewardItemCountCeiling,
    );
    final int qualifyingUnits = _boundedInt(
      row['qualifying_units'],
      'qualifying_units',
      min: 1,
      max: rewardUnitsCeiling,
    );
    final int coinsUncapped = _boundedInt(
      row['coins_uncapped'],
      'coins_uncapped',
      min: 0,
      max: rewardUncappedCeiling,
    );
    final int? coinsCappedTo = _optionalBoundedInt(
      row['coins_capped_to'],
      'coins_capped_to',
      min: 0,
      max: rewardUncappedCeiling,
    );
    final int rewardCoins = _boundedInt(
      row['reward_coins'],
      'reward_coins',
      min: 0,
      max: rewardUncappedCeiling,
    );
    final int? thresholdUnits = _optionalBoundedInt(
      row['threshold_units'],
      'threshold_units',
      min: 1,
      max: rewardSafeIntegerCeiling,
    );
    final int? configuredRewardCoins = _optionalBoundedInt(
      row['configured_reward_coins'],
      'configured_reward_coins',
      min: 1,
      max: campaignCoinCeiling,
    );

    // `campaign_rewards_tier_paired` and `campaign_rewards_tier_reward_paired`
    // are equivalences, so exactly one of the two shapes can be stored. A row
    // carrying both halves — or neither — describes two rules at once, and
    // there is no sentence that says both.
    switch (ruleType) {
      case CampaignRewardRuleType.perUnitCoins:
        if (thresholdUnits != null || configuredRewardCoins != null) {
          throw const RpcFormatException(
            'a per-unit reward carries a target tier',
          );
        }
      case CampaignRewardRuleType.targetBonus:
        if (thresholdUnits == null || configuredRewardCoins == null) {
          throw const RpcFormatException('a target reward has no tier');
        }
    }

    // `campaign_rewards_capped_range` refuses a `coins_capped_to` that is not
    // strictly below the uncapped amount — a cap that changed nothing is
    // indistinguishable from no cap — and `campaign_rewards_reward_within_uncapped`
    // refuses a reward above it. Both are re-checked because this is where "not
    // the contract this build was written against" has to be caught, and
    // because the screen explains the SHORTFALL between the two numbers.
    if (coinsCappedTo != null && coinsCappedTo >= coinsUncapped) {
      throw const RpcFormatException(
        'coins_capped_to is not below the uncapped amount',
      );
    }
    if (rewardCoins > coinsUncapped) {
      throw const RpcFormatException(
        'reward_coins is above the uncapped amount',
      );
    }

    return CampaignRewardRecord(
      rewardId: rewardId,
      campaignName: RpcRow.requiredString(
        row['campaign_name'],
        'campaign_name',
      ),
      receiptSubmissionId: receiptSubmissionId,
      shopName: RpcRow.optionalString(row['shop_name'], 'shop_name'),
      saleAt: RpcRow.requiredTimestamp(row['sale_at'], 'sale_at'),
      awardedAt: RpcRow.requiredTimestamp(row['awarded_at'], 'awarded_at'),
      ruleType: ruleType,
      performanceScope: scope,
      qualifyingItemCount: qualifyingItemCount,
      qualifyingUnits: qualifyingUnits,
      coinsUncapped: coinsUncapped,
      coinsCappedTo: coinsCappedTo,
      rewardCoins: rewardCoins,
      thresholdUnits: thresholdUnits,
      configuredRewardCoins: configuredRewardCoins,
    );
  }

  // -- Summary --------------------------------------------------------------

  /// `get_my_campaign_earnings_summary()`.
  ///
  /// The contract is set-returning, so PostgREST renders it as an array of zero
  /// or one row. **Zero rows is load-bearing**: it is what an unauthorized
  /// caller receives, and it is emphatically not a summary of zeros. Null is
  /// returned for it and the repository turns that into its own answer.
  ///
  /// More than one row would mean the deployed function is not the one this
  /// build expects — the query aggregates with no `GROUP BY` — so it is refused
  /// rather than silently taking the first.
  static CampaignEarningsSummary? parseEarningsSummary(Object? raw) {
    final List<Map<String, Object?>> rows = RpcRow.asRows(
      raw,
      'campaign earnings summary',
    );
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      throw const RpcFormatException(
        'campaign earnings summary returned more than one row',
      );
    }
    return parseEarningsSummaryRow(rows.single);
  }

  static CampaignEarningsSummary parseEarningsSummaryRow(
    Map<String, Object?> row,
  ) {
    final int total = _boundedInt(
      row['total_reward_coins'],
      'total_reward_coins',
      min: 0,
      max: rewardSafeIntegerCeiling,
    );
    final int currentMonth = _boundedInt(
      row['current_month_reward_coins'],
      'current_month_reward_coins',
      min: 0,
      max: rewardSafeIntegerCeiling,
    );
    // The month figure is the same sum over a subset of the same rows, and
    // every `reward_coins` is non-negative, so it cannot exceed the total. A
    // response where it does is not this shape.
    if (currentMonth > total) {
      throw const RpcFormatException(
        'current_month_reward_coins exceeds total_reward_coins',
      );
    }

    final DateTime monthStart = RpcRow.requiredTimestamp(
      row['current_month_start_utc'],
      'current_month_start_utc',
    );
    final DateTime monthEnd = RpcRow.requiredTimestamp(
      row['current_month_end_utc'],
      'current_month_end_utc',
    );
    if (!monthEnd.isAfter(monthStart)) {
      throw const RpcFormatException(
        'current_month_end_utc is not after current_month_start_utc',
      );
    }

    return CampaignEarningsSummary(
      totalRewardCoins: total,
      currentMonthRewardCoins: currentMonth,
      rewardedSaleCount: _boundedInt(
        row['rewarded_sale_count'],
        'rewarded_sale_count',
        min: 0,
        max: rewardSafeIntegerCeiling,
      ),
      rewardedCampaignCount: _boundedInt(
        row['rewarded_campaign_count'],
        'rewarded_campaign_count',
        min: 0,
        max: rewardSafeIntegerCeiling,
      ),
      latestRewardAt: RpcRow.optionalTimestamp(
        row['latest_reward_at'],
        'latest_reward_at',
      ),
      currentMonthStartUtc: monthStart,
      currentMonthEndUtc: monthEnd,
    );
  }

  // -- Target progress ------------------------------------------------------

  /// `get_my_campaign_target_progress()`.
  static List<CampaignTargetProgress> parseCampaignTargetProgress(Object? raw) {
    return RpcRow.asRows(
      raw,
      'campaign target progress',
    ).map(parseCampaignTargetProgressRow).toList(growable: false);
  }

  /// One progress row.
  ///
  /// Reads seven of the nine columns. `campaign_version_id` is returned and
  /// deliberately not read — see [CampaignTargetProgress]. `target_reached` and
  /// `bonus_awarded_to_me` are read as **booleans** and never recomputed from
  /// the two numbers beside them: the database decides both, and a second
  /// definition on the device would be the one nobody noticed had drifted.
  static CampaignTargetProgress parseCampaignTargetProgressRow(
    Map<String, Object?> row,
  ) {
    final CampaignPerformanceScope? scope =
        CampaignPerformanceScope.tryFromCode(
          RpcRow.requiredString(row['performance_scope'], 'performance_scope'),
        );
    if (scope == null) {
      throw const RpcFormatException(
        'performance_scope is not a known measurement',
      );
    }

    return CampaignTargetProgress(
      campaignId: _requiredUuid(row['campaign_id'], 'campaign_id'),
      campaignName: RpcRow.requiredString(
        row['campaign_name'],
        'campaign_name',
      ),
      performanceScope: scope,
      targetUnits: _boundedInt(
        row['target_units'],
        'target_units',
        min: 1,
        max: rewardSafeIntegerCeiling,
      ),
      configuredRewardCoins: _boundedInt(
        row['configured_reward_coins'],
        'configured_reward_coins',
        min: 1,
        max: campaignCoinCeiling,
      ),
      progressUnits: _boundedInt(
        row['progress_units'],
        'progress_units',
        min: 0,
        max: rewardSafeIntegerCeiling,
      ),
      targetReached: RpcRow.requiredBool(
        row['target_reached'],
        'target_reached',
      ),
      bonusAwardedToMe: RpcRow.requiredBool(
        row['bonus_awarded_to_me'],
        'bonus_awarded_to_me',
      ),
    );
  }

  // -- Readers --------------------------------------------------------------

  /// A `uuid` column that is `NOT NULL` in the contract.
  static String _requiredUuid(Object? raw, String what) {
    final String value = RpcRow.requiredString(raw, what);
    if (!_uuidPattern.hasMatch(value)) {
      throw RpcFormatException('$what is not a uuid');
    }
    return value;
  }

  /// A `bigint` or `integer` column that is `NOT NULL`, inside its documented
  /// bounds.
  static int _boundedInt(
    Object? raw,
    String what, {
    required int min,
    required int max,
  }) {
    final int? value = _optionalBoundedInt(raw, what, min: min, max: max);
    if (value == null) {
      throw RpcFormatException('$what is missing');
    }
    return value;
  }

  /// A nullable `bigint` or `integer` column, inside its documented bounds.
  ///
  /// Accepts an `int`, and a `num` whose value is integral — JSON has one number
  /// type and a transport is entitled to hand back `1.0`. A **string** is
  /// refused: a numeric column arriving as text means the response is not the
  /// shape this build was written against, and `int.parse` on it would launder a
  /// wrong contract into a plausible number.
  ///
  /// A value above [rewardSafeIntegerCeiling] is refused rather than rounded,
  /// on every platform, so a coin total cannot silently lose precision on the
  /// web and be right on a phone.
  static int? _optionalBoundedInt(
    Object? raw,
    String what, {
    required int min,
    required int max,
  }) {
    if (raw == null) {
      return null;
    }

    final int value;
    if (raw is int) {
      value = raw;
    } else if (raw is num) {
      if (!raw.isFinite || raw != raw.roundToDouble()) {
        throw RpcFormatException('$what is not an integer');
      }
      // Checked BEFORE `toInt()`: a double past the safe range has already lost
      // the precision that would make the conversion meaningful, and
      // `toInt()` on it would produce a confident, wrong integer.
      if (raw.abs() > rewardSafeIntegerCeiling) {
        throw RpcFormatException('$what is outside the safe integer range');
      }
      value = raw.toInt();
    } else {
      throw RpcFormatException('$what is not an integer');
    }

    if (value.abs() > rewardSafeIntegerCeiling) {
      throw RpcFormatException('$what is outside the safe integer range');
    }
    if (value < min || value > max) {
      throw RpcFormatException('$what is outside its documented range');
    }
    return value;
  }
}
