/// A membership status a Retailer Owner may **request**.
///
/// Two members, because `public.set_retailer_staff_membership_status(uuid, text)`
/// compares `p_status` **exactly and case-sensitively** against
/// `('ACTIVE', 'DEACTIVATED')` and raises `23514` for anything else — including
/// `'active'`, `' ACTIVE'`, `''` and null. The function performs no `upper()` and
/// no `btrim()`, so the token this enum carries is written verbatim into a
/// `CHECK`-constrained column and into an audit row a human reads later.
///
/// ## This is deliberately not [RetailerMemberStatus]
///
/// That enum is the **response** vocabulary for the roster and has five members:
/// it carries `invited` and `suspended`, which are legal values of
/// `organization_members.status` and are deliberately **not** members of this
/// operation's vocabulary in either direction, and `unknown`, whose `code` is the
/// empty string. A type that makes any of them expressible at a request boundary
/// is a type that eventually sends one.
///
/// * `INVITED` is not a state an Owner may **confer**. A membership becomes
///   `ACTIVE` by the recipient accepting their invitation, which is the only
///   place consent is recorded and the only place Shop rows are created.
/// * `SUSPENDED` is reserved for an administrative state this milestone defines
///   no owner for. Nothing here may set it, and nothing here may clear it.
///
/// So the request vocabulary and the response vocabulary are separate types, and
/// the only way to obtain a request is through
/// [RetailerStaffLifecycleAction.forStatus], from a status the backend actually
/// returned.
///
/// ## `INACTIVE` is not representable here, and that is the point
///
/// The product says **Inactive**; the database stores **DEACTIVATED**. The
/// translation is one-way and lives in `RetailerMemberStatus.label` and in
/// [RetailerStaffLifecycleAction.displayLabel]. There is no member of this enum
/// whose `code` is `'INACTIVE'`, so no amount of editing a label, a button or a
/// dialog can cause a display word to reach the RPC.
enum RetailerStaffLifecycleStatus {
  /// The membership is working normally.
  ///
  /// Shown to an Owner as **Active**.
  active('ACTIVE'),

  /// The membership is stood down. Reversible, and **not** a deletion: the
  /// profile, the Auth identity, the roles, the live and retired Shop
  /// assignments, the receipts, the invitations and the audit history all
  /// survive untouched.
  ///
  /// Shown to an Owner as **Inactive** — the word has to match the verb of the
  /// control that writes it (Deactivate / Reactivate).
  deactivated('DEACTIVATED');

  const RetailerStaffLifecycleStatus(this.code);

  /// The exact token `p_status` accepts, and the exact token the column stores.
  ///
  /// The only place in this feature outside the response enum where either
  /// literal is written, which is what keeps a status value from being assembled
  /// anywhere a screen could reach.
  final String code;

  /// Parses a backend token into the lifecycle vocabulary, or null.
  ///
  /// Null for **every** value outside the pair — including `INVITED` and
  /// `SUSPENDED`, which are legal column values this operation may neither set
  /// nor clear, and including `INACTIVE`, which is a display word no column
  /// stores. Callers must treat null as "not this operation's business", never
  /// as a default.
  static RetailerStaffLifecycleStatus? tryParse(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final RetailerStaffLifecycleStatus status in values) {
      if (status.code == value) {
        return status;
      }
    }
    return null;
  }
}
