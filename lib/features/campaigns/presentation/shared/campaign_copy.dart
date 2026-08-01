import '../../../../core/utils/date_format.dart';
import '../../domain/entities/campaign_lifecycle_state.dart';
import '../../domain/entities/campaign_measurement.dart';
import '../../domain/entities/campaign_offer.dart';
import '../../domain/entities/campaign_product_eligibility.dart';
import '../../domain/entities/campaign_reward.dart';
import '../../domain/entities/campaign_schedule.dart';
import '../../domain/entities/campaign_stacking_mode.dart';
import 'campaign_presentation.dart';

/// Every string the campaign screens render.
///
/// Centralised for one reason above all: **no copy on these screens may be
/// derived from a backend response.** Each string is a fixed literal or a
/// function of parsed, validated values, so a Postgres message, a SQLSTATE, a
/// stack trace, a UUID or an internal enum token cannot reach a screen through
/// any of them.
///
/// In particular, **no `.code` is ever interpolated**. Every enum in this
/// feature carries its backend token, and not one of them is rendered: each has
/// a hand-written sentence here instead. A reader is never shown
/// `RETAILER_TEAM`, `LIVE_TEMPORAL` or `PER_UNIT_COINS`.
///
/// The only interpolated values are the campaign's own name, description, Vendor
/// name, time-zone label, dates, and the four configured reward numbers.
///
/// ## Nothing here computes a result
///
/// Every reward sentence describes the **offer**. None of them says what has
/// been sold, what has been earned, or how far along anything is, because no
/// such value exists in the contract. [engineNotice] states that plainly on
/// every screen that shows a reward, so the absence reads as "not yet" rather
/// than as an empty number.
abstract final class CampaignCopy {
  // -- Screen chrome --------------------------------------------------------

  static const String title = 'Campaigns';

  /// Worded around what the Owner contract actually returns: the whole history
  /// of campaigns in force against this Retailer, not just the live ones.
  static const String retailerDescription =
      'The campaigns Vendors have assigned to your organization.';

  /// Worded around the ACTIVE/SCHEDULED filter the staff contract applies in
  /// SQL, so the scope of the list is stated rather than left to be inferred
  /// from what happens to be in it.
  static const String staffDescription =
      'The campaigns running now or starting soon for your Retailer.';

  static String description(CampaignAudience audience) => switch (audience) {
    CampaignAudience.retailerOwner => retailerDescription,
    CampaignAudience.salesStaff => staffDescription,
  };

  static const String loading = 'Loading campaigns…';
  static const String loadingDetail = 'Loading campaign…';
  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';
  static const String back = 'Back';
  static const String backToCampaigns = 'Back to campaigns';

  // -- Read-only framing ----------------------------------------------------

  /// Two facts a reader would otherwise get wrong, stated once.
  ///
  /// The first is agency: a Retailer cannot change a campaign. Authoring,
  /// publishing, pausing, versioning and cancelling are Vendor operations on
  /// `CAMPAIGNS_MANAGE`, performed elsewhere entirely — so the screen must not
  /// imply a control exists that is merely absent here.
  ///
  /// The second is scope: what is shown is the version currently **in force**.
  /// A superseded version's terms are history and are not retrievable, so the
  /// app must not imply one is hiding behind a filter.
  static const String retailerReadOnlyNote =
      'Campaigns are created and managed by the Vendor. This shows the terms '
      'currently in force for your organization.';

  static const String staffReadOnlyNote =
      'Campaigns are set by the Vendor. This shows what is running now or '
      'starting soon for your Retailer.';

  static String readOnlyNote(CampaignAudience audience) => switch (audience) {
    CampaignAudience.retailerOwner => retailerReadOnlyNote,
    CampaignAudience.salesStaff => staffReadOnlyNote,
  };

  /// The one notice every screen that shows a reward also shows.
  ///
  /// It is why there is no progress bar, no units-sold figure and no coin
  /// balance anywhere in this feature: the contract returns the offer and
  /// nothing else, and saying so is more honest than a zero that looks like a
  /// measurement.
  static const String engineNotice =
      'Campaign results and coin calculation will appear when the calculation '
      'engine is connected.';

