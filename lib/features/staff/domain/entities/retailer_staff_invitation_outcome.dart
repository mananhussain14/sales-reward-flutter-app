/// The contract version this build understands, and the only one it accepts.
///
/// The shared delivery contract pins `version: 1` in **every** response and
/// bumps it only for a breaking change — a removed field, a changed field
/// meaning, or a repurposed outcome. Adding a new `code` to an existing
/// `outcome` is explicitly *not* breaking.
///
/// So a response whose version is anything other than this is refused outright
/// rather than read optimistically: the safety-critical question this contract
/// answers is "might an email have been delivered?", and guessing at it under a
/// vocabulary this build has never seen is exactly the guess that must not be
/// made.
const int retailerStaffInvitationContractVersion = 1;

/// **The safety-critical classification.** Read before [RetailerStaffInvitationCode],
/// always.
///
/// It answers the one question a client must never get wrong: *might an email
/// have been delivered?* [notSent] means nothing was handed to the provider and
/// the request may be repeated as-is. The other four mean it was — so repeating
/// the whole write would mint a new token, invalidate a link that may already be
/// in the recipient's inbox, and send a second email.
enum RetailerStaffInvitationOutcome {
  /// First delivery; the provider accepted it; the send was recorded.
  sent('SENT'),

  /// The same, for an invitation that already existed. The **previous link is no
  /// longer current** — a resend rotates the token.
  resent('RESENT'),

  /// The provider accepted the message, but the write that records it could not
  /// be confirmed.
  ///
  /// Normally arrives with HTTP 202, which is a *success* status precisely so
  /// that no HTTP library, proxy or retry policy resubmits the write on its own.
  ///
  /// The invitation is still acceptable: the token hash and the expiry were
  /// stored before the email went out, and neither the recipient lookup nor the
  /// acceptance path reads `sent_at`. What is unconfirmed is the bookkeeping,
  /// not the recipient's ability to accept.
  ///
  /// **Never automatically repeat the write.** Repeating it re-reserves, mints a
  /// new token and rotates the hash, killing the link that was just delivered
  /// and sending a second email.
  deliveryAcceptedStatusUnconfirmed('DELIVERY_ACCEPTED_STATUS_UNCONFIRMED'),

  /// The provider did not accept the message. The invitation exists and is
  /// retryable by a deliberate, human-initiated action.
  deliveryFailed('DELIVERY_FAILED'),

  /// Nothing was handed to the provider. Safe to repeat the request unchanged
  /// once the reason in the code is addressed.
  notSent('NOT_SENT');

  const RetailerStaffInvitationOutcome(this.token);

  /// The exact wire token. Compared; never displayed.
  final String token;

  /// The outcome for a wire token, or null when this build does not know it.
  ///
  /// Null is never degraded to a member. An unrecognised outcome means the
  /// response cannot be classified as "an email may have gone out" or "nothing
  /// was sent", and both available guesses are wrong in a way that matters.
  static RetailerStaffInvitationOutcome? fromToken(String raw) {
    for (final RetailerStaffInvitationOutcome outcome
        in RetailerStaffInvitationOutcome.values) {
      if (outcome.token == raw) {
        return outcome;
      }
    }
    return null;
  }

  /// Whether the message reached the provider.
  ///
  /// The property that decides whether repeating the write is safe.
  bool get reachedProvider => this != notSent;
}

/// The stable machine codes, which refine an outcome's reason.
///
/// Every member below is deployed. There is **no `RATE_LIMITED`**: no rate
/// limiter exists in this system, so no code names one and nothing in this
/// application may claim one does.
///
/// The code vocabulary is allowed to grow — that is why a new code is not a
/// breaking change — so a token this build does not know degrades to
/// [unrecognized] and the screen falls back to the recognised **outcome's**
/// generic copy. That degradation is safe in a way an unrecognised *outcome*
/// never is: the outcome already settled whether an email may have gone out.
enum RetailerStaffInvitationCode {
  // -- the message reached the provider --------------------------------------
  sent('SENT', RetailerStaffInvitationOutcome.sent),
  resent('RESENT', RetailerStaffInvitationOutcome.resent),
  deliveryAcceptedStatusUnconfirmed(
    'DELIVERY_ACCEPTED_STATUS_UNCONFIRMED',
    RetailerStaffInvitationOutcome.deliveryAcceptedStatusUnconfirmed,
  ),
  deliveryFailed(
    'DELIVERY_FAILED',
    RetailerStaffInvitationOutcome.deliveryFailed,
  ),

