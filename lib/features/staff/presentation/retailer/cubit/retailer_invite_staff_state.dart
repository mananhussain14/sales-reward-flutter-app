part of 'retailer_invite_staff_cubit.dart';

/// Where the assignable-shops read has reached.
enum RetailerInviteShopsPhase {
  /// Never requested. Sales Staff has not been chosen yet.
  initial,

  /// A read is in flight.
  loading,

  /// Options are held — possibly zero, which is a real answer meaning this
  /// Retailer has no ACTIVE shops. A refusal is [failed], never this.
  ready,

  /// The read did not produce an answer.
  failed,
}

/// What the screen must tell the person about the last submission.
///
/// Every member maps to one fixed sentence in [RetailerInviteStaffCopy]. None is
/// ever built from a response, so no backend message, SQLSTATE, provider text,
/// invitation id, token or email link can reach a screen through this type.
///
/// The members are grouped by the only question that changes behaviour: **might
/// an email have gone out?**
enum RetailerInviteStaffNotice {
  // -- the form was never submitted ------------------------------------------
  /// Local validation refused it. Nothing left the device.
  checkTheForm,

  // -- delivered -------------------------------------------------------------
  /// `SENT`. First delivery, accepted by the provider and recorded.
  sent,

  /// `RESENT`. A new email went out and **the previous link is no longer
  /// current** — a resend rotates the token, so the copy has to say so.
  resent,

  // -- unresolved: an email may already have been delivered -------------------
  /// `DELIVERY_ACCEPTED_STATUS_UNCONFIRMED`, normally HTTP 202.
  deliveryUnconfirmed,

  /// The request was sent and nothing came back in time.
  timedOut,

  /// An answer arrived that this build could not read.
  unreadableAnswer,

  /// An unexpected fault after the request left. Not a claim about the network.
  unexpected,

  // -- definite: nothing was delivered ----------------------------------------
  /// `DELIVERY_FAILED`. The provider did not accept the message.
  deliveryFailed,

  /// `INVALID_REQUEST`, or a `NOT_SENT` code this build does not recognise.
  invalidRequest,

  /// `INVALID_ROLE_SHOP_COMBINATION`.
  invalidRoleShopCombination,

  /// `AUTH_REQUIRED`, or no usable session on this device.
  signedOut,

  /// `ACCESS_DENIED`.
  accessDenied,

  /// `INVITATION_CONFLICT`.
  invitationConflict,

  /// `RETAILER_INACTIVE`.
  retailerInactive,

  /// `FEATURE_DISABLED`.
  featureDisabled,

  /// `NOT_CONFIGURED`.
  notConfigured,

  /// `METHOD_NOT_ALLOWED` or `INTERNAL_ERROR`. Both are faults on the far side
  /// rather than anything the person did.
  serviceFault,

  /// The request never reached the backend.
  ///
  /// The only member whose copy mentions the connection.
  network;

  /// The invitation is on its way and the form's work is done.
  bool get isSuccess =>
      this == RetailerInviteStaffNotice.sent ||
      this == RetailerInviteStaffNotice.resent;

  /// **An email may already have been delivered, and this build cannot say.**
  ///
  /// The behaviour that follows is the whole reason the group exists: the write
  /// is never repeated automatically, the form is emptied rather than left armed
  /// (see [RetailerInviteStaffCubit] for why), and the copy points at the
  /// invitation history instead of at the submit button.
  bool get isUnresolved =>
      this == RetailerInviteStaffNotice.deliveryUnconfirmed ||
      this == RetailerInviteStaffNotice.timedOut ||
      this == RetailerInviteStaffNotice.unreadableAnswer ||
      this == RetailerInviteStaffNotice.unexpected;

  /// The entered values are kept so the person can review and try again.
  bool get preservesForm => !isSuccess && !isUnresolved;
}

/// The Invite Staff form's state.
///
/// Immutable, and holds **no raw response map** — every value is either
/// something a person typed, a parsed domain type, or a discriminant.
///
/// It holds no invitation id, token, token hash, normalized email, expiry,
/// Retailer organization id, membership id, HTTP status or backend message,
/// because none of those exists anywhere on the path that fills it.
final class RetailerInviteStaffState extends Equatable {
  const RetailerInviteStaffState({
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.role,
    this.selectedShopIds = const <String>{},
    this.shopsPhase = RetailerInviteShopsPhase.initial,
    this.shops,
    this.shopsProblem,
    this.isSubmitting = false,
    this.fieldProblems =
        const <RetailerStaffInvitationField, RetailerStaffInvitationProblem>{},
    this.notice,
    this.historyRereadFailed = false,
    this.formRevision = 0,
  });

  final String firstName;
  final String lastName;
  final String email;

  /// Null until a role is chosen. There is no default: picking one for somebody
  /// is picking what a colleague will be able to do.
  final RetailerStaffInvitationRole? role;