  // -- Empty and failure states --------------------------------------------

  static const String emptyTitle = 'No campaigns yet';

  static const String retailerEmptyBody =
      'Campaigns appear here when a Vendor assigns one to your organization.';

  static const String staffEmptyBody =
      'Campaigns appear here when one is running or about to start for your '
      'Retailer.';

  static String emptyBody(CampaignAudience audience) => switch (audience) {
    CampaignAudience.retailerOwner => retailerEmptyBody,
    CampaignAudience.salesStaff => staffEmptyBody,
  };

  static const String staleTitle = 'Showing the last loaded campaigns';
  static const String staleBody =
      'The most recent refresh did not complete, so this list may be out of '
      'date. Try refreshing again.';

  /// The one answer for every reason a campaign is not readable at this
  /// address.
  ///
  /// Says nothing about **why**, and offers no retry. An unknown campaign,
  /// another Retailer's campaign, a superseded version and — for a seller — a
  /// campaign that has since been paused all reach this screen, and telling them
  /// apart would let a reader learn which ids name real campaigns somewhere
  /// else.
  static const String notFoundTitle = 'This campaign is not available';
  static const String notFoundBody =
      'It may have finished, been replaced by a newer version, or no longer '
      'apply to your Retailer. Go back to see the campaigns available to you.';

  // -- Section headings -----------------------------------------------------

  static String sectionTitle(CampaignSectionKind kind) => switch (kind) {
    CampaignSectionKind.runningNow => 'Running now',
    CampaignSectionKind.startingSoon => 'Starting soon',
    CampaignSectionKind.paused => 'Paused',
    CampaignSectionKind.finished => 'Finished',
    CampaignSectionKind.cancelled => 'Cancelled',
    CampaignSectionKind.notPublished => 'Not published',
  };

  // -- Lifecycle ------------------------------------------------------------

  /// The badge label. Never the backend token.
  static String lifecycleLabel(CampaignLifecycleState state) => switch (state) {
    CampaignLifecycleState.active => 'Running',
    CampaignLifecycleState.scheduled => 'Starting soon',
    CampaignLifecycleState.paused => 'Paused',
    CampaignLifecycleState.ended => 'Finished',
    CampaignLifecycleState.cancelled => 'Cancelled',
    CampaignLifecycleState.draft => 'Not published',
  };

  /// A sentence for the detail screen's status line, so the state is carried by
  /// words as well as by a pill.
  static String lifecycleExplanation(CampaignLifecycleState state) =>
      switch (state) {
        CampaignLifecycleState.active =>
          'This campaign is running. Eligible sales count toward it now.',
        CampaignLifecycleState.scheduled =>
          'This campaign has not started yet. Eligible sales will count from '
              'its start date.',
        CampaignLifecycleState.paused =>
          'This campaign is paused by the Vendor. Eligible sales do not count '
              'while it is paused.',
        CampaignLifecycleState.ended =>
          'This campaign has finished. Its period has passed.',
        CampaignLifecycleState.cancelled =>
          'This campaign was cancelled by the Vendor.',
        CampaignLifecycleState.draft => 'This campaign has not been published.',
      };

  // -- Section titles -------------------------------------------------------

  static const String descriptionSectionTitle = 'About this campaign';

  // -- Reward ---------------------------------------------------------------

  static const String rewardSectionTitle = 'Reward';

  /// The configured offer, in one sentence.
  ///
  /// Reads the performance scope from the campaign rather than from the reward,
  /// because the same "25 units" is a personal goal under `INDIVIDUAL_STAFF` and
  /// a shop-wide one under `RETAILER_TEAM` — and a target sentence that did not
  /// say which would be ambiguous about money.
  ///
  /// **No arithmetic.** Nothing multiplies the rate by anything, nothing
  /// subtracts a cap from a total, and nothing divides a shared bonus between
  /// people. Every number in the output is a value the RPC returned.
  static String rewardSentence(CampaignOffer offer, CampaignAudience audience) {
    final CampaignReward reward = offer.reward;
    return switch (reward) {
      CampaignPerUnitReward() => _perUnitSentence(reward),
      CampaignTargetReward() => _targetSentence(
        reward,
        offer.performanceScope,
        audience,
      ),
    };
  }

