/// How far a Retailer's owner has got, as one word.
///
/// The five values `public.vendor_retailer_owner_state(uuid)` can return, in the
/// precedence the migration documents:
///
/// | State | Condition |
/// | --- | --- |
/// | `ACTIVE` | An `ACTIVE` membership holding an `ACTIVE` `RETAILER_OWNER` role. Wins outright over any invitation history |
/// | `PENDING` | Else: the newest unexpired `PENDING` invitation whose flow's completion proof exists |
/// | `DELIVERY_FAILED` | Else: that same invitation without its completion proof |
/// | `EXPIRED` | Else: any `EXPIRED` invitation, or a `PENDING` one past `expires_at` |
/// | `NONE` | Else. Revoked and settled history land here |
///
/// ## This is a badge, and it is all this milestone gets
///
/// The deployed reads return the **state word and nothing else** — no recipient
/// name, no email, no `sent_at` / `expires_at` / `accepted_at`, no failure
/// classification, and no invitation id, token or hash. Those live only in
/// `get_vendor_retailer_owner_status(uuid)`, which this milestone deliberately
/// does not call: an owner card is an invitation feature, and invitations are
/// out of scope here.
///
/// ## Why [unknown] can never read as "done"
///
/// A token this build does not recognise degrades to [unknown] rather than
/// failing the read, exactly as a status does. But [hasActiveOwner] tests
/// [active] positively, so an unrecognised future word cannot be mistaken for a
/// completed or accepted owner — it renders neutrally and claims nothing.
enum RetailerOwnerState {
  /// The Retailer has a live owner.
  active('ACTIVE'),

  /// An invitation is out and was genuinely dispatched.
  pending('PENDING'),

  /// An invitation row exists but was reserved and never delivered.
  deliveryFailed('DELIVERY_FAILED'),

  /// An invitation ran out of time.
  expired('EXPIRED'),

  /// No owner and no invitation state worth showing.
  none('NONE'),

  /// A value this build does not know. Displayed neutrally, and nothing more.
  unknown('');

  const RetailerOwnerState(this.code);

  /// The backend token, or the empty string for [unknown].
  final String code;

  /// Maps a backend token to a state, falling back to [unknown].
  static RetailerOwnerState fromCode(String raw) {
    for (final RetailerOwnerState state in values) {
      if (state != unknown && state.code == raw) {
        return state;
      }
    }
    return unknown;
  }

  /// Whether this Retailer definitely has a live owner.
  ///
  /// Positive test against [active] alone. [unknown], [none], [expired],
  /// [pending] and [deliveryFailed] all answer false, so no future token can
  /// arrive at "owned" by elimination.
  bool get hasActiveOwner => this == active;

  /// Whether a Vendor would want to look at this Retailer's owner situation.
  ///
  /// Presentation only — it gates no action, because this milestone offers
  /// none. [unknown] answers false: an unrecognised word is not evidence of a
  /// problem any more than it is evidence of success.
  bool get needsAttention =>
      this == none ||
      this == expired ||
      this == deliveryFailed ||
      this == pending;
}
