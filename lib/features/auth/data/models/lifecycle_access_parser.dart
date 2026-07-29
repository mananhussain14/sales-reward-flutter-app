import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/lifecycle_access_state.dart';

/// The only place in this application that knows the backend's wire codes.
///
/// Keeping them here — private, in one const map — is what makes it impossible
/// for a widget to render `ORGANIZATION_INACTIVE` on a screen. There is no
/// accessor, no reverse lookup and no `code` field on
/// [LifecycleAccessState]: the strings enter here and are converted, and no
/// path carries them back out.
///
/// The keys are the exact words the migration returns. They are matched
/// literally — see [LifecycleAccessParser.parse] for why nothing is normalized.
const Map<String, LifecycleAccessState> _supportedStates =
    <String, LifecycleAccessState>{
      'ACTIVE': LifecycleAccessState.active,
      'ORGANIZATION_INACTIVE': LifecycleAccessState.organizationInactive,
      'MEMBERSHIP_INACTIVE': LifecycleAccessState.membershipInactive,
      'PROFILE_INACTIVE': LifecycleAccessState.profileInactive,
      'NO_SUPPORTED_ACCESS': LifecycleAccessState.noSupportedAccess,
      'AMBIGUOUS': LifecycleAccessState.ambiguous,
    };

/// Reads `public.get_my_lifecycle_access_state()`'s single word.
///
/// ## The contract being parsed
///
/// PostgREST renders a `returns table (access_state text)` function as a JSON
/// array of row objects. The function returns **exactly one row on every
/// non-throwing path** — every branch in the migration is a single
/// `return query select '<CODE>'::text; return;` — so "a list of one map with an
/// `access_state` string" is not a lenient guess about the shape, it is the
/// shape.
///
/// ## Why this is stricter than the Web client, deliberately
///
/// The deployed Web parser (`lib/staff/my-lifecycle-access-state.ts`) does:
///
/// ```ts
/// const row = Array.isArray(data) ? data[0] : data;
/// ```
///
/// which accepts a non-array root and silently ignores extra rows. Both
/// implementations agree on every response the deployed function can actually
/// produce, so this is not a contract disagreement — it is hardening, and the
/// Web version is **not** the reference implementation for this file.
///
/// The reason to be stricter here is that a body which is not the documented
/// shape is evidence that something upstream is not what this build thinks it
/// is: a changed contract, a proxy, an error envelope, a different function. On
/// a screen whose whole job is to explain a refusal honestly, the safe response
/// to "I do not recognize this" is to say no more than the refusal already does
/// — which is exactly what a thrown [RpcFormatException] produces, because the
/// repository turns it into `LifecycleAccessUnavailable` and the page renders
/// the ordinary access-denied card.
///
/// Nobody should later "align" this with the Web parser. If the two must
/// converge, the Web one is the one to tighten.
///
/// ## Nothing is normalized, and that is the rule
///
/// There is no `trim()`, no `toUpperCase()`, no `??` fallback and no default
/// branch anywhere below. The value the backend sent goes into the map lookup
/// exactly as received, so `' ACTIVE '`, `'active'`, `'Active'` and `'ACTIVE\n'`
/// are all rejected rather than repaired.
///
/// Repairing them would be guessing at intent, and the guess has a cost: a
/// build that accepted `'active'` would also accept whatever a future migration
/// renamed it to, and would render "your Retailer is inactive" on the strength
/// of a word it had quietly rewritten. An unrecognized value — including one
/// from a migration this build predates — is treated as unknown and falls back
/// to the ordinary denial.
abstract final class LifecycleAccessParser {
  /// Parses [raw] into one [LifecycleAccessState].
  ///
  /// Throws [RpcFormatException] for every body that is not exactly the
  /// documented shape carrying exactly one of the six supported words. Extra
  /// keys on the row are ignored, so a future migration adding a column does not
  /// break this build.
  static LifecycleAccessState parse(Object? raw) {
    // Rules 1 and 3: the root must be a List, and each element must be a Map.
    // `asRows` refuses a null, scalar or map root, which is why there is no
    // separate check for those here.
    final List<Map<String, Object?>> rows = RpcRow.asRows(
      raw,
      'lifecycle access state',
    );

    // Rule 2. Zero rows and two rows are equally wrong: the function cannot
    // produce either, so both mean the body is not this contract. Refusing an
    // empty list matters most — reading `rows.first` on one would throw a
    // StateError that no caller is catching, and defaulting it to a state would
    // invent an answer the backend never gave.
    if (rows.length != 1) {
      throw const RpcFormatException(
        'lifecycle access state is not exactly one row',
      );
    }

    final Map<String, Object?> row = rows.first;

    // Rule 4. Checked separately from the type test below so that "the column
    // is missing" and "the column is null" stay distinguishable in the reason,
    // which is developer-facing only and never rendered.
    if (!row.containsKey('access_state')) {
      throw const RpcFormatException('access_state is missing');
    }

    final Object? value = row['access_state'];

    // Rule 5. Deliberately NOT RpcRow.requiredString: that helper rejects a
    // blank value with its own reason, and this column has a stricter rule than
    // "non-blank" anyway. A number, a bool, a list, a map and null all land
    // here.
    if (value is! String) {
      throw const RpcFormatException('access_state is not a text');
    }

    // Rules 6 to 9. The literal lookup IS the whole vocabulary check. Blank,
    // whitespace-only, wrong-case, padded and unknown values all miss the map
    // and are refused identically — there is no branch that could treat one of
    // them more kindly than another.
    final LifecycleAccessState? state = _supportedStates[value];
    if (state == null) {
      throw const RpcFormatException(
        'access_state is not a supported lifecycle state',
      );
    }

    // Rule 10: extra keys were never read, so a wider row passes untouched.
    return state;
  }
}
