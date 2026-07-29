/// Every user-facing sentence this feature renders, in one place.
///
/// Centralised for the same reason the receipt feature centralises its copy: a
/// string that explains a *backend* answer is part of the security boundary, not
/// decoration. The rules these strings obey:
///
/// * **No raw backend text.** No Postgres message, SQLSTATE, table, column,
///   function or policy name appears in any of them.
/// * **An inaccessible relationship is never described as somebody else's.**
///   [detailNotFoundTitle] and [detailNotFoundBody] are the single wording for
///   an unknown id, another Vendor's id and a malformed id alike. Saying "this
///   belongs to another Vendor" would confirm existence and undo the
///   indistinguishable zero-row answer the SQL is careful to give.
/// * **An outage is never a denial**, and a denial never reads as "not found".
///   Those two live in `SrFailureView`, which this feature reuses rather than
///   rewording.
abstract final class VendorRetailerCopy {
  // -- the directory ---------------------------------------------------------

  static const String listTitle = 'Retailers';

  static const String listDescription =
      'Every Retailer connected to your Vendor organization, with the shops '
      'each one operates. Open a Retailer to see its details and shops.';

  static const String searchLabel = 'Search Retailers';
  static const String searchPlaceholder = 'Search by Retailer name';
  static const String searchHint =
      'Filters the Retailers already loaded. Nothing is sent to the server.';

  static const String filterLabel = 'Relationship status';
  static const String filterAll = 'All';

  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';
  static const String clearFilters = 'Clear filters';

  static const String loadingList = 'Loading Retailers';

  static const String emptyTitle = 'No Retailers yet';
  static const String emptyBody =
      'Retailers appear here once your organization has onboarded them. '
      'Onboarding is done from the web admin.';

  static const String noMatchesTitle = 'No Retailers match';
  static const String noMatchesBody =
      'No loaded Retailer matches the current search or status filter.';

  static const String staleListTitle = 'This list may be out of date';
  static const String staleListBody =
      'We could not refresh your Retailers just now.';

  static const String openDetails = 'View details';

  // -- one Retailer ----------------------------------------------------------

  static const String detailEyebrow = 'Retailer';
  static const String backToList = 'Back to Retailers';
  static const String loadingDetail = 'Loading Retailer';

  static const String overviewTitle = 'Overview';

  static const String relationshipStatusLabel = 'Relationship status';
  static const String retailerStatusLabel = 'Retailer status';
  static const String ownerLabel = 'Owner';
  static const String countryLabel = 'Country';
  static const String currencyLabel = 'Default currency';
  static const String shopsLabel = 'Shops';
  static const String onboardedLabel = 'Onboarded';

  /// The single wording for every relationship this caller cannot address.
  static const String detailNotFoundTitle = 'Retailer not available';

  /// Deliberately says nothing about whether the Retailer exists, and offers no
  /// retry — the backend already answered, and it will answer the same way.
  static const String detailNotFoundBody =
      'This Retailer is not available to your account. The link may be out of '
      'date, or the Retailer may no longer be connected to your organization.';

  /// Shown when a lifecycle write committed but the canonical re-read did not
  /// succeed.
  ///
  /// Deliberately never worded as a failed change: the transaction committed,
  /// and only this client's picture of it is stale. It offers another **read**,
  /// never another write.
  static const String staleDetailTitle = 'These details may be out of date';
  static const String staleDetailBody =
      'The change was submitted, but this Retailer could not be re-read. The '
      'statuses above may not reflect it yet.';
  static const String reloadDetail = 'Reload Retailer';

  // -- the shop section ------------------------------------------------------

  static const String shopsSectionTitle = 'Shops';

  static const String shopsEmptyTitle = 'No shops yet';
  static const String shopsEmptyBody =
      'This Retailer has not recorded any shops. Shops are created by the '
      'Retailer from their own portal.';

  static const String shopsUnavailableTitle = 'Shops could not be loaded';

  /// Reason-free on purpose: the only thing that can produce it is a backend
  /// error whose detail must not reach a client.
  static const String shopsUnavailableBody =
      'The Retailer details above are up to date. Only the shop list could not '
      'be loaded.';

  static const String retryShops = 'Try again';

  static const String shopCodeLabel = 'Code';
  static const String shopCityLabel = 'City';
  static const String shopCountryLabel = 'Country';
}
