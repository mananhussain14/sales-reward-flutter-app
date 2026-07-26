/// Who the backend was able to attribute an audit event to.
///
/// The deployed `public.list_vendor_audit_logs(...)` returns exactly one of
/// `USER`, `SYSTEM` or `UNKNOWN` in `actor_type`, and the migration's own
/// expression is the whole of the rule:
///
/// ```sql
/// case when a.actor_profile_id is null then 'SYSTEM'
///      when actor.first_name    is null then 'UNKNOWN'
///      else                                  'USER'  end
/// ```
///
/// The join that resolves `actor` is scoped to a membership **in the audit
/// row's own Vendor organization**. That scope is a privacy boundary rather than
/// an optimisation: the function is `SECURITY DEFINER`, so an unscoped join to
/// `public.profiles` would bypass that table's RLS policy and could print a
/// person from another organization onto a Vendor's audit screen.
///
/// ## The three states are not three degrees of the same thing
///
/// They answer different questions, and the wording on screen keeps them apart:
///
/// * [user] — a profile was resolved through a membership of this Vendor. The
///   name is the only name the caller is entitled to see. A **suspended**
///   profile and a **deactivated** membership both still resolve here on
///   purpose: a suspended person's past actions are precisely the history an
///   operator reviews *after* suspending them, and demanding `ACTIVE` would
///   rewrite history as a side effect of an unrelated administrative act.
/// * [unknown] — an actor id is still on the row, but it resolves to no
///   membership of this Vendor. Two distinct database states reach it: an actor
///   who belongs to another Vendor, and an actor with no membership at all.
///   Neither may be described further, because describing them is exactly the
///   cross-tenant disclosure the scoped join exists to prevent.
/// * [system] — **no actor identity remains.** See below.
///
/// ## [system] does not prove that a system process acted
///
/// This is the one genuinely ambiguous value in the contract, and the backend
/// audit states it as a limitation rather than smoothing it over.
/// `public.profiles.id REFERENCES auth.users ON DELETE CASCADE`, and
/// `audit_logs.actor_profile_id REFERENCES profiles ON DELETE SET NULL`. So two
/// different histories produce a byte-identical row:
///
/// 1. the event was written with no actor from the beginning, and
/// 2. the event's actor was a real person whose auth user was later deleted,
///    nulling the audit row's actor while leaving the audit row intact.
///
/// The function cannot tell them apart, and neither can the schema. Verified
/// directly against the database by the backend milestone: a row reading
/// `USER` / a real name became `SYSTEM` / null after the auth user was deleted.
///
/// No application code path deletes a profile, but the Supabase Admin API and
/// the Studio user list both expose auth-user deletion to an operator, so the
/// state is reachable in operation.
///
/// **Therefore [system] must be read as "no actor identity remains".** The
/// presentation layer words it *"System or unavailable actor"*, never a bare
/// "System", never "Automated system", never "Deleted user" and never "Former
/// user" — each of those is a claim about *who acted* that the evidence cannot
/// support, and an audit surface is the last place to state something stronger
/// than the evidence.
///
/// ## Why [unrecognized] exists, and what it may never do
///
/// A token this build does not know means the backend is newer than the app.
/// The row still renders, because a history that hid the events its reader did
/// not recognise would be worse than useless on exactly the day it mattered.
///
/// It is **never** silently folded into [user], [system] or [unknown]: each of
/// those is a specific claim, and asserting one of them about a value whose
/// meaning is unknown would be inventing an attribution. It carries no name and
/// none is fabricated for it.
enum VendorAuditActorType {
  /// A profile resolved through a membership of this Vendor organization.
  /// `actor_display_name` is non-null for this member and only this member.
  user('USER'),

  /// No actor identity remains. Not proof that a system process acted.
  system('SYSTEM'),

  /// An actor id is present but resolves to no membership of this Vendor.
  unknown('UNKNOWN'),

  /// A token this build does not know. Rendered neutrally, and nothing more.
  unrecognized('');

  const VendorAuditActorType(this.code);

  /// The backend token, or the empty string for [unrecognized].
  final String code;

  /// Maps a backend token to an actor type, falling back to [unrecognized].
  ///
  /// Never throws: the parser has already established that a non-blank string
  /// is present, and an unfamiliar value is a forward-compatibility case rather
  /// than a malformed response.
  static VendorAuditActorType fromCode(String raw) {
    for (final VendorAuditActorType type in values) {
      if (type != unrecognized && type.code == raw) {
        return type;
      }
    }
    return unrecognized;
  }

  /// Whether this is the one state that carries a name.
  ///
  /// Deliberately a positive test against a single member rather than a
  /// negation, so a future token can never arrive at "this has a name" by
  /// failing to match something else.
  bool get carriesName => this == user;
}
