/// A status a caller may **request** for a Retailer relationship.
///
/// Two members, because `public.set_vendor_retailer_status(uuid, text)` compares
/// `p_status` **exactly and case-sensitively** against `('ACTIVE', 'SUSPENDED')`
/// and raises `23514` for anything else — including `'active'`, `' ACTIVE'`,
/// `''` and null. The deployed function performs no `upper()` and no `btrim()`,
/// so the token this enum carries is written verbatim into two `CHECK`-
/// constrained columns and into an audit row a human reads later.
///
/// ## This is deliberately not [VendorRetailerStatus]
///
/// That enum is the **response** vocabulary and has four members: it carries
/// `deactivated`, which is terminal and which this operation may neither set nor
/// clear, and `unknown`, the forward-compatibility case for a token a *response*
/// carried that this build does not recognise. `unknown.code` is the empty
/// string, and a type that makes it expressible at a request boundary is a type
/// that eventually sends it.
///
/// So the request vocabulary and the response vocabulary are separate types, and
/// the only way to obtain a request is through
/// [VendorRetailerLifecycleAction.forPair], from a pair of statuses the backend
/// actually returned.
///
/// ## `INACTIVE` is not representable here, and that is the point
///
/// The product says **Inactive**; the database stores **SUSPENDED**. The
/// translation is one-way and lives in
/// [VendorRetailerLifecycleAction.displayLabel]. There is no member of this enum
/// whose `code` is `'INACTIVE'`, so no amount of editing a label, a button or a
/// dialog can cause the display word to reach the RPC.
enum VendorRetailerLifecycleStatus {
  /// `organizations.status` and `vendor_retailers.status` both `ACTIVE`.
  ///
  /// Shown to a Vendor as **Active**.
  active('ACTIVE'),

  /// Both rows `SUSPENDED`. Reversible, and **not** a deletion: memberships,
  /// roles, Shops, assignments, receipts and invitations all survive untouched.
  ///
  /// Shown to a Vendor as **Inactive** — "suspended" reads as an accusation to a
  /// Retailer that is simply paused between contracts, and the control that
  /// writes this value is labelled Deactivate / Reactivate.
  suspended('SUSPENDED');

  const VendorRetailerLifecycleStatus(this.code);

  /// The exact token `p_status` accepts, and the exact token both columns store.
  ///
  /// The only place in this feature outside the response enum where either
  /// literal is written, which is what keeps a status value from being assembled
  /// anywhere a screen could reach.
  final String code;

  /// Parses a backend token into the lifecycle vocabulary, or null.
  ///
  /// Null for **every** value outside the pair — including `DEACTIVATED`, which
  /// is a legal member of both columns' `CHECK` constraints and deliberately not
  /// of this operation's vocabulary, and including `INACTIVE`, which is a
  /// display word no column stores. Callers must treat null as "not this
  /// operation's business", never as a default.
  static VendorRetailerLifecycleStatus? tryParse(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final VendorRetailerLifecycleStatus status in values) {
      if (status.code == value) {
        return status;
      }
    }
    return null;
  }
}
