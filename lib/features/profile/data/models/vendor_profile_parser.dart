import '../../domain/entities/vendor_administrator_profile.dart';

/// A Vendor administrator profile response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and on an identity surface the only safe guess is none. The repository turns
/// it into an operational failure — **never** into a profile with a placeholder
/// name, never into a partially populated profile, never into an empty role list,
/// and never into access denied.
///
/// The load-bearing case is the name. A parser that substituted a default for a
/// field it could not read would put a name on screen that the backend never
/// sent, above a role list it did — and a profile screen is a claim about **who
/// the signed-in person is**.
final class VendorProfileFormatException implements Exception {
  const VendorProfileFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carrying a value read from the response.
  final String reason;

  @override
  String toString() => 'VendorProfileFormatException: $reason';
}

/// Parses `get_my_vendor_profile()`.
///
/// ## Exactly one row, and the count is checked rather than assumed
///
/// An authorized caller always receives exactly one row — structurally, because
/// `organization_members` is UNIQUE on `(organization_id, user_id)` (so the two
/// predicates match at most one row) and the Vendor was itself derived by joining
/// through that very membership (so they match at least one). Zero rows and two
/// rows are therefore both impossible against the deployed contract, which is
/// precisely why both are **rejected** here instead of being tolerated: either
/// one means this build and the deployed function disagree, and the honest
/// response to that is an outage the user can retry past.
///
/// Taking "the first row" of a two-row answer would render an identity whose
/// provenance this build cannot explain. Treating zero rows as an empty profile
/// would be worse still: a denial is raised as an exception by the backend and is
/// **never** zero rows, so a client that rendered a blank profile for an empty
/// body could show a profile screen for an identity the caller does not hold.
///
/// ## Nothing here is composed, derived or inferred
///
/// The display name arrives already composed and is taken verbatim. The role
/// array arrives already filtered to ACTIVE definitions and already ordered, and
/// is taken verbatim. No name part is joined, no role code is derived, no
/// permission is inferred, and no organization name is looked for — the contract
/// returns none, and this parser has nowhere to put one.
abstract final class VendorProfileParser {
  /// The single profile row.
  ///
  /// The body is a JSON **array** — PostgREST renders a set-returning function as
  /// one — carrying exactly one object of two fields.
  static VendorAdministratorProfile parse(Object? raw) {
    if (raw is! List) {
      throw const VendorProfileFormatException('profile is not a list');
    }
    if (raw.length != 1) {
      // Both directions are the same statement: the contract guarantees one row
      // for an authorized caller, so anything else is a contract mismatch rather
      // than a state to render.
      throw VendorProfileFormatException(
        'profile must carry exactly one row, not ${raw.length}',
      );
    }

    final Object? first = raw.single;
    if (first is! Map) {
      throw const VendorProfileFormatException('profile row is not an object');
    }
    final Map<String, Object?> row = first.map<String, Object?>(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );

    // Both fields are read before anything is constructed, so a malformed role
    // array fails the whole profile rather than leaving a real name rendered
    // beside a fabricated role list — or the reverse. There is no partial
    // profile to emit.
    final String displayName = _requiredString(
      row['administrator_display_name'],
      'profile.administrator_display_name',
    );
    final List<String> roleNames = _roleNames(
      row['administrator_role_names'],
      'profile.administrator_role_names',
    );

    return VendorAdministratorProfile(
      displayName: displayName,
      roleNames: roleNames,
      // No organization name, no organization id, no profile id, no membership
      // id, no auth user id, no email, no mobile number, no status, no timestamp,
      // no role code and no permission code — the contract returns none of them,
      // and there is nowhere here to put one.
    );
  }
}

// ---------------------------------------------------------------------------
// Strict field readers
//
// Every one of these throws rather than substituting a default. A default here
// would be a value the backend never sent, presented as though it had — which is
// how an unreadable response becomes a fabricated identity.
// ---------------------------------------------------------------------------

/// A `text NOT NULL` column that the schema also guarantees is non-blank.
///
/// Rejects absent, `null`, a non-string, an empty string and a whitespace-only
/// string alike. All five mean the same thing — this is not the response this
/// build was written against — and none of them is a name.
///
/// The value is returned **exactly as received**. The blank check runs against a
/// trimmed copy, but nothing trimmed is ever handed on: the database composed
/// this name and its spacing is its decision, not this client's.
String _requiredString(Object? raw, String what) {
  if (raw is String && raw.trim().isNotEmpty) {
    return raw;
  }
  throw VendorProfileFormatException('$what missing or blank');
}

/// A `text[]` column that is **NOT NULL and may be empty**.
///
/// Three failures and one legitimate answer:
///
/// * `null` → **format error.** The SQL coalesces the aggregate to `'{}'`, so a
///   null array is not "no roles" — it is a response this build was not written
///   against. Reading it as "no roles" would be a guess.
/// * not a list, or an element that is not a non-blank string → format error.
/// * `[]` → **an empty list, preserved as such.** Defensive only: the ACTIVE
///   `Vendor Super Admin` assignment that authorizes the caller is always in the
///   array, and removing it denies the read rather than emptying it. The screen
///   still renders it safely rather than crashing.
///
/// ## Order is preserved, and nothing is de-duplicated
///
/// The array arrives ordered by role name then role id. Nothing here sorts,
/// filters or de-duplicates it, and it is deliberately not converted to a `Set`:
/// that would change the order, and `public.roles` constrains `code` to be unique
/// but **not** `name`, so two distinct ACTIVE definitions sharing a display name
/// is a legal database state rather than a malformed response. Rejecting or
/// collapsing a repeat would therefore refuse a real answer — and would hide a
/// genuine backend duplication bug rather than prevent one.
List<String> _roleNames(Object? raw, String what) {
  if (raw is! List) {
    throw VendorProfileFormatException('$what is not an array');
  }
  return raw
      .map<String>((Object? element) => _requiredString(element, '$what entry'))
      .toList(growable: false);
}
