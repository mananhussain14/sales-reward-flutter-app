import '../../domain/entities/retailer_staff_invitation_request.dart';

/// The exact top-level keys the deployed Edge Function accepts, in the order the
/// shared contract declares them.
///
/// Written down as a list so the encoder below can be checked against it rather
/// than against a reading of the encoder — and so that adding a sixth key is a
/// visible edit to a named constant with a test on it, not a quiet extra line in
/// a map literal.
const List<String> retailerStaffInvitationRequestFields = <String>[
  'firstName',
  'lastName',
  'email',
  'roleCode',
  'shopIds',
];

/// Encodes a validated request as the function's request body.
///
/// ## Five keys, and the function rejects a sixth rather than ignoring it
///
/// `parseStaffInvitationRequest` refuses any unknown top-level key. That is what
/// makes the following impossible to smuggle in against a later edit: a Retailer
/// organization id, an actor / user / profile id, a membership id, a permission,
/// an invitation id, a token, a token hash, audit data, an invitation state, an
/// expiry, a normalized email, or any Resend or service-role setting. None of
/// them is written below, and none of them exists on
/// [RetailerStaffInvitationRequest] to be written.
///
/// So a well-meaning "just add the organization id, the backend will ignore it"
/// does not degrade this client — it breaks every send with `INVALID_REQUEST`,
/// loudly, which is the intended failure mode.
///
/// ## `shopIds` is always present, including for a Retailer Manager
///
/// The field is **required** even when it is empty: an absent array and an empty
/// one would otherwise be the same request, and "I chose no shops" must not be
/// expressible as "I forgot the field". A Manager request carries `[]`, which the
/// validation guarantees by refusing to build a Manager request that holds one.
///
/// The values themselves are already canonical — trimmed, lower-cased, sorted
/// and de-duplicated by the request's own validation — so nothing is normalized
/// here. This function shapes; it does not decide.
Map<String, Object?> encodeRetailerStaffInvitationRequest(
  RetailerStaffInvitationRequest request,
) {
  return <String, Object?>{
    'firstName': request.firstName,
    'lastName': request.lastName,
    'email': request.email,
    'roleCode': request.role.code,
    'shopIds': List<String>.of(request.shopIds),
  };
}
