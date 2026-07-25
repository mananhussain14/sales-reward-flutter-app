/// A lifecycle status returned by the Vendor Retailer reads.
///
/// One enum for **three** columns, because the deployed schema gives all three
/// the same closed set:
///
/// * `organizations_status_allowed` — `retailer_status`
/// * `vendor_retailers_status_allowed` — `relationship_status`
/// * `retailer_shops_status_allowed` — `shop_status`
///
/// all of which are `check (status in ('ACTIVE', 'SUSPENDED', 'DEACTIVATED'))`.
/// Three enums with identical members would be three places to add a future
/// value and only one of them would be right.
///
/// > A Retailer's status and this Vendor's *relationship* status are still two
/// > separate facts about two separate rows. Sharing a vocabulary does not make
/// > them the same value, and the screens render them as two badges for exactly
/// > that reason.
///
/// ## Why [unknown] exists, and what it may never do
///
/// A token this build does not recognise means the backend is newer than the
/// app. That is an additive change, so it degrades to [unknown] and renders as a
/// neutral "Unknown" badge rather than failing the whole read.
///
/// [unknown] is **never** [active]: it unlocks nothing, it is never counted as
/// an active shop, and it never carries the raw backend token to the screen. A
/// **missing or blank** status is a different thing entirely — a required value
/// the response did not supply — and the parser raises a format error for it.
enum VendorRetailerStatus {
  /// Trading normally.
  active('ACTIVE'),

  /// Temporarily halted. Still listed, and still readable.
  suspended('SUSPENDED'),

  /// Ended. Listed rather than hidden, because hiding it would make ending a
  /// relationship look like deleting one.
  deactivated('DEACTIVATED'),

  /// A value this build does not know. Displayed neutrally, and nothing more.
  unknown('');

  const VendorRetailerStatus(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token to a status, falling back to [unknown].
  ///
  /// Never throws: the caller has already established that a status string is
  /// present, and an unrecognised value is a forward-compatibility case rather
  /// than a malformed response.
  static VendorRetailerStatus fromCode(String raw) {
    for (final VendorRetailerStatus status in values) {
      if (status != unknown && status.code == raw) {
        return status;
      }
    }
    return unknown;
  }

  /// Whether this is the one status that means "active".
  ///
  /// Deliberately a positive test against a single member rather than
  /// `!= deactivated`, so a future token can never arrive at "active" by
  /// failing to match something else.
  bool get isActive => this == active;
}
