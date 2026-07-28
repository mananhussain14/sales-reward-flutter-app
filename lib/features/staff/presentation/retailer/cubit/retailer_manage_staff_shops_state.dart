part of 'retailer_manage_staff_shops_cubit.dart';

/// Where the assignable-shops read has reached.
enum RetailerManageShopsOptionsPhase {
  /// Never requested. No editor is open.
  initial,

  /// A read is in flight.
  loading,

  /// Options are held — possibly zero, which is a real answer meaning this
  /// Retailer has no ACTIVE shops. A refusal is [failed], never this.
  ready,

  /// The read did not produce an answer.
  failed,
}

/// What the screen must tell the person about the last save.
///
/// Every member maps to one fixed sentence in [RetailerManageStaffShopsCopy].
/// None is ever built from a response, so no backend message, SQLSTATE,
/// PostgREST detail or hint, function or table name, membership id, shop id,
/// stack trace or project URL can reach a screen through this type.
///
/// The members are grouped by the only question that changes behaviour: **might
/// the change already have been committed?**
enum RetailerManageShopsNotice {
  // -- nothing was submitted -------------------------------------------------
  /// Local validation refused it. Nothing left the device.
  checkTheSelection,

  /// The member the editor was open for is no longer on the roster.
  targetUnavailable,

  // -- committed -------------------------------------------------------------
  /// The replacement committed and the counts describe what it changed.
  saved,

  // -- unresolved: the change may already have been committed ----------------
  /// The request was sent and nothing came back in time.
  timedOut,

  /// An answer arrived that this build could not read.
  unreadableAnswer,

  /// An unexpected fault after the request left. Not a claim about the network.
  unexpected,

  // -- definite: nothing was changed -----------------------------------------
  /// `42501`. Refused, absent, or another Retailer's — deliberately one member,
  /// because the backend gives one answer for all three.
  accessDenied,

  /// `23514`. The selection broke a rule the function enforces.
  invalidSelection,

  /// `55000`. The Retailer is not in a state that permits the change.
  retailerUnavailable,

  /// `22P02`. A value could not be read as an identifier. A defect in the
  /// request rather than anything the person did.
  invalidRequest,

  /// No usable session on this device.
  signedOut,

  /// The request never reached the backend.
  ///
  /// The only member whose copy mentions the connection.
  network;

  /// The change is committed and the editor's work is done.
  bool get isSuccess => this == RetailerManageShopsNotice.saved;

  /// **The change may already have been committed, and this build cannot say.**
  ///
  /// The behaviour that follows is the whole reason the group exists: the write
  /// is never repeated automatically, and the copy points at the roster instead
  /// of at the Save button.
  bool get isUnresolved =>
      this == RetailerManageShopsNotice.timedOut ||
      this == RetailerManageShopsNotice.unreadableAnswer ||
      this == RetailerManageShopsNotice.unexpected;
}

/// The Manage Shops editor's state.
///
/// Immutable, and holds **no raw Supabase map** — every value is either a parsed
/// domain type, a display string the contracts exist to return, or a
/// discriminant. It holds no HTTP status, no SQLSTATE and no backend message,
/// because none of those exists anywhere on the path that fills it.
///
/// It does hold two identifier collections — [membershipId] and the shop ids —
/// and both are bounded: never rendered, never persisted, never searched, and
/// dropped the moment the editor closes or the session changes.
final class RetailerManageStaffShopsState extends Equatable {
  const RetailerManageStaffShopsState({
    this.isOpen = false,
    this.membershipId,
    this.staffName,
    this.roleName,
    this.currentShopNames = const <String>[],
    this.rosterShopIds = const <String>{},
    this.baselineShopIds = const <String>{},
    this.selectedShopIds = const <String>{},
    this.optionsPhase = RetailerManageShopsOptionsPhase.initial,
    this.shops,
    this.optionsProblem,
    this.availabilityChanged = false,
    this.isSubmitting = false,
    this.fieldProblems =
        const <
          RetailerStaffShopAssignmentField,
          RetailerStaffShopAssignmentInputProblem
        >{},
    this.notice,
    this.change,
    this.rosterRereadFailed = false,
  });

