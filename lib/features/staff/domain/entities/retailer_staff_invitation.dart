import 'package:equatable/equatable.dart';

/// The state the backend derived for an invitation.
///
/// ## The backend derives this; the client must not
///
/// `list_retailer_staff_invitations()` computes `derived_state` in a single SQL
/// `CASE` that folds together the stored status, the expiry instant, `sent_at`,
/// `failure_code` and `failure_recorded_at`. Reconstructing any of that in Dart
/// would be a second definition of "is this invitation still usable", free to
/// disagree with the one the write operations actually enforce — so the client
/// reads the derived value and nothing else.
///
/// In particular this build never decides whether an invitation *could* be
/// resent, revoked or accepted. That is a write concern, no write exists in this
/// milestone, and the eligibility rules live in SQL.
///
/// ## Why [indeterminate] exists
///
/// The backend's `CASE` has **no `ELSE` branch**. Every arm tests a specific
/// combination, so a `PENDING` invitation that is unexpired, has been sent, and
/// carries a `failure_code` other than `EMAIL_DISPATCH_FAILED` matches no arm —
/// and PostgreSQL returns `NULL` for it.
///
/// That is a real, reachable value on the deployed contract, so it is modelled
/// rather than treated as malformed. It renders as a neutral "Status
/// unavailable" and unlocks nothing. Rejecting the whole row would hide an
/// invitation that genuinely exists; guessing `PENDING` would assert something
/// the backend declined to say.
///
/// [unknown] is the neighbouring case: a non-null token this build has not been
/// written for, which is an additive backend change and degrades the same way.
enum RetailerInvitationState {
  /// Created but not yet dispatched.
  reserved('RESERVED', 'Not sent yet'),

  /// Sent, unexpired, awaiting acceptance.
  pending('PENDING', 'Awaiting acceptance'),

  /// The recipient accepted and now holds a membership.
  accepted('ACCEPTED', 'Accepted'),

  /// Withdrawn before acceptance.
  revoked('REVOKED', 'Revoked'),

  /// Past its expiry instant, or explicitly expired.
  expired('EXPIRED', 'Expired'),

  /// The email could not be delivered. The invitation itself is still valid.
  deliveryFailed('DELIVERY_FAILED', 'Not delivered'),

  /// A non-null token this build does not recognise — an additive backend
  /// change.
  unknown('', 'Status unavailable'),

  /// The backend's own `CASE` produced `NULL`. See the enum doc.
  indeterminate('', 'Status unavailable');

  const RetailerInvitationState(this.code, this.label);

  /// The backend token. Empty for the two fallbacks, and **never rendered** —
  /// [label] is what reaches a screen, so an unrecognised token cannot travel to
  /// the UI through this enum.
  final String code;

  /// The fixed user-facing label.
  final String label;

  /// Maps a backend token, falling back to [unknown].
  ///
  /// A `null` token is [indeterminate] and is handled by the parser, not here,
  /// so the two fallbacks stay distinguishable in tests even though they share a
  /// label.
  static RetailerInvitationState fromCode(String raw) {
    for (final RetailerInvitationState state in values) {
      if (state != unknown && state != indeterminate && state.code == raw) {
        return state;
      }
    }
    return unknown;
  }

  /// Whether the state is one this build could name.
  ///
  /// Used only to decide whether to show a neutral badge; it grants nothing.
  bool get isRecognised => this != unknown && this != indeterminate;
}

/// One row of `public.list_retailer_staff_invitations()`.
///
/// ## What is deliberately not modelled
///
/// `invitation_id` and `shop_ids` are returned by the contract and **neither
/// appears here**. Both are UUIDs and both are addresses for operations this
/// milestone does not perform — there is no resend, revoke, or shop
/// reassignment. Carrying them would put identifiers on a phone for no purpose.
///
/// `failure_code` is also **not carried as a raw value**. It is reduced at the
/// parser to [hasDeliveryFailure], a boolean, so a backend enum token can never
/// reach a screen. What a user needs to know is that the email did not arrive,
/// not which internal code recorded it.
final class RetailerStaffInvitation extends Equatable {
  const RetailerStaffInvitation({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.roleCode,
    required this.state,
    required this.hasDeliveryFailure,
    required this.createdAt,
    required this.sentAt,
    required this.acceptedAt,
    required this.revokedAt,
    required this.expiresAt,
  });

  final String firstName;
  final String lastName;

  /// The address the invitation was sent to.
  ///
  /// Shown because an Owner needs to see *where* an invitation went — a typo in
  /// the address is the single most common reason one is never accepted, and
  /// it is not diagnosable without seeing it. It is already the Owner's own
  /// organization's data, and the Owner is the person who supplied it.
  final String email;

  /// `roles.code` for the role the invitation grants.
  ///
  /// The contract returns **only the code** here, not a display name — unlike
  /// the roster, which returns both. So this one *is* rendered, mapped through a
  /// fixed label table in the presentation layer rather than shown raw.
  final String roleCode;

  final RetailerInvitationState state;

  /// Whether delivery of the invitation email failed.
  ///
  /// Derived from `failure_code` at the parser; the code itself is discarded
  /// there and never reaches this type or a screen.
  final bool hasDeliveryFailure;

  final DateTime createdAt;

  /// Null until dispatched.
  final DateTime? sentAt;

  /// Null unless accepted.
  final DateTime? acceptedAt;

  /// Null unless revoked.
  final DateTime? revokedAt;

  /// When the invitation stops being usable. `NOT NULL` in the contract.
  final DateTime expiresAt;

  String get fullName => '$firstName $lastName';

  /// Whether this invitation has reached a terminal state.
  ///
  /// Presentation only — it decides whether to de-emphasise a row, and gates no
  /// operation, because this milestone has none.
  bool get isSettled =>
      state == RetailerInvitationState.accepted ||
      state == RetailerInvitationState.revoked ||
      state == RetailerInvitationState.expired;

  @override
  List<Object?> get props => <Object?>[
    firstName,
    lastName,
    email,
    roleCode,
    state,
    hasDeliveryFailure,
    createdAt,
    sentAt,
    acceptedAt,
    revokedAt,
    expiresAt,
  ];
}
