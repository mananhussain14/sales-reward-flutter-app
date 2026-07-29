/// The closed vocabulary returned by `public.get_my_lifecycle_access_state()`.
///
/// Six words, and the SQL returns exactly these and nothing else. Each names a
/// *reason a refusal happened*, never a capability:
///
/// * [active] — exactly one supported Retailer context, and everything about it
///   is ACTIVE. No lifecycle reason explains the refusal.
/// * [profileInactive] — the caller's own profile is not ACTIVE. Nothing they do
///   at any Retailer will work until that is resolved.
/// * [membershipInactive] — their one Retailer is ACTIVE, but their membership
///   of it is not.
/// * [organizationInactive] — their one Retailer organization is not ACTIVE.
/// * [noSupportedAccess] — no supported Retailer membership context exists at
///   all, or no profile row exists.
/// * [ambiguous] — more than one qualifying Retailer context, so no single
///   lifecycle story can be told and none is invented.
///
/// ## ⚠️ This is a diagnostic. It is not an authorization gate.
///
/// [active] is **not** permission to do anything. It is a description of why the
/// real gate said no, read *after* the real gate said no. `SessionBloc` and the
/// `SECURITY DEFINER` functions behind every RPC remain the only things that
/// decide whether a request may proceed, and each re-derives its answer from
/// `auth.uid()` on every call. Nothing in this application may branch on a value
/// here to admit a request or to navigate: these choose a SENTENCE, never a
/// capability.
///
/// ## Why the wire codes are not here
///
/// The strings the database sends — `ACTIVE`, `ORGANIZATION_INACTIVE` and the
/// rest — live in exactly one place, the private map inside
/// `LifecycleAccessParser`. This enum deliberately carries no `code` field, no
/// `name` override and no `toString()` that yields one.
///
/// That is not tidiness. A widget cannot render a state code it has no way to
/// obtain, so "the access-denied screen must never display a raw backend state"
/// is enforced by the *shape of the type* rather than by a reviewer noticing an
/// interpolation. `LifecycleAccessState.active.name` still yields `'active'`, a
/// Dart identifier this codebase chose — never the backend's word.
enum LifecycleAccessState {
  active,
  organizationInactive,
  membershipInactive,
  profileInactive,
  noSupportedAccess,
  ambiguous,
}
