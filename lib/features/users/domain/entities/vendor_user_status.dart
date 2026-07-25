/// A lifecycle status returned by the Vendor User reads.
///
/// One enum for **both** status columns, because the deployed schema gives them
/// the same closed set:
///
/// * `profiles_status_allowed` — `profile_status`
/// * `organization_members_status_allowed` — `membership_status`
///
/// both of which are
/// `check (status in ('INVITED', 'ACTIVE', 'SUSPENDED', 'DEACTIVATED'))`. Two
/// enums with identical members would be two places to add a future value and
/// only one of them would be right.
///
/// > A person's **profile** status and their **membership** status in this
/// > Vendor are still two separate facts about two separate rows, and the
/// > backend is explicit that they are independent. Sharing a vocabulary does
/// > not make them the same value, and the screens render them as two badges for
/// > exactly that reason.
///
/// ## [invited] is a status, not an invitation
///
/// There is no Vendor user invitation table anywhere in the schema — both
/// invitation tables are asserted Retailer-scoped, and nothing invites a person
/// into a VENDOR organization. So a Vendor user who has not yet joined is not an
/// invitation row to be listed, resent or cancelled: they are an ordinary
/// membership carrying `INVITED`. Modelling it as anything else would be a
/// promise about a table that does not exist.
///
/// ## Why [unknown] exists, and what it may never do
///
/// A token this build does not recognise means the backend is newer than the
/// app. That is an additive change, so it degrades to [unknown] and renders as a
/// neutral "Unknown" badge rather than failing the read or — worse — dropping
/// the person from the directory. A Vendor must not lose sight of a user because
/// their status is unfamiliar.
///
/// [unknown] is **never** [active]: it enables nothing, it is never counted as
/// an active user, and it never carries the raw backend token to the screen. A
/// **missing or blank** status is a different thing entirely — a required value
/// the response did not supply — and the parser raises a format error for it.
enum VendorUserStatus {
  /// Recorded, but not yet joined. `joined_at` is typically null alongside it.
  invited('INVITED'),

  /// Live.
  active('ACTIVE'),

  /// Temporarily halted. Still listed, and still openable — the detail screen is
  /// where a Vendor goes to understand a state.
  suspended('SUSPENDED'),

  /// Ended. Listed rather than hidden, for the same reason.
  deactivated('DEACTIVATED'),

  /// A value this build does not know. Displayed neutrally, and nothing more.
  unknown('');

  const VendorUserStatus(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token to a status, falling back to [unknown].
  ///
  /// Never throws: the caller has already established that a status string is
  /// present, and an unrecognised value is a forward-compatibility case rather
  /// than a malformed response.
  static VendorUserStatus fromCode(String raw) {
    for (final VendorUserStatus status in values) {
      if (status != unknown && status.code == raw) {
        return status;
      }
    }
    return unknown;
  }

  /// Whether this is the one status that means "active".
  ///
  /// Deliberately a positive test against a single member rather than
  /// `!= deactivated`, so a future token can never arrive at "active" by failing
  /// to match something else.
  bool get isActive => this == active;

  /// Whether this person has been recorded but has not joined.
  bool get isInvited => this == invited;
}
