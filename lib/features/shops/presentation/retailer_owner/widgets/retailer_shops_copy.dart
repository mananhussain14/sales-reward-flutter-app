/// Every string the Retailer Shops screen renders.
///
/// Centralised for one reason above all: **no copy on this screen may be derived
/// from a backend response.** Each string is a fixed literal, so a Postgres
/// message, a SQLSTATE, a stack trace or a UUID cannot reach the screen through
/// any of them — the only interpolated values anywhere in this feature are the
/// shop's own name, code and city, which are the display fields the contract
/// exists to return.
abstract final class RetailerShopsCopy {
  static const String title = 'Shops';
  static const String description =
      'The trading locations recorded for your organization.';

  static const String loading = 'Loading your shops…';
  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';

  // -- search ---------------------------------------------------------------

  static const String searchLabel = 'Search shops';
  static const String searchPlaceholder = 'Name, code or city';

  /// States the coverage in words, because the contract returns only five
  /// columns and a user must not conclude a shop is missing when it is merely
  /// unmatched.
  static const String searchHint =
      'Filters the shops already loaded, by name, code or city.';

  static const String searchEmptyTitle = 'No shops match that search';
  static const String searchEmptyBody =
      'Clear the search to see every shop again.';

  // -- empty ----------------------------------------------------------------

  static const String emptyTitle = 'No shops recorded yet';

  /// Deliberately does **not** say "you have no shops" as a statement of fact
  /// about permissions. The contract returns an empty list both for a Retailer
  /// with no shops and for a caller its resolver refused, and the client cannot
  /// tell those apart — so the copy describes what is on screen and points at a
  /// person, rather than asserting a cause.
  static const String emptyBody =
      'Shops are added by SalesReward when your organization is set up. If you '
      'expect to see shops here, contact whoever manages your SalesReward '
      'access.';

  // -- read-only framing ----------------------------------------------------

  /// The screen is a list and nothing else. Saying so is better than a user
  /// tapping a row and wondering why nothing happened.
  static const String readOnlyNote =
      'This list is read-only. Shop details, adding a shop and changing a '
      'shop are not available in the app.';

  static const String staleTitle = 'Showing the last loaded shops';
  static const String staleBody =
      'The most recent refresh did not complete, so this list may be out of '
      'date. Try refreshing again.';

  // -- field labels ---------------------------------------------------------

  static const String codeLabel = 'Code';
  static const String cityLabel = 'City';
  static const String countryLabel = 'Country';

  /// The count caption, e.g. "Showing 3 of 12".
  static String showing(int visible, int total) =>
      visible == total ? '$total shops' : 'Showing $visible of $total';
}