  static String _perUnitSentence(CampaignPerUnitReward reward) {
    final String rate = 'Earn ${_coins(reward.coinsPerUnit)} per eligible unit';
    final int? cap = reward.maxRewardCoins;
    if (cap == null) {
      return '$rate.';
    }
    return '$rate, up to ${_coins(cap)}.';
  }

  static String _targetSentence(
    CampaignTargetReward reward,
    CampaignPerformanceScope scope,
    CampaignAudience audience,
  ) {
    final String units = _units(reward.thresholdUnits);
    final String bonus = _coinAmount(reward.rewardCoins);

    final String sentence = switch ((scope, audience)) {
      // A shared Retailer target reads the same way to both roles: it is the
      // organization that reaches it either way, and "your Retailer" is
      // accurate for an Owner and a seller alike.
      (CampaignPerformanceScope.retailerTeam, _) =>
        'When your Retailer reaches $units, contributing Sales Staff share '
            'the configured $bonus-coin reward according to the campaign rules.',
      // An individual target is something a seller reaches themselves and
      // something an Owner watches their staff reach, so the two are written
      // separately rather than addressed to whoever happens to be looking.
      (CampaignPerformanceScope.individualStaff, CampaignAudience.salesStaff) =>
        'Reach $units to qualify for the configured $bonus-coin reward.',
      (
        CampaignPerformanceScope.individualStaff,
        CampaignAudience.retailerOwner,
      ) =>
        'A Sales Staff member who reaches $units qualifies for the configured '
            '$bonus-coin reward.',
    };

    final int? cap = reward.maxRewardCoins;
    if (cap == null) {
      return sentence;
    }
    // `max_reward_coins` sits on `campaign_rules` and applies to either rule
    // type, so a target bonus can carry one too. Stated as its own sentence
    // rather than folded in, because it bounds the campaign rather than the
    // individual reward.
    return '$sentence This campaign pays no more than ${_coins(cap)} in total.';
  }

  // -- Measurement ----------------------------------------------------------

  static const String measurementSectionTitle = 'How performance is measured';

  /// Whether sales are counted per person or across the Retailer.
  ///
  /// The two seller sentences are the ones the milestone specified verbatim. The
  /// two Owner sentences say the same fact in a voice that fits somebody who
  /// does not sell.
  static String measurementSentence(
    CampaignPerformanceScope scope,
    CampaignAudience audience,
  ) => switch ((scope, audience)) {
    (CampaignPerformanceScope.individualStaff, CampaignAudience.salesStaff) =>
      'Your eligible sales are measured separately.',
    (
      CampaignPerformanceScope.individualStaff,
      CampaignAudience.retailerOwner,
    ) =>
      "Each Sales Staff member's eligible sales are measured separately.",
    (CampaignPerformanceScope.retailerTeam, CampaignAudience.salesStaff) =>
      'Eligible Sales Staff sales in your Retailer contribute to the shared '
          'Retailer target.',
    (CampaignPerformanceScope.retailerTeam, CampaignAudience.retailerOwner) =>
      'Eligible Sales Staff sales in your Retailer contribute to one shared '
          'Retailer target.',
  };

  /// The short form, for a card.
  static String measurementLabel(CampaignPerformanceScope scope) =>
      switch (scope) {
        CampaignPerformanceScope.individualStaff => 'Individual',
        CampaignPerformanceScope.retailerTeam => 'Retailer team',
      };

  // -- Product eligibility --------------------------------------------------

  static const String productsSectionTitle = 'Eligible products';

