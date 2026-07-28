import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/retailer_staff_invitation.dart';
import '../../domain/entities/retailer_staff_member.dart';

/// The canonical uuid shape, matched case-insensitively.
///
/// Applied to `membership_id` and to every element of `shop_ids` because these
/// are the roster values that are **sent back** to the backend. Everywhere else
/// an unexpected string would only be displayed; here it would become an
/// argument of a `uuid` / `uuid[]` parameter, and a client that forwarded a
/// malformed one would turn a readable local refusal into an opaque `22P02`
/// cast error raised before the function body ever ran.
final RegExp _uuidShape = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// One `uuid` column, lower-cased.
///
/// Lower-cased so the value held is the value the contract canonicalizes to, and
/// so two spellings of one id can never be counted as two shops.
String _requiredUuid(Object? raw, String what) {
  final String value = RpcRow.requiredString(raw, what).trim();
  if (!_uuidShape.hasMatch(value)) {
    throw RpcFormatException('$what is not shaped like a uuid');
  }
  return value.toLowerCase();
}

/// A `uuid[]` column, lower-cased, order preserved.
///
/// Unlike [RpcRow.stringArray], a null or malformed **element** fails the row
/// rather than being dropped. A dropped shop name is one missing chip; a dropped
/// shop id would silently change the set the editor preselects, and saving from
/// it would retire an assignment nobody chose to remove.
///
/// A **duplicate** fails the row too: `retailer_shop_members` is keyed on the
/// pair, so the same shop cannot legitimately appear twice for one member, and a
/// response that says it does is not this contract.
List<String> _uuidArray(Object? raw, String what) {
  if (raw is! List) {
    throw RpcFormatException('$what is not an array');
  }
  final List<String> ids = raw
      .map((Object? value) => _requiredUuid(value, '$what element'))
      .toList(growable: false);
  if (ids.toSet().length != ids.length) {
    throw RpcFormatException('$what contains a duplicate');
  }
  return ids;
}

/// Parses `list_retailer_staff_members()`.
///
/// ## The whole roster, or none of it
///
/// One malformed row fails the read. Skipping bad rows would silently
/// under-report who works for a Retailer, and a roster quietly short by one
/// person is worse than one that honestly failed to load.
///
/// ## Which malformations are rejected, and which are tolerated
///
/// Rejected:
///
/// * a body that is not a list, or a row that is not an object;
/// * a missing, null, blank or non-string `first_name`, `last_name`,
///   `role_code`, `role_name` or `membership_status`;
/// * a missing, null, blank or non-string `membership_id`, or one that is not
///   shaped like a uuid;
/// * a missing or non-array `shop_names`;
/// * a missing or non-array `shop_ids`, an element that is not a uuid, or a
///   duplicate element;
/// * a missing, null or unparseable `created_at`;
/// * an unparseable `joined_at` — distinct from a **null** one, which is legal.
///
/// Tolerated:
///
/// * an **empty list** → an empty roster. A real answer.
/// * an **unrecognized extra key** → ignored; the contract is additive.
/// * an **unrecognized `membership_status`** → [RetailerMemberStatus.unknown],
///   displayed neutrally and never as active.
/// * an **unrecognized `role_code`** → carried through untouched. The role
///   catalogue is data rather than a closed enum, and `role_name` is what the
///   screen renders — a Retailer that adds a role should see its name, not a
///   parse failure.
/// * a **null `joined_at`** → null. A membership created but never accepted has
///   no joining date, and substituting `created_at` would state a date that
///   never happened.
/// * an **empty `shop_names`** or **`shop_ids`** → an empty list. Owners and
///   Managers hold no shop rows at all, so this is the expected shape for them.
/// * **`shop_ids` of a different length from `shop_names`** → both kept as they
///   arrived. See below.
///
/// ## Why the two identifier columns are strict where the names are not
///
/// `shop_names` drops a blank element rather than failing the row: a name that
/// cannot be shown is one missing chip. `membership_id` and `shop_ids` are the
/// values this client **sends back**, so the same leniency would mean addressing
/// a row with something the backend never returned, or preselecting a shop set
/// that is quietly short by one — and saving from a short set retires an
/// assignment nobody chose to remove.
abstract final class RetailerStaffMemberParser {
  static List<RetailerStaffMember> parse(Object? raw) {
    return RpcRow.asRows(
      raw,
      'staff',
    ).map(RetailerStaffMemberParser.parseRow).toList(growable: false);
  }

