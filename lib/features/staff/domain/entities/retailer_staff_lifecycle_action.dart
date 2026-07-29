import 'package:equatable/equatable.dart';

import 'retailer_staff_lifecycle_status.dart';
import 'retailer_staff_member.dart';

/// The two role codes whose lifecycle this control manages.
///
/// `RETAILER_OWNER` is deliberately absent. An Owner is the tenant's root of
/// authority — their membership is what `resolve_retailer_owner_organization`
/// resolves — so deactivating one can strand a Retailer with nobody able to
/// reactivate anybody, including the person just deactivated. Owner lifecycle
/// belongs to the Vendor-side milestone, whose actor sits **outside** the tenant
/// and therefore cannot lock the tenant out of itself.
const Set<String> eligibleStaffLifecycleRoles = <String>{
  'RETAILER_MANAGER',
  'SALES_STAFF',
};

/// What the lifecycle control may offer for one **current** membership status.
///
/// Pure: no I/O, no Supabase, no Flutter. Every rule here is applied again,
/// independently, by `public.set_retailer_staff_membership_status()` under the
/// caller's own token — which derives the Retailer from `auth.uid()` through
/// `resolve_retailer_member_organization('RETAILER_STAFF_MANAGE')`, locks the
/// target row, reads its **complete ACTIVE role set** and requires it to be
/// exactly `{RETAILER_MANAGER}` or `{SALES_STAFF}`, refuses the caller's own
/// membership by user id, and refuses any current status that is not `ACTIVE` or
/// `DEACTIVATED`.
///
/// This type exists so a control that could only ever be refused is never
/// rendered — **not** so the client can be trusted.
///
/// ## Every label and the requested status live in one table
///
/// The card verb, the dialog title, the confirm label, the pending label, the
/// status word and the value destined for `p_status` are all members of the same
/// record. That is what makes it impossible for a button to read "Deactivate"
/// while the request asks for `ACTIVE`. The requested status is emphatically
/// **not** derived from any of the labels.
final class RetailerStaffLifecycleAction extends Equatable {
  const RetailerStaffLifecycleAction._({
    required this.currentStatus,
    required this.displayLabel,
    required this.actionLabel,
    required this.dialogTitle,
    required this.confirmLabel,
    required this.pendingLabel,
    required this.requestedStatus,
  });

  /// The status the membership holds now.
  final RetailerStaffLifecycleStatus currentStatus;

  /// The user-facing word for [currentStatus]. `Active` or `Inactive` — never
  /// `Deactivated`, and never a raw backend token.
  final String displayLabel;

  /// The card verb. Short, because the card already names the person.
  final String actionLabel;

  /// The dialog heading. Carries the noun, because a dialog is read on its own.
  final String dialogTitle;

  /// The dialog's primary action.
  final String confirmLabel;

  /// The button label while the request is in flight.
  final String pendingLabel;

  /// The stored value that will be sent as `p_status`. Never a display word.
  final RetailerStaffLifecycleStatus requestedStatus;

  /// Whether this action stands the member down. Used to choose copy and an
  /// icon, never to derive the requested status.
  bool get isDeactivation =>
      requestedStatus == RetailerStaffLifecycleStatus.deactivated;

  /// The complete transition table: the two statuses this operation owns, and
  /// what each offers.
  static const Map<RetailerStaffLifecycleStatus, RetailerStaffLifecycleAction>
  _transitions = <RetailerStaffLifecycleStatus, RetailerStaffLifecycleAction>{
    RetailerStaffLifecycleStatus.active: RetailerStaffLifecycleAction._(
      currentStatus: RetailerStaffLifecycleStatus.active,
      displayLabel: 'Active',
      actionLabel: 'Deactivate',
      dialogTitle: 'Deactivate staff',
      confirmLabel: 'Deactivate staff',
      pendingLabel: 'Deactivating…',
      requestedStatus: RetailerStaffLifecycleStatus.deactivated,
    ),
    RetailerStaffLifecycleStatus.deactivated: RetailerStaffLifecycleAction._(
      currentStatus: RetailerStaffLifecycleStatus.deactivated,
      displayLabel: 'Inactive',
      actionLabel: 'Reactivate',
      dialogTitle: 'Reactivate staff',
      confirmLabel: 'Reactivate staff',
      pendingLabel: 'Reactivating…',
      requestedStatus: RetailerStaffLifecycleStatus.active,
    ),
  };

  /// The action offered for a membership currently in [status], or **null**.
  ///
  /// Null for every value outside the pair, written as a positive `switch` so a
  /// member added to [RetailerMemberStatus] is excluded by default rather than
  /// falling through into a supported transition.
  static RetailerStaffLifecycleAction? forStatus(RetailerMemberStatus status) {
    final RetailerStaffLifecycleStatus? lifecycle = switch (status) {
      RetailerMemberStatus.active => RetailerStaffLifecycleStatus.active,
      RetailerMemberStatus.deactivated =>
        RetailerStaffLifecycleStatus.deactivated,
      RetailerMemberStatus.invited => null,
      RetailerMemberStatus.suspended => null,
      RetailerMemberStatus.unknown => null,
    };
    if (lifecycle == null) {
      return null;
    }
    return _transitions[lifecycle];
  }

