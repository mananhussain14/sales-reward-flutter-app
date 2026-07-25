import 'package:equatable/equatable.dart';

import 'vendor_user_status.dart';

/// One row of `public.list_vendor_users()`.
///
/// Every field is a column the deployed function actually returns, and there is
/// no field it does not return. In particular there is **no** email, no mobile
/// number, no auth user id, no profile id, no organization id, no role id or
/// role code, no permission row or code, no password/provider/session metadata,
/// and no invitation field of any kind — because none of those is returned, and
/// several of them are refused on purpose.
///
/// ## `membershipId` is the address, and it is the right one
///
/// `organization_members.id` names one person **in one organization**, so
/// scoping it to the caller's Vendor is a predicate on the same row. A profile
/// id would not be: one profile may hold memberships in several organizations,
/// so it names a person globally and would have to be narrowed back down before
/// it could be authorized. An auth user id is worse still — it is the subject
/// Supabase Auth mints tokens for, and the contract neither returns nor accepts
/// it.
final class VendorUserSummary extends Equatable {
  const VendorUserSummary({
    required this.membershipId,
    required this.displayName,
    required this.profileStatus,
    required this.membershipStatus,
    required this.membershipCreatedAt,
    required this.joinedAt,
    required this.roleNames,
  });

  /// `organization_members.id` — the selector the detail read takes, and the
  /// segment the detail route carries.
  final String membershipId;

  /// First and last name, each trimmed and joined with one space, composed in
  /// SQL so the two clients cannot disagree about it. Never null, never blank.
  final String displayName;

  /// The person's own profile lifecycle state.
  final VendorUserStatus profileStatus;

  /// Their membership state in **this** Vendor — a separate fact from
  /// [profileStatus], rendered as its own badge.
  final VendorUserStatus membershipStatus;

  /// When the membership row was created. UTC.
  final DateTime membershipCreatedAt;

  /// When the person actually joined, or **null** when they have not — an
  /// `INVITED` row, typically.
  ///
  /// Null is a real answer and is never replaced by [membershipCreatedAt]:
  /// "recorded on" and "joined on" are different facts, and fabricating the
  /// second from the first would tell a Vendor somebody joined who never did.
  final DateTime? joinedAt;

  /// The display names of every **ACTIVE** role assigned through this
  /// membership, in the backend's `role name, role id` order.
  ///
  /// Never null. **May be empty**, and an empty list means exactly what it says:
  /// this person holds no active role. It is never a default and never a Super
  /// Admin — an absent role is the one place where a wrong guess would grant
  /// something.
  ///
  /// Names, never codes: `Vendor Super Admin` is what a screen renders;
  /// `VENDOR_SUPER_ADMIN` is internal authorization vocabulary, and the backend
  /// does not return it.
  final List<String> roleNames;

  /// Whether this person holds no active role at all.
  bool get hasNoRoles => roleNames.isEmpty;

  @override
  List<Object?> get props => <Object?>[
    membershipId,
    displayName,
    profileStatus,
    membershipStatus,
    membershipCreatedAt,
    joinedAt,
    roleNames,
  ];
}