  /// Whether the editor surface belongs on screen.
  final bool isOpen;

  /// `organization_members.id` for the open target, or null.
  ///
  /// **Never rendered.** It is an address: it travels to `p_membership_id` and
  /// nowhere else, and it is not put in a label, a semantics string, a widget
  /// key or a search index.
  final String? membershipId;

  /// The person's display name, for the editor's heading.
  final String? staffName;

  /// The role's display name — `roles.name`, never `role_code`.
  final String? roleName;

  /// The shop **names** this member currently holds, from the roster row.
  ///
  /// Display only, and the ACTIVE projection only. Never paired with an id.
  final List<String> currentShopNames;

  /// The roster's ACTIVE shop ids for the open target.
  ///
  /// Held separately from [selectedShopIds] because it is what the *backend*
  /// last said, not what the person has chosen: the selection is derived from it
  /// by intersecting with the options actually on offer.
  final Set<String> rosterShopIds;

  /// The selection the editor started from, once the options landed.
  ///
  /// The baseline for [hasChanges]. Distinct from [rosterShopIds]: a roster shop
  /// that is no longer assignable was never offered here, so leaving it out is
  /// not an edit the person made.
  final Set<String> baselineShopIds;

  /// The shop ids currently ticked. A `Set`, so a duplicate is impossible.
  final Set<String> selectedShopIds;

  final RetailerManageShopsOptionsPhase optionsPhase;

  /// The options, or null when none has been read. Null is not an empty estate
  /// and is never rendered as one.
  final List<RetailerAssignableShop>? shops;

  /// Why the options could not be read. A discriminant; never backend text.
  final RetailerReadProblem? optionsProblem;

  /// A shop that was ticked is no longer offered by the latest read.
  ///
  /// Blocks Save until the person has reviewed the selection, so an id that
  /// vanished can neither be submitted nor silently disappear.
  final bool availabilityChanged;

  final bool isSubmitting;

  /// One problem per offending part, from the request's own validation.
  final Map<
    RetailerStaffShopAssignmentField,
    RetailerStaffShopAssignmentInputProblem
  >
  fieldProblems;

  /// What to tell the person about the last save, or null for none.
  final RetailerManageShopsNotice? notice;

  /// The counts from the last committed save, for the change summary.
  ///
  /// A **change summary**, never a total: nothing may add [change] fields
  /// together and present the result as the number of shops this person works
  /// in. The roster is the authority on that.
  final RetailerStaffShopAssignmentChange? change;

  /// The save stands, but the canonical roster could not be re-read afterwards.
  ///
  /// Never rendered as a save failure. It is an additional sentence beside the
  /// save's own notice, and the action it offers is a **read** — refresh the
  /// roster — never another write.
  final bool rosterRereadFailed;

  // -- derived --------------------------------------------------------------

  /// The ids that may actually be submitted.
  ///
  /// Intersected with the options the **backend** returned and sorted, so an id
  /// that is no longer assignable — or was never in a response at all — cannot
  /// be sent. Nothing here fabricates an id, and a shop's name or its position
  /// in the list is never used as one.
  List<String> get submittableShopIds {
    final List<RetailerAssignableShop> options =
        shops ?? const <RetailerAssignableShop>[];
    return options
        .where(
          (RetailerAssignableShop shop) => selectedShopIds.contains(shop.id),
        )
        .map((RetailerAssignableShop shop) => shop.id)
        .toList(growable: false);
  }

  /// How many shops are ticked and could actually be sent.
  int get selectedCount => submittableShopIds.length;

  bool get isOptionsLoading =>
      optionsPhase == RetailerManageShopsOptionsPhase.loading;

  bool get hasOptionsFailed =>
      optionsPhase == RetailerManageShopsOptionsPhase.failed;

  bool get isOptionsReady =>
      optionsPhase == RetailerManageShopsOptionsPhase.ready;

