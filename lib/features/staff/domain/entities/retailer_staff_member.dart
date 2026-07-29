import 'package:equatable/equatable.dart';

/// A staff member's membership state.
///
/// The closed set is `organization_members_status_allowed` —
/// `check (status in ('INVITED', 'ACTIVE', 'SUSPENDED', 'DEACTIVATED'))`.
///
/// ## Which of these a caller sees is the backend's decision
///
/// `list_retailer_staff_members()` ends with `and (v_can_manage or m.status =
/// 'ACTIVE')`, where `v_can_manage` is
/// `has_organization_permission(retailer, 'RETAILER_STAFF_MANAGE')`. So a
/// Retailer Owner receives every status and a Retailer Manager receives only
/// `ACTIVE` rows — decided in SQL, per caller, on every call.
///
/// **This client must not re-implement that filter.** It renders exactly the
/// rows it was given. A Manager seeing only active members is not the app hiding
/// anything; it is the database answering a narrower question.
///
/// ## `DEACTIVATED` reads "Inactive", and `SUSPENDED` still reads "Suspended"
///
/// The database stores `DEACTIVATED`; the product says **Inactive**. The word has
/// to match the verb of the Owner control that writes it — Deactivate /
/// Reactivate — and `set_retailer_staff_membership_status` is the only writer of
/// this value for a membership. The *stored* token stays `DEACTIVATED`
/// everywhere: in the column, in `p_status`, and in the audit trail.
///
/// The two are deliberately **not** collapsed. `DEACTIVATED` is the reversible
/// state this control writes and clears; `SUSPENDED` is an administrative state
/// the RPC refuses in **both** directions and this milestone defines no owner
/// for. Rendering both as "Inactive" would put two words on screen that mean "the
/// button is there" and "the button can never be there", and a reader could not
/// tell which they were looking at.
///
/// > This is the mirror image of the Vendor Retailer milestone, and for the same
/// > reason. There, on `organizations` / `vendor_retailers`, `SUSPENDED` is the
/// > reversible state and reads "Inactive" while `DEACTIVATED` is terminal and
/// > reads "Deactivated". Here, on `organization_members`, it is `DEACTIVATED`
/// > that is reversible. The same stored token, two different facts, because they
/// > live in different tables under different operations.
///
/// The shared `SrStatusBadge` map in `core/` is untouched: it is reached by
/// profile and Vendor-side statuses this milestone has not analysed.
enum RetailerMemberStatus {
  invited('INVITED', 'Invited'),
  active('ACTIVE', 'Active'),
  suspended('SUSPENDED', 'Suspended'),
  deactivated('DEACTIVATED', 'Inactive'),

  /// A value this build does not know. Displayed neutrally, and nothing more.
  unknown('', 'Unknown');

  const RetailerMemberStatus(this.code, this.label);

  /// The backend token, or the empty string for [unknown]. Never rendered.
  final String code;

  /// The user-facing name.
  final String label;

  static RetailerMemberStatus fromCode(String raw) {
    for (final RetailerMemberStatus status in values) {
      if (status != unknown && status.code == raw) {
        return status;
      }
    }
    return unknown;
  }

  bool get isActive => this == active;
}

/// The one `role_code` this application acts on rather than merely displays.
///
/// Matched to decide whether a roster row may have its shop assignments edited,
/// because the deployed `set_retailer_staff_shop_assignments()` refuses any
/// membership that is not Sales Staff. Held here, on the domain entity, and
/// never rendered: `roleName` is what a screen shows.
///
/// The comparison is a **presentation gate**, not an authorization decision. The
/// function re-derives the target's role in SQL on every call and refuses on its
/// own terms; this only avoids offering a control whose sole outcome would be a
/// refusal.
const String salesStaffRoleCode = 'SALES_STAFF';

/// One row of `public.list_retailer_staff_members()`.
///
/// ## Why the two identifiers are carried now, and what bounds them
///
/// The read-portal milestone deliberately dropped `membership_id` and
/// `shop_ids`: it was read-only, nothing on a screen was addressable, and
/// identifiers lying around invite a later feature to address a row from a stale
/// list. That reasoning ended when `set_retailer_staff_shop_assignments()` was
/// deployed — the operation takes a membership id, and the desired shop set has
/// to start from the shops the backend says this person currently holds.
///
/// So both are carried, and both are bounded by that one purpose:
///
/// * [membershipId] is **never displayed**, never persisted, never typed,
///   derived from a name, or read from a route, and travels to exactly one
///   place — `p_membership_id`;
/// * [shopIds] is **never displayed** — [shopNames] is what a person reads — and
///   is used only to preselect the editor and to detect an unchanged selection.
///
/// A staleness note that matters: both are a snapshot of one read. The editor
/// re-reads the assignable shops when it opens and intersects, and the backend
/// re-derives everything from `auth.uid()` regardless, so holding either grants
/// nothing.
///
/// ## `shopIds` is the ACTIVE projection, not the whole truth
///
/// The contract's shop subquery ends `removed_at is null and s.status =
/// 'ACTIVE'`. A member may also hold a live assignment to a **suspended or
/// deactivated** shop, which this contract intentionally does not return and
/// this client therefore cannot see. Nothing here may be described as the
/// member's complete assignment history, and nothing here may be used to try to
/// remove an assignment that is not in it — the write preserves those hidden
/// rows by design.
///
/// ## `roleCode` is carried but never displayed
///
/// The backend returns both `role_code` (`SALES_STAFF`) and `role_name`
/// (`Sales Staff`). Only the name reaches a screen. The code is kept because it
/// is the stable value across renames — used by [isEditableSalesStaff] to decide
/// whether to offer the shop editor — and it is deliberately excluded from
/// search and from every label so an internal token cannot leak into the UI
/// through a search match.
final class RetailerStaffMember extends Equatable {
  const RetailerStaffMember({
    required this.membershipId,
    required this.firstName,
    required this.lastName,
    required this.roleCode,
    required this.roleName,
    required this.status,
    required this.shopIds,
    required this.shopNames,
    required this.joinedAt,
    required this.createdAt,
  });

