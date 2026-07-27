import '../../domain/entities/retailer_owner_overview.dart';

/// A Retailer Owner overview response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and on this screen the only safe guess is none. The repository turns it into
/// [RetailerOverviewProblem.malformed] — **never** into an overview of zeros,
/// never into a partially populated overview, and never into "you are not
/// eligible".
///
/// Zero is the load-bearing case. `0` is a real, reachable answer for both shop
/// counts — a newly onboarded Retailer has no shops yet — so a parser that
/// substituted it for a field it could not read would tell an Owner "you have no
/// shops" on the strength of a response this build did not understand.
final class RetailerOwnerOverviewFormatException implements Exception {
  const RetailerOwnerOverviewFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carrying a value read from the response.
  final String reason;

  @override
  String toString() => 'RetailerOwnerOverviewFormatException: $reason';
}

/// The largest count this build will render.
///
/// `2^53 - 1`, the largest integer a JavaScript number represents exactly —
/// which is what a Dart `int` compiles to on Flutter web. A `bigint` above it
/// has already lost precision inside `JSON.parse` before any Dart code runs, so
/// no amount of care here could recover it.
///
/// A value above this is therefore **rejected as malformed rather than
/// rendered**, on every platform including the VM where it would in fact fit.
/// Two clients quietly disagreeing about the same figure is worse than one
/// honest "could not load this": a shop count is only useful if it is the same
/// number the web portal shows.
///
/// Unreachable in practice — nine quadrillion shops — and recorded as a known
/// limitation rather than left as an assumption.
const int maxSafeRetailerShopCount = 9007199254740991;

/// The outcome of parsing the overview body.
///
/// Zero rows is modelled here, in the parser's own return type, rather than as a
/// null [RetailerOwnerOverview] — so no caller can reach for `?.` and treat "you
/// are not eligible for this overview" as "the name happens to be missing".
sealed class ParsedRetailerOverview {
  const ParsedRetailerOverview();
}

/// Exactly one row was returned and it was well formed.
final class ParsedRetailerOverviewRow extends ParsedRetailerOverview {
  const ParsedRetailerOverviewRow(this.overview);

  final RetailerOwnerOverview overview;
}

/// The body was a well-formed **empty** set.
///
/// A real, successful answer, and the single one given to every ineligible
/// caller. Distinguished from a malformed body precisely because it is not one.
final class ParsedRetailerOverviewEmpty extends ParsedRetailerOverview {
  const ParsedRetailerOverviewEmpty();
}