  /// The read answered and this Retailer has no ACTIVE shops.
  ///
  /// Distinct from a refusal, which arrives as [optionsProblem] — the deployed
  /// function raises rather than returning nothing, precisely so an Owner is
  /// never told their Retailer is empty when they were refused.
  bool get isOptionsEmpty => isOptionsReady && (shops?.isEmpty ?? false);

  /// Whether the desired set differs from what the editor started with.
  bool get hasChanges =>
      !_sameShops(submittableShopIds.toSet(), baselineShopIds);

  /// Whether Save may be pressed.
  ///
  /// Every condition is a reason a write must not start, and each is enforced in
  /// the cubit as well — the button is the courtesy, the cubit's own refusal is
  /// the rule.
  bool get canSave =>
      isOpen &&
      !isSubmitting &&
      isOptionsReady &&
      !availabilityChanged &&
      selectedCount > 0 &&
      hasChanges;

  /// The problem to show under one control, or null.
  RetailerStaffShopAssignmentInputProblem? problemFor(
    RetailerStaffShopAssignmentField field,
  ) => fieldProblems[field];

  RetailerManageStaffShopsState copyWith({
    bool? isOpen,
    String? membershipId,
    String? staffName,
    String? roleName,
    List<String>? currentShopNames,
    Set<String>? rosterShopIds,
    Set<String>? baselineShopIds,
    Set<String>? selectedShopIds,
    RetailerManageShopsOptionsPhase? optionsPhase,
    List<RetailerAssignableShop>? shops,
    RetailerReadProblem? optionsProblem,
    bool? availabilityChanged,
    bool? isSubmitting,
    Map<
      RetailerStaffShopAssignmentField,
      RetailerStaffShopAssignmentInputProblem
    >?
    fieldProblems,
    RetailerManageShopsNotice? notice,
    RetailerStaffShopAssignmentChange? change,
    bool? rosterRereadFailed,
    bool clearOptionsProblem = false,
    bool clearNotice = false,
  }) {
    return RetailerManageStaffShopsState(
      isOpen: isOpen ?? this.isOpen,
      membershipId: membershipId ?? this.membershipId,
      staffName: staffName ?? this.staffName,
      roleName: roleName ?? this.roleName,
      currentShopNames: currentShopNames ?? this.currentShopNames,
      rosterShopIds: rosterShopIds ?? this.rosterShopIds,
      baselineShopIds: baselineShopIds ?? this.baselineShopIds,
      selectedShopIds: selectedShopIds ?? this.selectedShopIds,
      optionsPhase: optionsPhase ?? this.optionsPhase,
      shops: shops ?? this.shops,
      // Explicit clears, because `copyWith(x: null)` cannot be told from "leave
      // it alone" in Dart — and a stale problem surviving a successful retry
      // would leave an error notice above working options.
      optionsProblem: clearOptionsProblem
          ? null
          : (optionsProblem ?? this.optionsProblem),
      availabilityChanged: availabilityChanged ?? this.availabilityChanged,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      fieldProblems: fieldProblems ?? this.fieldProblems,
      notice: clearNotice ? null : (notice ?? this.notice),
      change: clearNotice ? null : (change ?? this.change),
      rosterRereadFailed: rosterRereadFailed ?? this.rosterRereadFailed,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    isOpen,
    membershipId,
    staffName,
    roleName,
    currentShopNames,
    rosterShopIds,
    baselineShopIds,
    selectedShopIds,
    optionsPhase,
    shops,
    optionsProblem,
    availabilityChanged,
    isSubmitting,
    fieldProblems,
    notice,
    change,
    rosterRereadFailed,
  ];
}

/// Order-insensitive set comparison, for
/// [RetailerManageStaffShopsState.hasChanges].
///
/// Hand-written rather than pulled from `package:collection`, which is not a
/// dependency of this application and which one comparison does not justify
/// making one. Order-insensitive on purpose: ticking A then B and ticking B then
/// A are the same desired set, and offering to save the second as a change would
/// be offering to write nothing.
bool _sameShops(Set<String> a, Set<String> b) =>
    a.length == b.length && a.every(b.contains);
