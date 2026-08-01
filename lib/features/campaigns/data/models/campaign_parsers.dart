import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/campaign_lifecycle_state.dart';
import '../../domain/entities/campaign_measurement.dart';
import '../../domain/entities/campaign_offer.dart';
import '../../domain/entities/campaign_product.dart';
import '../../domain/entities/campaign_product_eligibility.dart';
import '../../domain/entities/campaign_reward.dart';
import '../../domain/entities/campaign_schedule.dart';
import '../../domain/entities/campaign_stacking_mode.dart';
import '../../domain/entities/retailer_campaign.dart';
import '../../domain/entities/staff_campaign.dart';

/// The canonical UUID shape.
///
/// Used to refuse a `campaign_id` the backend could not have produced, so a
/// value that could never address anything is caught before it is rendered.
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Whether [raw] is shaped like a campaign id.
///
/// Shared with the repositories, which refuse a malformed id **before** putting
/// it into a `uuid` RPC parameter — so a mistyped deep link produces this
/// feature's own safe not-found rather than a PostgREST cast error.
///
/// This is a **shape** check and never an authorization check. A perfectly
/// well-formed id belonging to another Retailer reaches exactly the same
/// not-found screen, because the backend returns zero rows for it.
bool isCampaignIdShaped(String raw) => _uuidPattern.hasMatch(raw);

/// Parses the six campaign read contracts.
///
/// ## Strict, and deliberately stricter than the rest of this application
///
/// The Vendor Product and Retailer parsers degrade an unrecognised enum token to
/// an `unknown` member and render a neutral badge. **This parser refuses it.**
///
/// The difference is what the values decide. A product's status is decoration
/// beside a name a Vendor still needs to see. A campaign's enums decide which
/// section it is filed under, whether a reader is told a reward is available
/// now, whether the zero-product warning appears, and which sentence describes
/// how money is earned. There is no neutral rendering of "we could not read how
/// this campaign pays" — the honest options are the right sentence or no
/// campaign, and a wrong sentence about a reward is worse than a failed read.
///
/// So every branch below throws rather than substituting a default, and the
/// repository turns that into [RetailerReadProblem.malformed] — never an empty
/// list, never a partially populated card, and never "you are not allowed".
///
/// ## The whole list, or none of it
///
/// One malformed row fails the read. Skipping bad rows would under-report what a
/// Retailer has been offered, and a campaign list quietly short by one campaign
/// is worse than one that honestly failed to load.
///
/// ## What is rejected
///
/// * a body that is not a list, or a row that is not an object;
/// * a missing, null, blank or non-string required text column;
/// * a `campaign_id` that is not UUID-shaped;
/// * **any** unrecognised enum token, in any of the seven vocabularies;
/// * a `SELECTED_PRODUCTS` / `LIVE_TEMPORAL` pair, or `ALL_ELIGIBLE_PRODUCTS` /
///   `SNAPSHOT` — both are refused by `campaign_versions_resolution_matches_scope`
///   at the table and cannot be stored, so a row carrying one is not this shape;
/// * an unparseable timestamp, or a period whose end is not after its start;
/// * a numeric column that is not an integer, or one outside the bounds the
///   deployed `CHECK` constraints enforce — a non-positive rate, a threshold
///   below one, a coin amount over `campaignCoinCeiling`, a negative count;
/// * a reward whose typed half does not match its rule type: a
///   `PER_UNIT_COINS` row without a rate, a `TARGET_BONUS` row carrying one, or
///   a `TARGET_BONUS` row with no tier.
///
/// ## What is tolerated
///
/// * an **empty list** → nothing assigned. A real answer.
/// * an **unrecognised extra key** → ignored; the contract is additive.
/// * a **null `description`, `ends_at`, `barcode` or `brand`** → null. All four
///   are nullable in the schema, and null means "not recorded" or, for
///   `ends_at`, "evergreen".
/// * **duplicate products** → kept, both of them. See [CampaignProduct].
abstract final class CampaignParsers {
  // -- Retailer Owner -------------------------------------------------------

  /// `list_my_retailer_campaigns()`.
  static List<RetailerCampaign> parseRetailerCampaigns(Object? raw) {
    return RpcRow.asRows(
      raw,
      'retailer campaigns',
    ).map(parseRetailerCampaignRow).toList(growable: false);
  }

