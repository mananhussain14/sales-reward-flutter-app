import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/retailer_staff_invitation.dart';
import '../../domain/entities/retailer_staff_member.dart';

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
/// * a missing or non-array `shop_names`;
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
/// * an **empty `shop_names`** → an empty list. Owners and Managers hold no shop
///   rows at all, so this is the expected shape for them.
/// * **`shop_ids` of a different length from `shop_names`** → ignored entirely.
///   See below.
abstract final class RetailerStaffMemberParser {
  static List<RetailerStaffMember> parse(Object? raw) {
    return RpcRow.asRows(
      raw,
      'staff',
    ).map(RetailerStaffMemberParser.parseRow).toList(growable: false);
  }

  static RetailerStaffMember parseRow(Map<String, Object?> row) {
    return RetailerStaffMember(
      firstName: RpcRow.requiredString(row['first_name'], 'first_name'),
      lastName: RpcRow.requiredString(row['last_name'], 'last_name'),
      roleCode: RpcRow.requiredString(row['role_code'], 'role_code'),
      roleName: RpcRow.requiredString(row['role_name'], 'role_name'),
      status: RetailerMemberStatus.fromCode(
        RpcRow.requiredString(row['membership_status'], 'membership_status'),
      ),
      // Names only. `shop_ids` is read by nobody: the two arrays are built by
      // the backend from the same subquery with the same `order by s.name,
      // s.id`, so they are positionally aligned by construction — but this
      // client never pairs them, because it has no use for an id. Nothing here
      // can therefore be mis-paired by a length mismatch, and a mismatch cannot
      // produce a shop name attributed to the wrong shop, because no name is
      // ever attributed to an id at all.
      //
      // That is a stronger guarantee than validating the lengths would give: a
      // validation would have to decide what to do on mismatch, and every
      // available answer (drop the row, truncate, pad) loses information.
      shopNames: RpcRow.stringArray(row['shop_names'], 'shop_names'),
      joinedAt: RpcRow.optionalTimestamp(row['joined_at'], 'joined_at'),
      createdAt: RpcRow.requiredTimestamp(row['created_at'], 'created_at'),
      // No membership_id. The contract returns one; nothing here holds it.
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