  /// The shop ids currently ticked.
  ///
  /// Kept across a switch to Retailer Manager so switching back restores the
  /// selection, and **never sent** for a Manager — see [submittableShopIds].
  final Set<String> selectedShopIds;

  final RetailerInviteShopsPhase shopsPhase;

  /// The options, or null when none has been read. Null is not an empty estate
  /// and is never rendered as one.
  final List<RetailerAssignableShop>? shops;

  /// Why the options could not be read. A discriminant; never backend text.
  final RetailerReadProblem? shopsProblem;

  final bool isSubmitting;

  /// One problem per offending control, from the request's own validation.
  final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
  fieldProblems;

  /// What to tell the person about the last submission, or null for none.
  final RetailerInviteStaffNotice? notice;

  /// The send stands, but the canonical invitation history could not be
  /// re-read afterwards.
  ///
  /// Never rendered as a send failure. It is an additional sentence beside the
  /// send's own notice, and the action it offers is a **read** — refresh the
  /// history — never another send.
  final bool historyRereadFailed;

  /// Bumped whenever the fields are reset from underneath the widgets.
  ///
  /// The text controllers live in the form widget, so "the cubit emptied the
  /// form" has to be observable as a change rather than inferred from values
  /// that may legitimately already have been empty.
  final int formRevision;

  /// The ids that may actually be submitted.
  ///
  /// Two rules, both structural rather than remembered:
  ///
  /// * a Retailer Manager submits **nothing**, whatever is ticked, so a stale
  ///   selection cannot ride along on a role the contract forbids it for;
  /// * a Sales Staff selection is intersected with the options the **backend**
  ///   returned, so an id that is no longer assignable — or was never in a
  ///   response at all — cannot be sent. Nothing here fabricates an id, and a
  ///   shop's name or its position in the list is never used as one.
  List<String> get submittableShopIds {
    if (role?.carriesShops != true) {
      return const <String>[];
    }
    final List<RetailerAssignableShop> options =
        shops ?? const <RetailerAssignableShop>[];
    return options
        .where(
          (RetailerAssignableShop shop) => selectedShopIds.contains(shop.id),
        )
        .map((RetailerAssignableShop shop) => shop.id)
        .toList(growable: false);
  }

  /// Whether the shop picker belongs on screen at all.
  bool get showsShopPicker => role?.carriesShops == true;

  /// The read answered and this Retailer has no ACTIVE shops.
  ///
  /// Distinct from a refusal, which arrives as [shopsProblem] — the deployed
  /// function raises rather than returning nothing, precisely so an Owner is
  /// never told their Retailer is empty when they were refused.
  bool get isShopsEmpty =>
      shopsPhase == RetailerInviteShopsPhase.ready && (shops?.isEmpty ?? false);

  bool get isShopsLoading => shopsPhase == RetailerInviteShopsPhase.loading;

  bool get hasShopsFailed => shopsPhase == RetailerInviteShopsPhase.failed;

  /// The problem to show under one control, or null.
  RetailerStaffInvitationProblem? problemFor(
    RetailerStaffInvitationField field,
  ) => fieldProblems[field];

  RetailerInviteStaffState copyWith({
    String? firstName,
    String? lastName,
    String? email,
    RetailerStaffInvitationRole? role,
    Set<String>? selectedShopIds,
    RetailerInviteShopsPhase? shopsPhase,
    List<RetailerAssignableShop>? shops,
    RetailerReadProblem? shopsProblem,
    bool? isSubmitting,
    Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>?
    fieldProblems,
    RetailerInviteStaffNotice? notice,
    bool? historyRereadFailed,
    int? formRevision,
    bool clearShopsProblem = false,
    bool clearNotice = false,
  }) {
    return RetailerInviteStaffState(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      // A role, once chosen, is never unset by a copy — only by a reset, which
      // builds a fresh state rather than copying this one.
      role: role ?? this.role,
      selectedShopIds: selectedShopIds ?? this.selectedShopIds,
      shopsPhase: shopsPhase ?? this.shopsPhase,
      shops: shops ?? this.shops,
      // Explicit clears, because `copyWith(x: null)` cannot be told from "leave
      // it alone" in Dart — and a stale problem surviving a successful retry
      // would leave an error notice above working options.
      shopsProblem: clearShopsProblem
          ? null
          : (shopsProblem ?? this.shopsProblem),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      fieldProblems: fieldProblems ?? this.fieldProblems,
      notice: clearNotice ? null : (notice ?? this.notice),
      historyRereadFailed: historyRereadFailed ?? this.historyRereadFailed,
      formRevision: formRevision ?? this.formRevision,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    firstName,
    lastName,
    email,
    role,
    selectedShopIds,
    shopsPhase,
    shops,
    shopsProblem,
    isSubmitting,
    fieldProblems,
    notice,
    historyRereadFailed,
    formRevision,
  ];
}
