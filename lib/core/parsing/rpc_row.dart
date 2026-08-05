/// A backend response could not be understood.
///
/// Every branch that throws this is a branch that would otherwise have to guess,
/// and on a read-only portal the only safe guess is none. A repository turns it
/// into `RetailerReadProblem.malformed` — **never** into an empty list, never
/// into a partially populated row, and never into "you are not allowed".
///
/// The empty list is the load-bearing case: it is a real, reachable answer for
/// every one of these contracts, so a parser that degraded to it on a field it
/// could not read would tell a Retailer "you have no shops / no staff / no
/// products" on the strength of a response this build did not understand.
final class RpcFormatException implements Exception {
  const RpcFormatException(this.reason);

  /// A short, developer-facing reason. Never rendered to a user, and never
  /// carrying a value read from the response.
  final String reason;

  @override
  String toString() => 'RpcFormatException: $reason';
}

/// Strict readers for a PostgREST row.
///
/// They throw rather than substituting a default. A default here would be a
/// value the backend never sent, presented as though it had.
///
/// Shared by the Shops, Staff and Product parsers because all three read the
/// same primitive shapes from the same transport. Each parser still owns its own
/// field names, cross-field rules and enums — this file knows nothing about any
/// contract.
abstract final class RpcRow {
  /// The body as a list of rows.
  ///
  /// PostgREST renders a set-returning function as a JSON array. A body that is
  /// not an array means the response is not this shape; an **empty** array is a
  /// real, successful answer and passes straight through.
  static List<Map<String, Object?>> asRows(Object? raw, String what) {
    if (raw is! List) {
      throw RpcFormatException('$what is not a list');
    }
    return raw.map((Object? row) => asMap(row, '$what row')).toList();
  }

  /// One row as a string-keyed map.
  static Map<String, Object?> asMap(Object? raw, String what) {
    if (raw is Map) {
      return raw.map<String, Object?>(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
    }
    throw RpcFormatException('$what is not an object');
  }

  /// A `text` column that is `NOT NULL` in the contract.
  ///
  /// Blank is refused along with null: every such column in these contracts is
  /// backed by a `length(trim(...)) > 0` check, so an empty string is evidence
  /// the response is not this shape, and rendering one would produce a card
  /// titled with nothing.
  static String requiredString(Object? raw, String what) {
    if (raw is! String) {
      throw RpcFormatException('$what is missing or not a text');
    }
    if (raw.trim().isEmpty) {
      throw RpcFormatException('$what is blank');
    }
    return raw;
  }

  /// A nullable `text` column.
  ///
  /// Null passes through untouched — it is a real answer meaning "not recorded",
  /// and none of these columns has a defensible default. A present value must
  /// still be a string; a number or a boolean means the response is not this
  /// shape.
  ///
  /// A present-but-blank value is treated as null: it carries the same meaning
  /// and, for the columns that have a `not_empty` check, cannot legally be
  /// stored anyway.
  static String? optionalString(Object? raw, String what) {
    if (raw == null) {
      return null;
    }
    if (raw is! String) {
      throw RpcFormatException('$what is not a text');
    }
    final String trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// A `boolean` column that is `NOT NULL` in the contract.
  ///
  /// Refused rather than coerced. `null`, `0`, `1`, `'t'` and `'true'` are all
  /// values a boolean column could conceivably arrive as if the response were
  /// not this shape, and every one of them would have to be *interpreted* — on
  /// this surface the booleans decide whether a reader is told a target was
  /// reached and whether a bonus was theirs, so a guess is a confident claim
  /// about money.
  static bool requiredBool(Object? raw, String what) {
    if (raw is! bool) {
      throw RpcFormatException('$what is missing or not a boolean');
    }
    return raw;
  }

  /// A `timestamptz` column that is `NOT NULL` in the contract.
  ///
  /// Parsed to **UTC**, so nothing downstream depends on the device's zone for
  /// equality or ordering. Formatting for display is the presentation layer's
  /// job and happens in local time there.
  static DateTime requiredTimestamp(Object? raw, String what) {
    final DateTime? parsed = optionalTimestamp(raw, what);
    if (parsed == null) {
      throw RpcFormatException('$what is missing');
    }
    return parsed;
  }

  /// A nullable `timestamptz` column.
  ///
  /// Null is a real answer — an invitation that was never sent has no `sent_at`,
  /// a membership created by an invitation that was never accepted has no
  /// `joined_at`. An **unparseable** string is not: it is refused rather than
  /// silently dropped to null, because "no date" and "a date this build could
  /// not read" are different facts and only one of them is the backend's.
  static DateTime? optionalTimestamp(Object? raw, String what) {
    if (raw == null) {
      return null;
    }
    if (raw is! String) {
      throw RpcFormatException('$what is not a timestamp string');
    }
    final DateTime? parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw RpcFormatException('$what is not a parseable timestamp');
    }
    return parsed.toUtc();
  }

  /// A `text[]` column, as a list of non-blank strings.
  ///
  /// `coalesce(..., '{}')` in the contracts means the column is never null, so a
  /// missing key or a null value is a malformed row rather than "no entries".
  /// An empty array **is** a real answer — a Manager or Owner holds no shop
  /// assignments — and yields an empty list.
  ///
  /// Individual null or blank elements are dropped rather than failing the row:
  /// a name that cannot be shown is one entry missing from a chip list, not a
  /// reason to hide a whole staff member.
  static List<String> stringArray(Object? raw, String what) {
    if (raw is! List) {
      throw RpcFormatException('$what is not an array');
    }
    return raw
        .whereType<String>()
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList();
  }
}
