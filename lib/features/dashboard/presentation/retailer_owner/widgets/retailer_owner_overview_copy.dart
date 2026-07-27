import '../../../domain/repositories/retailer_owner_overview_repository.dart';

/// Every string the Retailer Owner Overview renders.
///
/// Centralised for one reason above all others: **no copy on this screen may be
/// derived from a backend response.** Each string below is a fixed literal
/// chosen from a discriminant, so a Postgres message, a SQLSTATE, a GoTrue
/// error, a stack trace, a token or a raw UUID cannot reach the screen through
/// any of them — there is no interpolation of a response value anywhere in this
/// file except the organization's own name and the two ISO codes, which are the
/// display values the contract exists to return.
abstract final class RetailerOwnerOverviewCopy {
  // -- page chrome ----------------------------------------------------------

  static const String title = 'Overview';
  static const String description =
      'A read-only view of your organization and its shops on SalesReward.';

  static const String loading = 'Loading your overview…';
  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';

  // -- the organization panel ----------------------------------------------

  static const String organizationSectionTitle = 'Your organization';
  static const String organizationSectionDescription =
      'Recorded by SalesReward for your Retailer account.';

  static const String retailerNameLabel = 'Retailer';
  static const String retailerStatusLabel = 'Retailer status';
  static const String countryLabel = 'Country';
  static const String currencyLabel = 'Default currency';
  static const String membershipStatusLabel = 'Your membership';

  /// Shown in place of a nullable ISO code the backend did not record.
  ///
  /// Deliberately not a guess. `country_code` and `default_currency` are both
  /// nullable in the schema, so "not recorded" is a real answer — and a
  /// fabricated currency on a rewards product is the kind of wrong that looks
  /// right.
  static const String notRecorded = 'Not recorded';

  // -- the shop counts ------------------------------------------------------

  static const String shopsSectionTitle = 'Shops';
  static const String shopsSectionDescription =
      'Counted by SalesReward across your whole organization.';

  static const String totalShopsLabel = 'Total shops';
  static const String totalShopsHint = 'Every shop, whatever its status';
  static const String activeShopsLabel = 'Active shops';
  static const String activeShopsHint = 'Currently trading';

  /// The one thing about these two figures a reader could otherwise get wrong.
  static const String shopsNote =
      'Both figures are counted by SalesReward, so they match the numbers on '
      'the web portal exactly. Shop details are not available in the app yet.';

  // -- the inactive-status notice ------------------------------------------

  static const String inactiveTitle = 'This account needs attention';
  static const String inactiveBody =
      'Your organization or your membership is not currently active. Some '
      'parts of the portal may be unavailable. Contact whoever manages your '
      'SalesReward access.';

  // -- the stale-refresh notice --------------------------------------------

  static const String staleTitle = 'Showing the last loaded overview';
  static const String staleBody =
      'The most recent refresh did not complete, so these figures may be out '
      'of date. Try refreshing again.';

  // -- the ineligible state -------------------------------------------------

  static const String ineligibleTitle = 'No Retailer overview for this account';
  static const String ineligibleBody =
      'SalesReward has no Retailer Owner workspace for you. This happens when '
      'an account is not set up as a Retailer Owner, or when its access has '
      'been changed. Contact whoever manages your SalesReward access.';

  // -- upcoming destinations ------------------------------------------------

  static const String upcomingTitle = 'Coming to the app';
  static const String upcomingDescription =
      'These are already available on the SalesReward web portal. They are '
      'not built into the app yet.';

  static const String upcomingShops = 'Shop list and details';
  static const String upcomingStaff = 'Staff roster and invitations';
  static const String upcomingProducts = 'Assigned products';

  /// The copy for one [RetailerOverviewProblem].
  ///
  /// The mapping is **one-to-one and total**, so widening the problem domain
  /// later cannot quietly collapse a new reason into an existing message. Only
  /// the two genuinely connection-shaped problems mention the connection:
  /// telling someone to check a connection that is working sends them to fix
  /// something that was never broken.
  ///
  /// Retryability is a property of the problem, not a preference. A refusal and
  /// a signed-out session do not change on a second identical call, so neither
  /// offers a button that would do nothing.
  static RetailerOverviewProblemCopy problemCopy(
    RetailerOverviewProblem problem,
  ) => switch (problem) {
    RetailerOverviewProblem.denied => const RetailerOverviewProblemCopy(
      title: 'Not available to this account',
      // Says nothing about whether anything exists, preserving the backend's
      // single generic denial.
      body:
          'This account does not have access to the Retailer overview. If you '
          'think that is wrong, contact whoever manages your access.',
      retryable: false,
    ),
    RetailerOverviewProblem.signedOut => const RetailerOverviewProblemCopy(
      title: 'Your session has ended',
      body: 'Sign in again to continue.',
      retryable: false,
    ),
    RetailerOverviewProblem.malformed => const RetailerOverviewProblemCopy(
      title: 'Could not read your overview',
      // Never "you have no shops". An unreadable answer is not an empty one.
      body:
          'SalesReward sent something this version of the app could not read. '
          'Updating the app may help.',
      retryable: true,
    ),
    RetailerOverviewProblem.network => const RetailerOverviewProblemCopy(
      title: 'Could not reach SalesReward',
      body: 'Check your connection and try again.',
      retryable: true,
    ),
    RetailerOverviewProblem.timeout => const RetailerOverviewProblemCopy(
      title: 'This took too long',
      body:
          'Loading your overview timed out. Check your connection and try '
          'again.',
      retryable: true,
    ),
    RetailerOverviewProblem.unexpected => const RetailerOverviewProblemCopy(
      title: 'Something went wrong',
      // Deliberately says nothing about the network: an unrecognised fault is a
      // bug in this app or the SDK, not a statement about the user's
      // connection.
      body: 'Your overview could not be loaded. Try again.',
      retryable: true,
    ),
  };
}

/// The fixed copy for one problem discriminant.
final class RetailerOverviewProblemCopy {
  const RetailerOverviewProblemCopy({
    required this.title,
    required this.body,
    required this.retryable,
  });

  final String title;
  final String body;

  /// Whether a second identical call could produce a different answer.
  final bool retryable;
}
