/// Every string the Sales Staff home renders.
///
/// Centralised for the same reason `CampaignCopy` and `EarningsCopy` are: **no
/// copy on this screen may be derived from a backend response.** Each string is
/// a fixed literal or a function of parsed, validated values, so a Postgres
/// message, a SQLSTATE, a stack trace, a UUID or an internal enum token cannot
/// reach a screen through any of them.
///
/// ## Encouraging, and true
///
/// The screen is meant to feel motivating. That is a constraint on tone, never
/// on accuracy — so nothing here invents a streak, a countdown, a rank, a
/// prediction, a personal statistic or a promise about a future reward. The one
/// forward-looking sentence on the screen, [greetingLine], says a reward is
/// *within reach*, which is true of every seller with a running campaign and
/// asserts nothing about any of them in particular.
///
/// ## Nothing here is a balance
///
/// The coin figure is labelled as **earned**, with the same qualifying notice
/// the earnings screen carries. Not one string calls it a wallet balance, an
/// available balance, redeemable coins, paid coins or a payout, because none of
/// those exists in the deployed schema.
abstract final class SalesStaffHomeCopy {
  // -- Screen chrome --------------------------------------------------------

  static const String title = 'Home';

  static const String loading = 'Loading your home screen…';
  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';

  // -- Welcome --------------------------------------------------------------

  /// The greeting. Deliberately time-of-day-free: the device clock is not the
  /// campaign's clock, and "Good morning" on a night shift is a small lie the
  /// screen does not need to tell.
  static const String greeting = 'Welcome back';

  /// The motivating line, and the only forward-looking sentence on the screen.
  static const String greetingLine = 'Your next reward is within reach.';

  /// Shown instead when the seller has no running or upcoming campaign at all,
  /// so the encouragement never contradicts an empty screen below it.
  static const String greetingLineNoCampaigns =
      'Keep submitting invoices / receipts — campaigns appear here as soon '
      'as a Vendor '
      'runs one for your Retailer.';

  /// The organization name is the trusted session context's, never a value read
  /// back from a campaign or a reward.
  static String forRetailer(String organizationName) =>
      'Selling for $organizationName';

  // -- Campaign coins -------------------------------------------------------

  static const String coinsSectionTitle = 'Campaign coins earned';

  static const String coinsHint =
      'Every campaign reward awarded to you, added up.';

  static const String coinsAction = 'View my earnings';

  /// The totals could not be read. Said as a line inside the panel rather than
  /// as a screen-wide failure: the campaigns below came from a different
  /// contract and are unaffected.
  static const String coinsUnavailable = 'Your totals could not be loaded.';

  static const String thisMonthLabel = 'This month';
  static const String rewardedSalesLabel = 'Rewarded sales';
  static const String rewardedCampaignsLabel = 'Rewarded campaigns';

  // -- The hero ------------------------------------------------------------

  /// The hero's eyebrow, chosen from the stored `target_reached` boolean and
  /// nothing else.
  ///
  /// It never says "next reward" over a target that has already been met, and
  /// never says "reached" over one that has not.
  static const String heroEyebrowNext = 'YOUR NEXT REWARD';
  static const String heroEyebrowReached = 'TARGET REACHED';
  static const String heroEyebrowRunning = 'RUNNING NOW';
  static const String heroEyebrowUpcoming = 'STARTING SOON';

  /// The action on the hero. It opens the campaign; it earns nothing.
  static const String heroAction = 'View campaign';

  /// Shown in place of the hero when there is no campaign at all.
  static const String heroEmptyTitle = 'No campaign to aim at yet';
  static const String heroEmptyBody =
      'When a Vendor runs a campaign for your Retailer it appears here, with '
      'your progress towards it.';

  /// The hero's centre label under the percentage.
  static const String heroOfTarget = 'of target';

  // -- Opportunities --------------------------------------------------------

  static const String opportunitiesTitle = 'Running now';
  static const String upcomingTitle = 'Starting soon';

  /// The carousel heading. "for you" is about **targeting** — these campaigns
  /// were assigned to this seller's Retailer — and not about a ranking.
  static const String carouselTitle = 'Opportunities for you';

  /// Told once, under the carousel heading, so a horizontal list is not
  /// mistaken for the whole list.
  static const String carouselHint = 'Swipe to see more';

  static const String opportunitiesDescription =
      'Eligible sales count towards these campaigns.';
  static const String upcomingDescription =
      'These have not started yet. Eligible sales will count from their start '
      'date.';

  static const String viewAllCampaigns = 'View all campaigns';

  static const String campaignsEmptyTitle = 'No campaigns right now';
  static const String campaignsEmptyBody =
      'No active or upcoming campaigns are available for your shop. '
      'Invoices / receipts '
      'you submit are still recorded.';

  /// The campaign read failed outright. Reason-free, like every other failure
  /// notice in this application.
  static const String campaignsUnavailableTitle = 'Campaigns did not load';
  static const String campaignsUnavailableBody =
      'Your campaigns could not be loaded just now. Pull down to try again.';

  /// Named so the cap is stated rather than left to look like the whole list.
  static String showingSome(int shown, int total) =>
      'Showing $shown of $total.';

  // -- Recent submissions ---------------------------------------------------

  static const String recentTitle = 'Recent invoices / receipts';
  static const String recentDescription = 'Your most recent submissions.';
  static const String recentAction = 'View all';

  static const String recentEmptyTitle = 'No invoices / receipts yet';
  static const String recentEmptyBody =
      'Invoices / receipts you submit will appear here straight away.';

  // -- The primary action ---------------------------------------------------

  /// Required wording for the primary call to action.
  static const String addReceipt = 'Add invoice / receipt';

  /// The accessible name, which has room for the whole phrase the four-word
  /// button does not.
  static const String addReceiptSemanticLabel =
      'Add an invoice / receipt to submit';

  /// The supporting line under the action.
  ///
  /// "to qualify" and not "to earn": submitting a receipt makes a sale
  /// *eligible for evaluation*. Whether it earns anything is decided by
  /// verification and by the campaign, neither of which this button performs.
  static const String addReceiptHint = 'Submit your sale to qualify';

  // -- Recent receipt -------------------------------------------------------

  /// The single latest submission, rather than a list. The full history is one
  /// tap away and is the screen that owns it.
  static const String latestReceiptTitle = 'Latest invoice / receipt';
}