  /// Which products count, and when that was decided.
  ///
  /// Two sentences for two rules, and the pairing is guaranteed by the table —
  /// `SELECTED_PRODUCTS` implies `SNAPSHOT` and `ALL_ELIGIBLE_PRODUCTS` implies
  /// `LIVE_TEMPORAL` — so switching on the scope alone says everything.
  ///
  /// **No temporal calculation happens here or anywhere in this feature.** The
  /// second sentence describes what the backend already resolved at
  /// `least(now(), coalesce(ends_at, 'infinity'))`; it does not re-derive it.
  static String eligibilitySentence(CampaignProductScope scope) =>
      switch (scope) {
        CampaignProductScope.selectedProducts =>
          'Only the products selected for this campaign version count. '
              'Eligibility was frozen when the campaign was published.',
        CampaignProductScope.allEligibleProducts =>
          'Products assigned to your Retailer count while they are eligible. '
              'Later assignment changes affect later sales, not earlier sales.',
      };

  /// The short form, for a card.
  static String productScopeLabel(CampaignProductScope scope) =>
      switch (scope) {
        CampaignProductScope.selectedProducts => 'Selected products',
        CampaignProductScope.allEligibleProducts => 'All eligible products',
      };

  /// The eligible-product count, as a card fact.
  static String productCountLabel(int count) => switch (count) {
    0 => 'No eligible products',
    1 => '1 eligible product',
    _ => '$count eligible products',
  };

  // -- The zero-eligible-product warning -----------------------------------

  /// Deliberately NOT the same string as `productCountLabel(0)`.
  ///
  /// Both appear on the detail screen — the count inside the products section,
  /// the title on the warning above it — and rendering the identical phrase
  /// twice reads as a duplicated element rather than as two facts.
  static const String noProductsTitle =
      'No eligible products for this campaign';

  /// The truthful state, worded exactly as it was approved on the Web.
  ///
  /// Three things it deliberately does **not** do:
  ///
  /// * it does not say the campaign is broken — the campaign is configured
  ///   correctly and simply has nothing to apply to here;
  /// * it does not suggest the reader fix it — product assignment is a Vendor
  ///   action on `PRODUCT_RETAILER_ASSIGN`, and no control for it exists on any
  ///   Retailer or Sales Staff surface;
  /// * it does not hide the campaign, or round the zero away.
  ///
  /// "your Retailer" rather than "you" for both roles: eligibility is a fact
  /// about the organization's assignments, and a seller must not read it as
  /// something about their own account.
  static const String noProductsBody =
      'No eligible products are currently assigned to your Retailer for this '
      'campaign. Sales cannot earn coins until an eligible product is '
      'available.';

  /// The compact form for a card, where the full sentence would dominate.
  static const String noProductsCardNote =
      'No eligible products are assigned to your Retailer for this campaign.';

  static const String productsEmptyDetail =
      'No products are listed for this campaign for your Retailer.';

  // -- Stacking -------------------------------------------------------------

  static const String stackingSectionTitle = 'Combining with other campaigns';

  /// Whether this campaign combines with others.
  ///
  /// Describes the **mode** and nothing else. `exclusivity_key` and `priority`
  /// are the Vendor's competition configuration between its own campaigns;
  /// neither is returned by either contract, neither is held anywhere in this
  /// application, and neither appears in any sentence here.
  static String stackingSentence(CampaignStackingMode mode) => switch (mode) {
    CampaignStackingMode.stackable =>
      'This campaign can apply at the same time as other campaigns that also '
          'allow it.',
    CampaignStackingMode.exclusive =>
      'This campaign does not combine with other campaigns. Only one exclusive '
          'campaign applies to an eligible sale.',
  };

  /// The short form, for a card.
  static String stackingLabel(CampaignStackingMode mode) => switch (mode) {
    CampaignStackingMode.stackable => 'Combines with others',
    CampaignStackingMode.exclusive => 'Exclusive',
  };

  // -- Schedule -------------------------------------------------------------

  static const String scheduleSectionTitle = 'Schedule';
  static const String startsLabel = 'Starts';
  static const String endsLabel = 'Ends';
  static const String timeZoneLabel = 'Campaign time zone';

  /// The period, as a card fact.
  ///
  /// Rendered in the **device's** time zone, like every other date in this
  /// application — see [CampaignSchedule] for why no conversion into the
  /// campaign's own zone happens, and [timeZoneNote] for how that is disclosed.
  static String dateRange(CampaignSchedule schedule) {
    final String start = formatDayDate(schedule.startsAt);
    final DateTime? end = schedule.endsAt;
    if (end == null) {
      return 'From $start · No end date';
    }
    return '$start – ${formatDayDate(end)}';
  }