  /// `organization_members.id`, lower-cased at the parser.
  ///
  /// The canonical address of this membership, and the **only** value that may
  /// become `p_membership_id`. Never rendered; never searched; never composed
  /// into a label, a semantics string or a widget key that could be read back.
  final String membershipId;

  /// `profiles.first_name`. `NOT NULL` and non-blank in the schema.
  final String firstName;

  /// `profiles.last_name`. `NOT NULL` and non-blank in the schema.
  final String lastName;

  /// `roles.code` — internal. Never rendered, never searched.
  final String roleCode;

  /// `roles.name` — the label a person reads.
  final String roleName;

  final RetailerMemberStatus status;

  /// The ids of the ACTIVE shops this member is currently assigned to,
  /// lower-cased at the parser.
  ///
  /// The backend builds this and [shopNames] from the same subquery with the
  /// same ordering, so they are positionally aligned — but **this client never
  /// pairs them**, and no code anywhere attributes a name to an id. The ids seed
  /// the editor's preselection; the names are what a person reads. A length
  /// mismatch therefore cannot mislabel anything.
  ///
  /// **Not the member's complete assignment set.** See the class doc: a live
  /// assignment to a non-ACTIVE shop is invisible on this contract, and the
  /// write preserves it.
  final List<String> shopIds;

  /// The names of the shops this member is currently assigned to.
  ///
  /// Live assignments only, to shops that are still ACTIVE and still belong to
  /// this Retailer — the backend's `removed_at is null and s.status = 'ACTIVE'`
  /// predicate. Ordered by the backend (`order by s.name, s.id`).
  ///
  /// **Empty is normal and not an error.** An Owner and a Manager hold no shop
  /// rows at all, so an empty list is the expected shape for them rather than a
  /// gap in the data.
  final List<String> shopNames;

  /// `organization_members.joined_at` — nullable.
  ///
  /// Null for a membership that was created but never completed acceptance. It
  /// is rendered as an absence, never as [createdAt]: the two mean different
  /// things and substituting one would state a joining date that never happened.
  final DateTime? joinedAt;

  /// `organization_members.created_at`. `NOT NULL`.
  ///
  /// Held so the roster has a stable secondary ordering key and so a future
  /// screen can distinguish "invited long ago" from "invited today" without a
  /// second read. Not currently displayed — [joinedAt] is the date a person
  /// cares about.
  final DateTime createdAt;

  /// The name to display, composed once here so every surface agrees.
  ///
  /// Both parts are `NOT NULL` and non-blank in the schema, so this is never
  /// blank and there is no placeholder branch to get wrong.
  String get fullName => '$firstName $lastName';

  /// Whether this member works in at least one shop.
  bool get hasShops => shopNames.isNotEmpty;

  /// Whether this row is one whose shop assignments may be offered for editing.
  ///
  /// Three conditions, all read from the backend's own answer:
  ///
  /// * **Sales Staff.** Only that role holds shop rows;
  ///   `set_retailer_staff_shop_assignments()` refuses every other membership.
  /// * **ACTIVE.** A suspended or deactivated membership is not editable, and
  ///   the function refuses it.
  /// * **Accepted.** [joinedAt] is null for a membership created by an
  ///   invitation nobody has accepted yet. Its shops come from the invitation,
  ///   and this operation is explicitly post-acceptance.
  ///
  /// **This is presentation scope, not authorization.** It exists so a control
  /// whose only possible outcome is a refusal is not put on screen. The database
  /// re-derives the caller, the Retailer, the permission and the target's own
  /// role and status on every call, and would refuse a hand-crafted request
  /// whatever any UI rendered.
  bool get isEditableSalesStaff =>
      roleCode == salesStaffRoleCode && status.isActive && joinedAt != null;

  @override
  List<Object?> get props => <Object?>[
    membershipId,
    firstName,
    lastName,
    roleCode,
    roleName,
    status,
    shopIds,
    shopNames,
    joinedAt,
    createdAt,
  ];
}
