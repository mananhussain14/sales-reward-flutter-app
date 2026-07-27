/// Every string the Retailer assigned-products screen renders.
///
/// Centralised for one reason above all: **no copy on this screen may be derived
/// from a backend response.** Each string is a fixed literal, so a Postgres
/// message, a SQLSTATE, a stack trace, a UUID or an internal enum token cannot
/// reach the screen through any of them. The only interpolated values are the
/// product's own name, code, brand, barcode and description.
abstract final class RetailerProductsCopy {
  static const String title = 'Products';

  /// Worded around **currently**, because that is exactly what the contract
  /// returns: rows whose assignment and product are both `ACTIVE` right now.
  static const String description =
      'The products currently assigned to your organization.';

  static const String loading = 'Loading your products…';
  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';

  // -- search ---------------------------------------------------------------

  static const String searchLabel = 'Search products';
  static const String searchPlaceholder = 'Name, code, brand or barcode';
  static const String searchHint =
      'Filters the products already loaded, by name, code, brand or barcode.';

  static const String searchEmptyTitle = 'No products match that search';
  static const String searchEmptyBody =
      'Clear the search to see every product again.';

  // -- empty ----------------------------------------------------------------

  static const String emptyTitle = 'No products assigned yet';

  /// Says who assigns products without asserting anything about permissions —
  /// an empty catalogue is a commercial fact, not an access outcome.
  static const String emptyBody =
      'Products appear here when a Vendor assigns them to your organization.';

  // -- read-only framing ----------------------------------------------------

  /// Two facts a user would otherwise get wrong, stated once.
  ///
  /// The first is scope: this is what is assigned **now**, and no withdrawn
  /// assignment is retrievable — the backend returns only active rows and offers
  /// no history read, so the app must not imply one exists behind a filter.
  ///
  /// The second is agency: a Retailer cannot change these. Assignment is a
  /// Vendor capability on a different permission entirely.
  static const String readOnlyNote =
      'This list shows what is assigned right now. Products are assigned and '
      'withdrawn by the Vendor, and past assignments are not shown.';

  static const String staleTitle = 'Showing the last loaded products';
  static const String staleBody =
      'The most recent refresh did not complete, so this list may be out of '
      'date. Try refreshing again.';

  // -- field labels ---------------------------------------------------------

  static const String codeLabel = 'Code';
  static const String brandLabel = 'Brand';
  static const String barcodeLabel = 'Barcode';

  static String showing(int visible, int total) =>
      visible == total ? '$total products' : 'Showing $visible of $total';
}