  // -- nothing was sent ------------------------------------------------------
  /// The request was not a POST. Unreachable from this client, which posts.
  methodNotAllowed(
    'METHOD_NOT_ALLOWED',
    RetailerStaffInvitationOutcome.notSent,
  ),

  /// Malformed JSON, a missing, blank or oversized field, or an unknown
  /// top-level key.
  invalidRequest('INVALID_REQUEST', RetailerStaffInvitationOutcome.notSent),

  /// Shops for a Retailer Manager, or none for Sales Staff. Structurally valid,
  /// semantically impossible.
  invalidRoleShopCombination(
    'INVALID_ROLE_SHOP_COMBINATION',
    RetailerStaffInvitationOutcome.notSent,
  ),

  /// No access token, or one the Auth server does not accept.
  authRequired('AUTH_REQUIRED', RetailerStaffInvitationOutcome.notSent),

  /// Authenticated, but not permitted to invite staff for any Retailer.
  accessDenied('ACCESS_DENIED', RetailerStaffInvitationOutcome.notSent),

  /// A live invitation exists for this address with a different role or shop
  /// set.
  invitationConflict(
    'INVITATION_CONFLICT',
    RetailerStaffInvitationOutcome.notSent,
  ),

  /// The caller's Retailer is not ACTIVE, so it may not invite anyone.
  retailerInactive('RETAILER_INACTIVE', RetailerStaffInvitationOutcome.notSent),

  /// Sending is switched off for this deployment.
  featureDisabled('FEATURE_DISABLED', RetailerStaffInvitationOutcome.notSent),

  /// A required server-side secret is absent or invalid. Nothing was attempted.
  notConfigured('NOT_CONFIGURED', RetailerStaffInvitationOutcome.notSent),

  /// Anything else. Deliberately opaque on the backend, and kept opaque here.
  internalError('INTERNAL_ERROR', RetailerStaffInvitationOutcome.notSent),

  // -- this build's own fallback ---------------------------------------------
  /// A code this build does not know, or one whose declared outcome contradicts
  /// the response's own `outcome` field.
  ///
  /// Carries **no token**, so an unrecognised backend string cannot travel past
  /// the parser, let alone reach a screen. The outcome decides what is shown.
  unrecognized('', null);

  const RetailerStaffInvitationCode(this.token, this.outcome);

  /// The exact wire token, or the empty string for [unrecognized]. Compared;
  /// never displayed.
  final String token;

  /// The outcome this code belongs to, or null for [unrecognized].
  ///
  /// Used only to detect a response whose `outcome` and `code` disagree, which
  /// is treated as an unrecognised code rather than as a reason to prefer the
  /// code — the outcome is the field the contract calls safety-critical.
  final RetailerStaffInvitationOutcome? outcome;

  /// The code for a wire token, or null when this build does not know it.
  static RetailerStaffInvitationCode? fromToken(String raw) {
    for (final RetailerStaffInvitationCode code
        in RetailerStaffInvitationCode.values) {
      if (code != unrecognized && code.token == raw) {
        return code;
      }
    }
    return null;
  }
}

/// Why a send produced no readable contract answer at all.
///
/// Distinct from every [RetailerStaffInvitationCode], because a code is
/// something the function *said* and these are the cases where it said nothing
/// this build could use. Collapsing them into one "check your connection" would
/// send somebody to fix a connection that is working.
enum RetailerStaffInvitationTransportProblem {
  /// The request never reached the backend: no route, no DNS answer, a refused
  /// TLS handshake, a blocked socket, a browser CORS refusal.
  ///
  /// The one member whose copy may mention the connection. Nothing was sent.
  network,

  /// The request was sent and nothing came back in time.
  ///
  /// **Ambiguous, and treated as such.** The function may have completed after
  /// the client stopped waiting, so this never claims the invitation failed and
  /// never retries — it points at the invitation history, which is the only
  /// authority on what actually happened.
  timeout,

  /// There is no verified session. The caller is not signed in, rather than
  /// signed in and refused.
  signedOut,

  /// An answer arrived that this build could not read: a wrong shape, an
  /// unsupported `version`, or a missing or unrecognised `outcome`.
  ///
  /// Also ambiguous, and treated the same way as [timeout]: the outcome field is
  /// the only thing that says whether an email went out, so a response missing
  /// it settles nothing.
  malformed,

  /// Anything else — an unexpected SDK state or a programming error. Not a
  /// statement about the user's network.
  unexpected,
}
