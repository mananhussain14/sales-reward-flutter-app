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
enum RetailerMemberStatus {
  invited('INVITED', 'Invited'),
  active('ACTIVE', 'Active'),
  suspended('SUSPENDED', 'Suspended'),
  deactivated('DEACTIVATED', 'Deactivated'),

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

/// One row of `public.list_retailer_staff_members()`.
///
/// ## What is deliberately not modelled
///
/// The contract returns `membership_id` and `shop_ids`, and **neither appears
/// here**. Both are UUIDs, both are internal addresses, and this milestone is
/// read-only with no operation that could use one: there is no member detail
/// screen, no role change, no activation, no shop reassignment. Carrying them
/// would put identifiers on a phone for no purpose, and the first write feature
/// to find them lying around would be tempted to address a row from a stale
/// list.
///
/// `shop_names` is carried, because a person needs to know which shops a member
/// works in. The ids that accompany those names are dropped at the parser.
///
/// ## `roleCode` is carried but never displayed
///
/// The backend returns both `role_code` (`SALES_STAFF`) and `role_name`
/// (`Sales Staff`). Only the name reaches a screen. The code is kept because it
/// is the stable value across renames — useful for grouping and for a future
/// write feature — and it is deliberately excluded from search and from every
/// label so an internal token cannot leak into the UI through a search match.
final class RetailerStaffMember extends Equatable {
  const RetailerStaffMember({
    required this.firstName,
    required this.lastName,
    required this.roleCode,
    required this.roleName,
    required this.status,
    required this.shopNames,
    required this.joinedAt,
    required this.createdAt,
  });

  /// `profiles.first_name`. `NOT NULL` and non-blank in the schema.
  final String firstName;

  /// `profiles.last_name`. `NOT NULL` and non-blank in the schema.
  final String lastName;

  /// `roles.code` — internal. Never rendered, never searched.
  final String roleCode;

  /// `roles.name` — the label a person reads.
  final String roleName;

  final RetailerMemberStatus status;

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

  @override
  List<Object?> get props => <Object?>[
    firstName,
    lastName,
    roleCode,
    roleName,
    status,
    shopNames,
    joinedAt,
    createdAt,
  ];
}