  static String endDateValue(CampaignSchedule schedule) {
    final DateTime? end = schedule.endsAt;
    // An evergreen campaign has no end date. Said in words rather than left
    // blank or filled with a dash, because "runs until the Vendor stops it" is
    // a real term and an empty cell is not.
    return end == null ? 'No end date' : formatDayDate(end);
  }

  /// States which zone the dates above are in, and which zone the campaign is
  /// scheduled in.
  ///
  /// Shown whenever a schedule is shown. The application ships no IANA time-zone
  /// database, so it cannot render the campaign's own wall clock — and saying so
  /// is better than showing a device-local date under a heading that implies
  /// otherwise.
  static String timeZoneNote(String timeZoneName) =>
      'Dates are shown in your device time zone. This campaign is scheduled '
      'in $timeZoneName.';

  // -- Vendor ---------------------------------------------------------------

  static const String vendorLabel = 'Vendor';

  // -- Accessibility --------------------------------------------------------

  /// The screen-reader label for a whole campaign card.
  ///
  /// One utterance, in the same order as the visible content, so the reading
  /// order follows the layout. The individual pieces inside the card are
  /// excluded from the semantics tree, which is what stops a reader hearing the
  /// name, then the status, then the name again inside the badge.
  ///
  /// The zero-product warning is included **once**, at the end, where the visual
  /// notice sits.
  static String cardSemanticLabel(CampaignPresentation campaign) {
    final CampaignOffer offer = campaign.offer;
    final StringBuffer buffer = StringBuffer(offer.name)
      ..write('. ')
      ..write(lifecycleLabel(offer.lifecycleState))
      ..write('. ');

    final String? vendor = campaign.vendorName;
    if (vendor != null) {
      buffer
        ..write(vendorLabel)
        ..write(': ')
        ..write(vendor)
        ..write('. ');
    }

    buffer
      ..write(rewardSentence(offer, campaign.audience))
      ..write(' ')
      ..write(measurementLabel(offer.performanceScope))
      ..write('. ')
      ..write(productScopeLabel(offer.productEligibility.scope))
      ..write('. ')
      ..write(productCountLabel(offer.productEligibility.eligibleProductCount))
      ..write('. ')
      ..write(dateRange(offer.schedule))
      ..write('.');

    if (offer.showsEmptyProductWarning) {
      buffer
        ..write(' ')
        ..write(noProductsCardNote);
    }
    return buffer.toString();
  }

  // -- Number formatting ----------------------------------------------------

  /// `2500` → `2,500 coins`; `1` → `1 coin`.
  static String _coins(int amount) =>
      '${_coinAmount(amount)} ${amount == 1 ? 'coin' : 'coins'}';

  /// `25` → `25 eligible units`; `1` → `1 eligible unit`.
  static String _units(int amount) =>
      '${formatCampaignNumber(amount)} eligible '
      '${amount == 1 ? 'unit' : 'units'}';

  /// The bare grouped amount, for the `2,500-coin reward` construction.
  static String _coinAmount(int amount) => formatCampaignNumber(amount);
}

/// Groups an integer with thousands separators: `2500` → `2,500`.
///
/// Hand-rolled rather than `package:intl`, matching `date_format.dart` and the
/// receipt, Retailer, User, Role and Product features: the application ships one
/// locale, so a localisation dependency would be weight for a handful of
/// strings.
///
/// Kept local to this feature rather than promoted to `core`. The codebase's own
/// rule, recorded on `ReadResult`, is *"when a third feature needs one, that is
/// the evidence to promote it"* — this is the first.
///
/// Negatives are handled for completeness, though no campaign number can be one:
/// every coin column is `> 0` and every count is `>= 0` at the parse boundary.
String formatCampaignNumber(int value) {
  final bool negative = value < 0;
  final String digits = value.abs().toString();
  final StringBuffer buffer = StringBuffer();

  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}
