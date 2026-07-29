import '../../domain/entities/retailer_staff_lifecycle_status.dart';

/// The four columns `set_retailer_staff_membership_status` returns, reduced to
/// what this application uses.
///
/// `membership_id` is **validated but not carried**. Validation and exposure are
/// separate concerns: the id has to be checked to know the response describes the
/// row that was addressed, and once that is established the screen already holds
/// it from the roster, so passing it further would move an identifier for no
/// reason.
///
/// `role_code` is present in the response and is deliberately **not read**.
/// Nothing this application renders needs it, the roster already carries the
/// row's display role, and a role code has no business travelling further than it
/// must. It is emphatically **not** a second status and no synchronisation check
/// applies to it.
final class RetailerStaffLifecycleRow {
  const RetailerStaffLifecycleRow({
    required this.confirmedStatus,
    required this.statusChanged,
  });

  /// The status the membership now holds, as the database reported it — never
  /// the status that was requested.
  final RetailerStaffLifecycleStatus confirmedStatus;

  /// The RPC's own `status_changed`. `false` is an honest idempotent no-op, not
  /// an error: the function performed no `UPDATE`, wrote no audit row, and left
  /// `deactivated_at` exactly as it was.
  final bool statusChanged;
}

/// The 8-4-4-4-12 hexadecimal shape of a UUID.
final RegExp _uuidShape = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Parses a **successful** `set_retailer_staff_membership_status` response, or
/// returns null.
///
/// ## Null means "committed, but undescribable" — never "nothing happened"
///
/// This function is only ever reached when the SDK threw nothing, which means the
/// transaction **committed**. So every rejection below describes a response this
/// build cannot trust — not a write that failed. The repository maps null to
/// `RetailerStaffLifecycleUnconfirmed`, which is a success with a caveat: the
/// canonical roster is re-read, the Owner is told to confirm, and nothing is
/// retried. Reporting any of these as a refusal would tell an Owner a colleague
/// was not deactivated after they had been; reporting one as "unchanged" would
/// claim nothing happened when somebody may have just lost access.
///
/// ## It never throws
///
/// Deliberately a nullable return rather than `RpcFormatException`. That
/// exception means "a **read** could not be understood", and a read that could
/// not be understood changed nothing — the repository turns it into an
/// operational problem with a retry. Neither is true here, and reusing the type
/// would invite exactly the wrong handling. A malformed body of any shape —
/// including one that is not a list, not a map, or `null` — returns null rather
/// than raising.
///
/// ## This is deliberately stricter than the Web implementation
///
/// The Next.js wrapper's `readStatusRow` takes `data[0]` with **no row-count
/// check** and does **not** compare the returned `membership_id` to the submitted
/// one. Both checks are implemented here anyway, and the divergence is
/// intentional: a stricter parser can only ever produce *more* `unconfirmed` and
/// never a false success, and the id-echo check is the only thing that stops one
/// colleague's outcome being rendered under another colleague's name — the worst
/// available failure of this control, and one no status check could catch.
///
/// All checks, in order:
///
/// 1. **Exactly one row.** PostgREST renders a `returns table (...)` function as
///    an array. The function is structurally guaranteed to emit one row — on the
///    no-op path too — so zero rows and two rows are both drift. Two rows would
///    otherwise have the second silently discarded.
/// 2. The row is a map.
/// 3. `membership_id` is present and a string.
/// 4. It is a well-formed UUID.
/// 5. **It is the row that was addressed**, compared case-insensitively after
///    trimming, because a UUID's canonical form differs only in case.
/// 6. `membership_status` is exactly `ACTIVE` or `DEACTIVATED`, not merely a
///    string. `INVITED`, `SUSPENDED` and `INACTIVE` are all rejected here.
/// 7. `status_changed` is a genuine `bool`, not merely truthy — the difference
///    between "you did that" and "somebody already had" is decided by this flag.
///
/// Nothing is silently ignored, coerced or defaulted: every failed check returns
/// null.
///
/// ## Nothing from the response is ever logged or rendered
///
/// There is no `print`, no logger and no message carrying a value read from the
/// body. A wrong membership id is exactly the kind of value that must not reach
/// an operator log or a screen, and the safe fact — "this could not be described"
/// — is already carried by the null.
RetailerStaffLifecycleRow? parseRetailerStaffLifecycleRow(
  Object? raw,
  String expectedMembershipId,
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

  // 2. The row is a map.
  if (candidate is! Map) {
    return null;
  }

  final Map<String, Object?> row = candidate.map<String, Object?>(
    (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
  );

  // 3 + 4. The identifier is present, a string, and well formed.
  final Object? returnedId = row['membership_id'];
  if (returnedId is! String) {
    return null;
  }
  if (!_uuidShape.hasMatch(returnedId)) {
    return null;
  }

  // 5. And it is the row that was addressed. The expected id is canonicalized
  //    here too, so a caller that passed an upper-cased id is compared on equal
  //    terms rather than having its own input rejected.
  if (returnedId.toLowerCase() != expectedMembershipId.trim().toLowerCase()) {
    return null;
  }

  // 6. The status is in the closed vocabulary.
  final RetailerStaffLifecycleStatus? status =
      RetailerStaffLifecycleStatus.tryParse(row['membership_status']);
  if (status == null) {
    return null;
  }

  // 7. The change flag is a genuine boolean.
  final Object? statusChanged = row['status_changed'];
  if (statusChanged is! bool) {
    return null;
  }

  // The validated identifier is deliberately not returned, and `role_code` is
  // deliberately never read. Both have done their job.
  return RetailerStaffLifecycleRow(
    confirmedStatus: status,
    statusChanged: statusChanged,
  );
}