  /// `get_my_retailer_campaign(uuid)`.
  ///
  /// The contract is set-returning, so PostgREST renders it as an array of zero
  /// or one row. **Zero rows is the load-bearing case**: it is what an unknown
  /// id, another Retailer's id and a superseded version all produce, and it maps
  /// to a safe not-found rather than to a failure.
  ///
  /// More than one row would mean the deployed function is not the one this
  /// build expects — `campaigns.id` is a primary key and the join is on
  /// `published_version_id` — so it is refused rather than silently taking the
  /// first.
  static RetailerCampaign? parseRetailerCampaignSingle(Object? raw) {
    final List<Map<String, Object?>> rows = RpcRow.asRows(
      raw,
      'retailer campaign',
    );
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      throw const RpcFormatException(
        'retailer campaign returned more than one row',
      );
    }
    return parseRetailerCampaignRow(rows.single);
  }

  static RetailerCampaign parseRetailerCampaignRow(Map<String, Object?> row) {
    final String status = RpcRow.requiredString(
      row['campaign_status'],
      'campaign_status',
    );
    final CampaignManagementStatus? managementStatus =
        CampaignManagementStatus.tryFromCode(status);
    if (managementStatus == null) {
      throw const RpcFormatException('campaign_status is not a known status');
    }

    return RetailerCampaign(
      offer: _parseOffer(row),
      vendorName: RpcRow.requiredString(row['vendor_name'], 'vendor_name'),
      managementStatus: managementStatus,
    );
  }

  // -- Sales Staff ----------------------------------------------------------

  /// `list_my_staff_campaigns()`.
  static List<StaffCampaign> parseStaffCampaigns(Object? raw) {
    return RpcRow.asRows(
      raw,
      'staff campaigns',
    ).map(parseStaffCampaignRow).toList(growable: false);
  }

  /// `get_my_staff_campaign(uuid)`. Zero rows → null; see
  /// [parseRetailerCampaignSingle].
  static StaffCampaign? parseStaffCampaignSingle(Object? raw) {
    final List<Map<String, Object?>> rows = RpcRow.asRows(
      raw,
      'staff campaign',
    );
    if (rows.isEmpty) {
      return null;
    }
    if (rows.length > 1) {
      throw const RpcFormatException(
        'staff campaign returned more than one row',
      );
    }
    return parseStaffCampaignRow(rows.single);
  }

  /// One staff row.
  ///
  /// Reads **no** `vendor_name` and **no** `campaign_status`, because the staff
  /// contract returns neither. A key that is not read cannot be rendered, so a
  /// backend that started sending a Vendor name to sellers would still not put
  /// one on a seller's screen through this path.
  static StaffCampaign parseStaffCampaignRow(Map<String, Object?> row) {
    return StaffCampaign(offer: _parseOffer(row));
  }

  // -- Products -------------------------------------------------------------

  /// `list_my_retailer_campaign_products(uuid)` and
  /// `list_my_staff_campaign_products(uuid)` — the same five columns, resolved
  /// the same way, so one parser serves both.
  static List<CampaignProduct> parseCampaignProducts(Object? raw) {
    return RpcRow.asRows(
      raw,
      'campaign products',
    ).map(_parseProductRow).toList(growable: false);
  }

  static CampaignProduct _parseProductRow(Map<String, Object?> row) {
    return CampaignProduct(
      productCode: RpcRow.requiredString(row['product_code'], 'product_code'),
      productName: RpcRow.requiredString(row['product_name'], 'product_name'),
      barcode: RpcRow.optionalString(row['barcode'], 'barcode'),
      brand: RpcRow.optionalString(row['brand'], 'brand'),
      // No product_id. The contract returns one; nothing here holds it, so no
      // UUID can reach state or a screen.
    );
  }

  // -- The seventeen shared columns -----------------------------------------

  /// The columns both contracts return, parsed once.
  ///
  /// Called by both role row parsers, which is what makes it impossible for the
  /// two roles to disagree about a lifecycle state, a reward or an eligibility
  /// rule: there is one implementation and neither role has a copy.
  static CampaignOffer _parseOffer(Map<String, Object?> row) {
    final String campaignId = RpcRow.requiredString(
      row['campaign_id'],
      'campaign_id',
    );
    if (!isCampaignIdShaped(campaignId)) {
      throw const RpcFormatException('campaign_id is not a uuid');
    }

    return CampaignOffer(
      campaignId: campaignId,
      name: RpcRow.requiredString(row['campaign_name'], 'campaign_name'),
      description: RpcRow.optionalString(row['description'], 'description'),
      lifecycleState: _lifecycleState(row['derived_state']),
      schedule: _schedule(row),
      performanceScope: _performanceScope(row['performance_scope']),
      rewardRecipientScope: _recipientScope(row['reward_recipient_scope']),
      productEligibility: _productEligibility(row),
      stackingMode: _stackingMode(row['stacking_mode']),
      reward: _reward(row),
    );
  }

  static CampaignLifecycleState _lifecycleState(Object? raw) {
    final CampaignLifecycleState? state = CampaignLifecycleState.tryFromCode(
      RpcRow.requiredString(raw, 'derived_state'),
    );
    if (state == null) {
      throw const RpcFormatException('derived_state is not a known state');
    }
    return state;
  }

  static CampaignPerformanceScope _performanceScope(Object? raw) {
    final CampaignPerformanceScope? scope =
        CampaignPerformanceScope.tryFromCode(
          RpcRow.requiredString(raw, 'performance_scope'),
        );
    if (scope == null) {
      throw const RpcFormatException(
        'performance_scope is not a known measurement',
      );
    }
    return scope;
  }

  static CampaignRewardRecipientScope _recipientScope(Object? raw) {
    final CampaignRewardRecipientScope? scope =
        CampaignRewardRecipientScope.tryFromCode(
          RpcRow.requiredString(raw, 'reward_recipient_scope'),
        );
    if (scope == null) {
      throw const RpcFormatException(
        'reward_recipient_scope is not a known recipient',
      );
    }
    return scope;
  }

  static CampaignStackingMode _stackingMode(Object? raw) {
    final CampaignStackingMode? mode = CampaignStackingMode.tryFromCode(
      RpcRow.requiredString(raw, 'stacking_mode'),
    );
    if (mode == null) {
      throw const RpcFormatException('stacking_mode is not a known mode');
    }
    return mode;
  }

  /// The period and the zone.
  ///
  /// `starts_at` is `NOT NULL` in the schema and is required here. `ends_at` is
  /// nullable — the evergreen campaign — and an **unparseable** end is refused
  /// rather than dropped to null, because "no end date" and "an end date this
  /// build could not read" are different facts and only one of them is the
  /// backend's.
  static CampaignSchedule _schedule(Map<String, Object?> row) {
    final CampaignSchedule schedule = CampaignSchedule(
      startsAt: RpcRow.requiredTimestamp(row['starts_at'], 'starts_at'),
      endsAt: RpcRow.optionalTimestamp(row['ends_at'], 'ends_at'),
      timeZoneName: RpcRow.requiredString(
        row['timezone_name'],
        'timezone_name',
      ),
    );
    if (!schedule.isOrdered) {
      throw const RpcFormatException('ends_at is not after starts_at');
    }
    return schedule;
  }

  /// The product rule, including the pairing the table enforces structurally.
  static CampaignProductEligibility _productEligibility(
    Map<String, Object?> row,
  ) {
    final CampaignProductScope? scope = CampaignProductScope.tryFromCode(
      RpcRow.requiredString(row['product_scope'], 'product_scope'),
    );
    if (scope == null) {
      throw const RpcFormatException('product_scope is not a known scope');
    }

    final CampaignProductEligibilityResolution? resolution =
        CampaignProductEligibilityResolution.tryFromCode(
          RpcRow.requiredString(
            row['product_eligibility_resolution'],
            'product_eligibility_resolution',
          ),
        );
    if (resolution == null) {
      throw const RpcFormatException(
        'product_eligibility_resolution is not a known resolution',
      );
    }

    final int count = _requiredInt(
      row['eligible_product_count'],
      'eligible_product_count',
    );
    // A count of zero is preserved exactly as it arrived — it is the whole
    // point of the warning this feature renders. A NEGATIVE count is something
    // `count(*)` cannot produce, so it means the response is not this shape.
    if (count < 0) {
      throw const RpcFormatException('eligible_product_count is negative');
    }

    final CampaignProductEligibility eligibility = CampaignProductEligibility(
      scope: scope,
      resolution: resolution,
      eligibleProductCount: count,
    );
    if (!eligibility.isCoherent) {
      throw const RpcFormatException(
        'product_scope and product_eligibility_resolution do not pair',
      );
    }
    return eligibility;
  }

  /// The reward rule.
  ///
  /// ## Every bound the table enforces is re-checked here
  ///
  /// Not because the backend is untrusted, but because this is the boundary
  /// where "not the contract this build was written against" has to be caught.
  /// A rate of zero, a threshold of zero or a coin amount above the ceiling
  /// cannot be stored by the deployed schema, so a row carrying one is not this
  /// shape — and rendering "Earn 0 coins per eligible unit" would be a
  /// confidently wrong statement about money.
  ///
  /// ## `rule_type` is required, even though the join is a LEFT JOIN
  ///
  /// Both contracts `left join public.campaign_rules ... and r.sequence = 1`, so
  /// a null `rule_type` is representable in the response. It is nonetheless a
  /// malformed row: `publish_vendor_campaign` refuses a draft with no rule —
  /// *"A draft without a rule cannot be published"* — and only published
  /// versions in force reach these reads. A campaign whose reward cannot be
  /// described is not a campaign this screen can show.
  static CampaignReward _reward(Map<String, Object?> row) {
    final CampaignRewardRuleType? ruleType = CampaignRewardRuleType.tryFromCode(
      RpcRow.requiredString(row['rule_type'], 'rule_type'),
    );
    if (ruleType == null) {
      throw const RpcFormatException('rule_type is not a known rule');
    }

    final CampaignMetricType? metric = CampaignMetricType.tryFromCode(
      RpcRow.requiredString(row['metric_type'], 'metric_type'),
    );
    if (metric == null) {
      throw const RpcFormatException('metric_type is not a known metric');
    }

    final int? maxRewardCoins = _optionalCoins(
      row['max_reward_coins'],
      'max_reward_coins',
    );
    final int? coinsPerUnit = _optionalCoins(
      row['coins_per_unit'],
      'coins_per_unit',
    );
    final int? thresholdUnits = _optionalInt(
      row['threshold_units'],
      'threshold_units',
    );
    final int? rewardCoins = _optionalCoins(
      row['reward_coins'],
      'reward_coins',
    );

    switch (ruleType) {
      case CampaignRewardRuleType.perUnitCoins:
        // `campaign_rules_rate_paired` is an equivalence, so this direction is
        // guaranteed by the table.
        if (coinsPerUnit == null) {
          throw const RpcFormatException(
            'coins_per_unit is missing for a per-unit rule',
          );
        }
        // The tier belongs to a target rule. A per-unit row carrying one means
        // two rules are being described at once, and there is no sentence that
        // says both.
        if (thresholdUnits != null || rewardCoins != null) {
          throw const RpcFormatException(
            'a per-unit rule carries a target tier',
          );
        }
        return CampaignPerUnitReward(
          coinsPerUnit: coinsPerUnit,
          maxRewardCoins: maxRewardCoins,
          metric: metric,
        );

      case CampaignRewardRuleType.targetBonus:
        // The other direction of the same equivalence.
        if (coinsPerUnit != null) {
          throw const RpcFormatException(
            'a target rule carries a per-unit rate',
          );
        }
        // Tier 1 holds the target and the bonus. Without it there is no target
        // to reach and no reward to describe, so the row cannot be rendered
        // truthfully at all.
        if (thresholdUnits == null || rewardCoins == null) {
          throw const RpcFormatException('a target rule has no tier');
        }
        if (thresholdUnits < 1) {
          throw const RpcFormatException('threshold_units is below one');
        }
        return CampaignTargetReward(
          thresholdUnits: thresholdUnits,
          rewardCoins: rewardCoins,
          maxRewardCoins: maxRewardCoins,
          metric: metric,
        );
    }
  }

  // -- Numeric readers ------------------------------------------------------

  /// A `bigint` or `integer` column that is `NOT NULL` in the contract.
  ///
  /// Accepts an integer, and a `num` whose value is integral — JSON has one
  /// number type and a transport is entitled to hand back `1.0`. Matches the
  /// receipt and Vendor Product parsers.
  ///
  /// A **string** is refused: a numeric column arriving as text means the
  /// response is not the shape this build was written against.
  static int _requiredInt(Object? raw, String what) {
    final int? value = _optionalInt(raw, what);
    if (value == null) {
      throw RpcFormatException('$what is missing');
    }
    return value;
  }

  /// A nullable `bigint` or `integer` column.
  static int? _optionalInt(Object? raw, String what) {
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is num && raw.isFinite && raw == raw.roundToDouble()) {
      return raw.toInt();
    }
    throw RpcFormatException('$what is not an integer');
  }

  /// A nullable coin amount, bounded exactly as the schema bounds it.
  ///
  /// Strictly positive and no greater than [campaignCoinCeiling]. Zero is
  /// refused along with the negatives: `campaign_rules_rate_positive`,
  /// `campaign_rules_cap_positive` and `campaign_rule_tiers_reward_positive` all
  /// exclude it, and the migration says why — *"A cap of zero is a campaign that
  /// pays nothing, which no operator means to configure."*
  static int? _optionalCoins(Object? raw, String what) {
    final int? value = _optionalInt(raw, what);
    if (value == null) {
      return null;
    }
    if (value < 1) {
      throw RpcFormatException('$what is not positive');
    }
    if (value > campaignCoinCeiling) {
      throw RpcFormatException('$what is above the coin ceiling');
    }
    return value;
  }
}