/// Parses `get_retailer_owner_portal_context()`.
///
/// ## At most one row, and the count is checked rather than assumed
///
/// The deployed function `returns table (...)` with a `where` clause that can
/// match at most one organization, so PostgREST renders the body as a JSON
/// **array** of zero or one object.
///
/// * **one row** → [ParsedRetailerOverviewRow].
/// * **zero rows** → [ParsedRetailerOverviewEmpty]. Successful and meaningful.
/// * **two or more** → rejected. It is impossible against the deployed contract,
///   so it means this build and the backend disagree; taking "the first row"
///   would render figures whose provenance this build cannot explain, and which
///   organization they described would be a coin toss.
///
/// ## Which malformations are rejected, and which are tolerated
///
/// Rejected, because guessing would state something false:
///
/// * a body that is not a list, or a row that is not an object;
/// * a missing, null, blank or non-string `retailer_name`;
/// * a missing, null, blank or non-string status on either field;
/// * a missing, null or non-integer count on either field;
/// * a negative count — `count(*)` cannot be negative, so a negative value is
///   evidence this is not the response this build expects, and clamping it to
///   zero would state a fact the backend never sent;
/// * `active_shop_count > total_shop_count` — the active set is a **subset** of
///   the total by construction (`status = 'ACTIVE'` narrows the same predicate),
///   so this pair cannot both be true and cannot be repaired by picking one.
///
/// Tolerated, because the contract is explicitly additive or genuinely nullable:
///
/// * an **unrecognized extra key** → ignored. A new key must not break an old
///   client.
/// * an **unrecognized status token** → [RetailerLifecycleStatus.unknown] /
///   [RetailerMembershipStatus.unknown]. A newer backend adding a lifecycle
///   value is additive; it is displayed neutrally and unlocks nothing.
/// * a **null `country_code` or `default_currency`** → null. Both columns are
///   nullable in the schema, so null is a real answer meaning "not recorded" and
///   is never defaulted to a country or a currency.
abstract final class RetailerOwnerOverviewParser {
  /// The overview row, or the well-formed empty answer.
  static ParsedRetailerOverview parse(Object? raw) {
    if (raw is! List) {
      throw const RetailerOwnerOverviewFormatException(
        'overview is not a list',
      );
    }
    if (raw.isEmpty) {
      // The one answer given to every ineligible caller. Not an error.
      return const ParsedRetailerOverviewEmpty();
    }
    if (raw.length > 1) {
      throw RetailerOwnerOverviewFormatException(
        'overview must carry at most one row, not ${raw.length}',
      );
    }

    final Object? first = raw.single;
    if (first is! Map) {
      throw const RetailerOwnerOverviewFormatException(
        'overview row is not an object',
      );
    }
    final Map<String, Object?> row = first.map<String, Object?>(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );

    // Every field is read before anything is constructed, so a malformed
    // seventh field fails the whole overview rather than leaving six rendered
    // beside a fabricated one. The seven values are one snapshot; there is no
    // partial overview to emit.
    final String retailerName = _requiredString(
      row['retailer_name'],
      'retailer_name',
    );
    final RetailerLifecycleStatus retailerStatus =
        RetailerLifecycleStatus.fromCode(
          _requiredString(row['retailer_status'], 'retailer_status'),
        );
    final String? countryCode = _optionalCode(
      row['country_code'],
      'country_code',
    );
    final String? defaultCurrency = _optionalCode(
      row['default_currency'],
      'default_currency',
    );
    final RetailerMembershipStatus membershipStatus =
        RetailerMembershipStatus.fromCode(
          _requiredString(row['membership_status'], 'membership_status'),
        );
    final int totalShopCount = _requiredCount(
      row['total_shop_count'],
      'total_shop_count',
    );
    final int activeShopCount = _requiredCount(
      row['active_shop_count'],
      'active_shop_count',
    );

    // The one cross-field rule. Checked here rather than in the entity because
    // an entity that can be constructed in an impossible state is one a future
    // caller will construct in an impossible state.
    if (activeShopCount > totalShopCount) {
      throw const RetailerOwnerOverviewFormatException(
        'active_shop_count exceeds total_shop_count',
      );
    }

    return ParsedRetailerOverviewRow(
      RetailerOwnerOverview(
        retailerName: retailerName,
        retailerStatus: retailerStatus,
        countryCode: countryCode,
        defaultCurrency: defaultCurrency,
        membershipStatus: membershipStatus,
        totalShopCount: totalShopCount,
        activeShopCount: activeShopCount,
        // No organization id, membership id, profile id, role code, permission
        // code or timestamp — the contract returns none of them, and there is
        // nowhere here to put one.
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The strict field readers
//
// They throw rather than substituting a default. A default here would be a value
// the backend never sent, presented as though it had — which on this screen is
// how a missing name becomes a blank organization and a malformed count becomes
// "you have no shops".
// ---------------------------------------------------------------------------

/// A `text` column that is `NOT NULL` in the contract.
///
/// Blank is refused along with null: `organizations_name_not_empty` guarantees a
/// non-empty name, so an empty string is evidence the response is not this
/// shape. Rendering one would produce a page titled with nothing.
String _requiredString(Object? raw, String what) {
  if (raw is! String) {
    throw RetailerOwnerOverviewFormatException(
      '$what is missing or not a text',
    );
  }
  if (raw.trim().isEmpty) {
    throw RetailerOwnerOverviewFormatException('$what is blank');
  }
  return raw;
}

/// A nullable `text` code column — `country_code` and `default_currency`.
///
/// Null is a **real answer** and passes through untouched: both columns are
/// nullable in the schema and neither has a defensible default. A present value
/// must still be a non-blank string; a number or a boolean here means the
/// response is not this shape.
///
/// The schema's own length rules (`char_length = 2` and `= 3`) are deliberately
/// **not** re-asserted. They are enforced by check constraints at write time, so
/// re-checking them here would refuse to display a value the database has
/// already accepted — turning a future four-character currency code into a blank
/// overview instead of a slightly unfamiliar label.
String? _optionalCode(Object? raw, String what) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw RetailerOwnerOverviewFormatException('$what is not a text');
  }
  final String trimmed = raw.trim();
  // A column that is present but empty is treated as "not recorded" rather than
  // rejected: it carries the same meaning as null and is stored by the same
  // absence of a value.
  return trimmed.isEmpty ? null : trimmed;
}

/// A `bigint` count column: `NOT NULL`, and non-negative by construction.
///
/// ## Why `int` alone, and no `num` conversion
///
/// Accepting a `double` means normalising it through floating-point arithmetic,
/// and a `double` large enough to matter has already been rounded — so the
/// conversion would launder a wrong number into a confident one. This reader
/// takes an `int` and nothing else, and bounds it at [maxSafeRetailerShopCount]
/// so the same value is either rendered identically on the VM and on the web or
/// rendered on neither.
///
/// On Flutter web every whole JavaScript number *is* an `int`, so a well-formed
/// response parses there exactly as it does on the VM.
///
/// A **string** is refused for the same reason a `double` is: a numeric column
/// arriving as text means the response is not this shape.
int _requiredCount(Object? raw, String what) {
  if (raw is! int) {
    throw RetailerOwnerOverviewFormatException('$what is not an integer');
  }
  if (raw < 0) {
    throw RetailerOwnerOverviewFormatException('$what is negative');
  }
  if (raw > maxSafeRetailerShopCount) {
    throw RetailerOwnerOverviewFormatException(
      '$what exceeds the exact integer range',
    );
  }
  return raw;
}