  static RetailerStaffMember parseRow(Map<String, Object?> row) {
    return RetailerStaffMember(
      // The canonical address of this membership, and the only value that may
      // become `p_membership_id`. Read here, held on the entity, never rendered.
      membershipId: _requiredUuid(row['membership_id'], 'membership_id'),
      firstName: RpcRow.requiredString(row['first_name'], 'first_name'),
      lastName: RpcRow.requiredString(row['last_name'], 'last_name'),
      roleCode: RpcRow.requiredString(row['role_code'], 'role_code'),
      roleName: RpcRow.requiredString(row['role_name'], 'role_name'),
      status: RetailerMemberStatus.fromCode(
        RpcRow.requiredString(row['membership_status'], 'membership_status'),
      ),
      // Both arrays are read, and the two are deliberately **never paired**.
      //
      // The backend builds them from the same subquery with the same `order by
      // s.name, s.id`, so they are positionally aligned by construction. This
      // parser still does not zip them, and no code downstream does either: the
      // ids seed the editor's preselection, the names are what a person reads,
      // and no name is ever attributed to an id anywhere.
      //
      // That is a stronger guarantee than validating the lengths would give. A
      // length check would have to decide what to do on mismatch, and every
      // available answer (fail the row, truncate, pad) either hides a colleague
      // or invents a pairing. Not pairing them at all makes a mismatch
      // incapable of mislabelling anything.
      //
      // These are the ACTIVE shops only — the contract's own `removed_at is
      // null and s.status = 'ACTIVE'` predicate. A live assignment to a
      // suspended or deactivated shop is not here, and the write preserves it.
      shopIds: _uuidArray(row['shop_ids'], 'shop_ids'),
      shopNames: RpcRow.stringArray(row['shop_names'], 'shop_names'),
      joinedAt: RpcRow.optionalTimestamp(row['joined_at'], 'joined_at'),
      createdAt: RpcRow.requiredTimestamp(row['created_at'], 'created_at'),
    );
  }
}

/// The one `failure_code` the backend's own `CASE` recognises.
///
/// Matched here solely to confirm that a recorded failure is the delivery
/// failure the derived state already describes. The **value is never carried
/// forward and never rendered** — [RetailerStaffInvitation.hasDeliveryFailure]
/// is a boolean, so no backend enum token can reach a screen.
const String _emailDispatchFailed = 'EMAIL_DISPATCH_FAILED';

/// Parses `list_retailer_staff_invitations()`.
///
/// ## Which malformations are rejected, and which are tolerated
///
/// Rejected:
///
/// * a body that is not a list, or a row that is not an object;
/// * a missing, null, blank or non-string `first_name`, `last_name`, `email` or
///   `role_code`;
/// * a missing, null or unparseable `created_at` or `expires_at`;
/// * an unparseable `sent_at`, `accepted_at` or `revoked_at` — distinct from a
///   **null** one, which is legal and common.
///
/// Tolerated:
///
/// * an **empty list** → no invitations. A real answer for a Retailer that has
///   never invited anyone.
/// * an **unrecognized extra key** → ignored.
/// * a **null `derived_state`** → [RetailerInvitationState.indeterminate]. This
///   is not defensive padding: the backend's `CASE` has no `ELSE`, so a
///   `PENDING` invitation that is unexpired, has been sent, and carries a
///   `failure_code` other than `EMAIL_DISPATCH_FAILED` genuinely produces
///   `NULL`. Rejecting the row would hide an invitation that exists; guessing
///   `PENDING` would assert something the backend declined to say.
/// * an **unrecognized `derived_state` token** → [RetailerInvitationState.unknown].
/// * a **`failure_code` this build does not know** → treated as a delivery
///   failure for display purposes only, and the code itself is discarded. The
///   user-visible claim is "the email did not arrive", which is true for any
///   recorded failure; the specific code is an internal value and is not shown.
abstract final class RetailerStaffInvitationParser {
  static List<RetailerStaffInvitation> parse(Object? raw) {
    return RpcRow.asRows(
      raw,
      'invitations',
    ).map(RetailerStaffInvitationParser.parseRow).toList(growable: false);
  }

  static RetailerStaffInvitation parseRow(Map<String, Object?> row) {
    final Object? rawState = row['derived_state'];
    final RetailerInvitationState state = rawState == null
        ? RetailerInvitationState.indeterminate
        : RetailerInvitationState.fromCode(
            RpcRow.requiredString(rawState, 'derived_state'),
          );

    // Reduced to a boolean here and nowhere else. `failure_code` does not exist
    // beyond this line: it is not stored on the entity, not put in state, and
    // not rendered. A recorded failure of any kind means the same thing to the
    // person reading the screen.
    final String? failureCode = RpcRow.optionalString(
      row['failure_code'],
      'failure_code',
    );
    final bool hasDeliveryFailure =
        failureCode != null || state == RetailerInvitationState.deliveryFailed;

    // Referenced so the one recognised code is not merely dead documentation:
    // an unrecognised code is still a failure, which is the point of the
    // boolean, and this assertion of intent keeps the constant honest.
    assert(
      failureCode == null ||
          failureCode == _emailDispatchFailed ||
          hasDeliveryFailure,
      'any recorded failure code must surface as a delivery failure',
    );

    return RetailerStaffInvitation(
      firstName: RpcRow.requiredString(row['first_name'], 'first_name'),
      lastName: RpcRow.requiredString(row['last_name'], 'last_name'),
      email: RpcRow.requiredString(row['email'], 'email'),
      roleCode: RpcRow.requiredString(row['role_code'], 'role_code'),
      state: state,
      hasDeliveryFailure: hasDeliveryFailure,
      createdAt: RpcRow.requiredTimestamp(row['created_at'], 'created_at'),
      sentAt: RpcRow.optionalTimestamp(row['sent_at'], 'sent_at'),
      acceptedAt: RpcRow.optionalTimestamp(row['accepted_at'], 'accepted_at'),
      revokedAt: RpcRow.optionalTimestamp(row['revoked_at'], 'revoked_at'),
      expiresAt: RpcRow.requiredTimestamp(row['expires_at'], 'expires_at'),
      // No invitation_id and no shop_ids. The contract returns both; nothing
      // here holds either.
    );
  }
}
