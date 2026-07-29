import '../../domain/entities/vendor_retailer_lifecycle_status.dart';

/// The four columns `set_vendor_retailer_status` returns, reduced to what this
/// application uses.
///
/// `relationship_id` is **validated but not carried**. Validation and exposure
/// are separate concerns: the id has to be checked to know the response
/// describes the row that was addressed, and once that is established the screen
/// already holds it from its own route, so passing it further would move an
/// identifier for no reason.
///
/// The two returned statuses collapse to one field for the same kind of reason:
/// the parser refuses a response whose statuses disagree, so by the time a row
/// exists there is exactly one confirmed status to report.
final class VendorRetailerLifecycleRow {
  const VendorRetailerLifecycleRow({
    required this.confirmedStatus,
    required this.statusChanged,
  });

  /// The status **both** rows now hold, as the database reported it — never the
  /// status that was requested.
  final VendorRetailerLifecycleStatus confirmedStatus;

  /// The RPC's own `status_changed`. `false` is an honest idempotent no-op, not
  /// an error.
  final bool statusChanged;
}

/// The 8-4-4-4-12 hexadecimal shape of a UUID.
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Parses a **successful** `set_vendor_retailer_status` response, or returns
/// null.
///
/// ## Null means "committed, but undescribable" — never "nothing happened"
///
/// This function is only ever reached when the SDK threw nothing, which means
/// the transaction **committed**. So every rejection below describes a response
/// this build cannot trust — not a write that failed. The repository maps null
/// to `VendorRetailerWriteUnconfirmed`, which is a success with a caveat: the
/// canonical detail is re-read, the person is told to confirm, and nothing is
/// retried. Reporting any of these as a failure would tell a Vendor their change
/// was not saved after it had been; reporting one as "unchanged" would claim
/// nothing happened when an entire Retailer may have just been deactivated.
///
/// ## It never throws
///
/// Deliberately a nullable return rather than the feature's
/// `VendorRetailerFormatException`. That exception means "a **read** could not be
/// understood", and a read that could not be understood changed nothing — the
/// repository turns it into an operational failure with a retry. Neither of
/// those is true here, and reusing the type would invite exactly the wrong
/// handling. A malformed body of any shape — including one that is not a list,
/// not a map, or `null` — returns null rather than raising.
///
/// ## All four columns are checked, including the identifier
///
/// `client.rpc<Object?>` is untyped, so the body is an `Object?`. A cast would be
/// a claim about the SQL rather than a check of it. Every one of these is a real
/// runtime check:
///
/// 1. **Exactly one row.** PostgREST renders a `returns table (...)` function as
///    an array. The function is structurally guaranteed to emit one row, so zero
///    rows and two rows are both drift. Two rows would otherwise have the second
///    silently discarded, which is the more dangerous of the two.
/// 2. **`relationship_id` is present and a string.**
/// 3. **It is a well-formed UUID.**
/// 4. **It is the row that was addressed.** This is the check that makes the
///    other three worth doing: a response describing a *different* relationship
///    must never be rendered as the outcome of this request. It would attribute
///    another Retailer's lifecycle change to the one on screen — the worst
///    available failure of this control, and one no status check could catch.
/// 5. **`retailer_status` is in the closed vocabulary**, not merely a string.
/// 6. **`relationship_status` is too.** `DEACTIVATED` and `INACTIVE` are both
///    rejected here: the first is a legal column value this operation may never
///    produce, the second is a display word no column stores.
/// 7. **The two statuses agree.** This operation moves both rows in one
///    transaction, so a mismatched pair coming back contradicts the function's
///    own guarantee.
/// 8. **`status_changed` is a genuine `bool`**, not merely truthy — the
///    difference between "you did that" and "somebody already had" is decided by
///    this flag.
///
/// Nothing is silently ignored, coerced or defaulted: every failed check returns
/// null.
///
/// ## Nothing from the response is ever logged or rendered
///
/// There is no `print`, no logger and no message carrying a value read from the
/// body. A wrong relationship id is exactly the kind of value that must not
/// reach an operator log or a screen, and the safe fact — "this could not be
/// described" — is already carried by the null.
///
/// [expectedRelationshipId] is the id that was **submitted**. Compared
/// case-insensitively after trimming, because a UUID's canonical form differs
/// only in case and an upper-cased echo of the same id addresses the same row:
/// this is a check that the right *row* came back, not a string-formatting
/// check.
VendorRetailerLifecycleRow? parseVendorRetailerLifecycleRow(
  Object? raw,
  String expectedRelationshipId,
) {
  // 1. Exactly one row. A bare map is accepted as that one row, so a transport
  //    that unwraps a single-row body is not treated as drift.
  final Object? candidate;
  if (raw is List) {
    if (raw.length != 1) {
      return null;
    }
    candidate = raw.first;
  } else {
    candidate = raw;
  }

  if (candidate is! Map) {
    return null;
  }

  final Map<String, Object?> row = candidate.map<String, Object?>(
    (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
  );

  // 2 + 3. The identifier is present, a string, and well formed.
  final Object? returnedId = row['relationship_id'];
  if (returnedId is! String) {
    return null;
  }
  if (!_uuid.hasMatch(returnedId)) {
    return null;
  }

  // 4. And it is the row that was addressed. The expected id is canonicalized
  //    here too, so a caller that passed an upper-cased id is compared on equal
  //    terms rather than having its own input rejected.
  if (returnedId.toLowerCase() != expectedRelationshipId.trim().toLowerCase()) {
    return null;
  }

  // 5 + 6. Both statuses are in the closed vocabulary.
  final VendorRetailerLifecycleStatus? retailerStatus =
      VendorRetailerLifecycleStatus.tryParse(row['retailer_status']);
  if (retailerStatus == null) {
    return null;
  }
  final VendorRetailerLifecycleStatus? relationshipStatus =
      VendorRetailerLifecycleStatus.tryParse(row['relationship_status']);
  if (relationshipStatus == null) {
    return null;
  }

  // 7. And they agree — the two rows move together or not at all.
  if (retailerStatus != relationshipStatus) {
    return null;
  }

  // 8. The change flag is a genuine boolean.
  final Object? statusChanged = row['status_changed'];
  if (statusChanged is! bool) {
    return null;
  }

  // The validated identifier is deliberately not returned. It has done its job.
  return VendorRetailerLifecycleRow(
    confirmedStatus: retailerStatus,
    statusChanged: statusChanged,
  );
}