  @override
  List<Object?> get props => <Object?>[
    currentStatus,
    displayLabel,
    actionLabel,
    dialogTitle,
    confirmLabel,
    pendingLabel,
    requestedStatus,
  ];
}

/// Which roster rows may be acted on at all.
///
/// ## Why a row predicate is not enough, and must never be used alone
///
/// `public.list_retailer_staff_members()` joins `member_roles` and `roles`
/// **without `DISTINCT`**, so a membership holding two ACTIVE roles is emitted as
/// **two rows sharing one `membership_id`**, each carrying a single `role_code`.
/// This client's parser produces one [RetailerStaffMember] per row, so those two
/// rows become two entities with the same [RetailerStaffMember.membershipId].
///
/// Judging such a row on its own is wrong in the most dangerous direction:
///
/// * the `SALES_STAFF` row of a Manager+Sales member looks perfectly eligible,
///   and the control would be offered for a target the RPC refuses outright —
///   it compares the **complete** ACTIVE role set to a single-element array;
/// * worse, for a member holding `RETAILER_OWNER` **alongside** another role the
///   Owner row is excluded by the role test but the other row is not — so the
///   Owner exclusion, the headline rule of this feature, would be defeated by an
///   extra role assignment.
///
/// So eligibility is decided **per membership, over the whole roster**, and a
/// membership is eligible only when:
///
/// 1. it is represented by **exactly one** row — any duplicate hides the control
///    on **every** occurrence, whatever the other row says; and
/// 2. that row is itself an eligible target: role exactly `RETAILER_MANAGER` or
///    `SALES_STAFF`, and status exactly `ACTIVE` or `DEACTIVATED`.
///
/// Rule 1 is deliberately blind to **why** a membership appears twice. A second
/// role, a historical duplicate and malformed data all produce the same answer —
/// hidden — because this client cannot tell them apart and the only safe reading
/// of an ambiguous roster is that the operation is not offered.
///
/// ## The self-target rule, and how it is actually achieved
///
/// `list_retailer_staff_members()` returns no `user_id` and no "this row is you"
/// flag, so this layer **cannot** identify the caller's own roster row — and
/// nothing here pretends otherwise.
///
/// It does not need to. `RETAILER_STAFF_MANAGE` is mapped to `RETAILER_OWNER`
/// alone, so every caller who can reach this operation is an Owner, and the role
/// rule refuses **every** `RETAILER_OWNER` row — including, necessarily, the
/// caller's own. The self case is covered transitively by the Owner exclusion,
/// which is the strictly wider rule.
///
/// The database does **not** rely on that coincidence: it compares the target's
/// user id to `auth.uid()` as a separate, explicit check, so the rule still holds
/// on the day `RETAILER_STAFF_MANAGE` is granted to `RETAILER_MANAGER`. That is
/// precisely why the RPC, and not this file, is the authority.
abstract final class RetailerStaffLifecycleEligibility {
  /// The membership ids in [roster] for which the control may be offered.
  ///
  /// Ids are compared trimmed and lower-cased. The parser already lower-cases
  /// `membership_id`, so this is belt and braces — and it means two spellings of
  /// one id can never be counted as two memberships, which would turn a genuine
  /// duplicate into two apparently-unique rows.
  static Set<String> eligibleMemberships(Iterable<RetailerStaffMember> roster) {
    final Map<String, List<RetailerStaffMember>> rowsById =
        <String, List<RetailerStaffMember>>{};

    for (final RetailerStaffMember member in roster) {
      final String id = member.membershipId.trim().toLowerCase();
      // A blank id cannot address anything and must never become a key a later
      // lookup could match by accident.
      if (id.isEmpty) {
        continue;
      }
      rowsById.putIfAbsent(id, () => <RetailerStaffMember>[]).add(member);
    }

    final Set<String> eligible = <String>{};
    for (final MapEntry<String, List<RetailerStaffMember>> entry
        in rowsById.entries) {
      if (entry.value.length != 1) {
        // Rule 1. A duplicate hides the control on every occurrence.
        continue;
      }
      if (!_isEligibleRow(entry.value.first)) {
        continue;
      }
      eligible.add(entry.key);
    }
    return eligible;
  }

  /// Whether one row is an eligible target, ignoring duplication.
  ///
  /// Never used alone — [eligibleMemberships] applies it only after the
  /// exactly-one-row rule. Private for that reason: a caller reaching for a row
  /// predicate is a caller about to reintroduce the multi-role defect.
  static bool _isEligibleRow(RetailerStaffMember member) {
    if (!eligibleStaffLifecycleRoles.contains(member.roleCode)) {
      return false;
    }
    return RetailerStaffLifecycleAction.forStatus(member.status) != null;
  }

  /// The action offered for [member], or **null** when none is.
  ///
  /// [eligibleMemberships] must have been built from the **same** roster this
  /// member came from — a set built from a different read would answer a
  /// different question.
  static RetailerStaffLifecycleAction? actionFor(
    RetailerStaffMember member,
    Set<String> eligibleMemberships,
  ) {
    if (!eligibleMemberships.contains(
      member.membershipId.trim().toLowerCase(),
    )) {
      return null;
    }
    return RetailerStaffLifecycleAction.forStatus(member.status);
  }
}
