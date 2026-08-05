import 'package:equatable/equatable.dart';

/// The single row of `get_my_campaign_earnings_summary()`.
///
/// ## Earned is not a balance
///
/// Every value here is a sum or a count over immutable `campaign_rewards` rows
/// that already exist. The migration is explicit about what that means:
///
/// > *"Nothing here is a wallet, a balance, an available amount, a redeemable
/// > amount, a payable amount or a settled amount, and no column is named as
/// > though it were. Nothing is subtracted, because there is nothing to subtract
/// > from: no ledger and no redemption model exists, and inventing one in a read
/// > would be inventing money."*
///
/// So no field here is called a balance, nothing is netted off anything, and the
/// screen that renders it says plainly that wallet, payout and redemption do not
/// exist yet.
///
/// ## Zero is a real answer
///
/// The contract `coalesce`s the two sums to `0`, *"so a seller with no rewards
/// reads 0 rather than NULL"*. A seller who has earned nothing gets a summary of
/// zeros, and it renders as zeros — never as an error and never as a dash.
///
/// [latestRewardAt] is the one genuinely nullable value: `max(awarded_at)` over
/// no rows is null, and that means "no reward yet" rather than "unknown".
///
/// ## The month window is the backend's, not the device's
///
/// "This month" needs a time zone and the schema has none to offer a seller —
/// shops each carry their own IANA zone and one member may belong to several. So
/// the window is computed in **UTC** by the database and its exact bounds are
/// returned. [currentMonthStartUtc] and [currentMonthEndUtc] are carried so the
/// screen can label the period it is showing rather than assert a month the
/// device happens to be in.
final class CampaignEarningsSummary extends Equatable {
  const CampaignEarningsSummary({
    required this.totalRewardCoins,
    required this.currentMonthRewardCoins,
    required this.rewardedSaleCount,
    required this.rewardedCampaignCount,
    required this.latestRewardAt,
    required this.currentMonthStartUtc,
    required this.currentMonthEndUtc,
  });

  /// `sum(reward_coins)` over the caller's own rewards. Coins **earned**.
  final int totalRewardCoins;

  /// The same sum restricted to `[currentMonthStartUtc, currentMonthEndUtc)`.
  final int currentMonthRewardCoins;

  /// `count(distinct verified_sale_id)` — two campaigns paying on one sale is
  /// one rewarded sale.
  ///
  /// The **count** is returned; the sale ids behind it are not, and nothing here
  /// holds one.
  final int rewardedSaleCount;

  /// `count(distinct campaign_id)` — one campaign paying on ten sales is one
  /// rewarded campaign.
  final int rewardedCampaignCount;

  /// `max(awarded_at)`, or null when no reward has ever been awarded.
  final DateTime? latestRewardAt;

  /// The inclusive start of the UTC calendar month the backend measured.
  final DateTime currentMonthStartUtc;

  /// The exclusive end of that month.
  final DateTime currentMonthEndUtc;

  @override
  List<Object?> get props => <Object?>[
    totalRewardCoins,
    currentMonthRewardCoins,
    rewardedSaleCount,
    rewardedCampaignCount,
    latestRewardAt,
    currentMonthStartUtc,
    currentMonthEndUtc,
  ];
}
