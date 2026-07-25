import 'package:equatable/equatable.dart';

import 'vendor_user_status.dart';

/// The one row `public.get_vendor_user_detail(uuid)` returns.
///
/// ## Why this is a separate type from `VendorUserSummary`
///
/// The detail contract is the list contract **plus exactly one column**
/// ([deactivatedAt]) — the membership lifecycle timestamp a single-user screen
/// has room to show and a directory row does not. Every other column is
/// identical in name, type, meaning and nullability, and both the backend's
/// pgTAP suite and its static suite assert that as a *relationship* between the
/// two column lists rather than as two literals.
///
/// A single entity with one nullable extra would have made "did the list give me
/// a deactivation date, or is this membership live?" unanswerable, and every
/// screen would have had to know which read produced the value it holds. Two
/// types make that question unrepresentable instead.
///
/// ## What is deliberately absent
///
/// The auth user id; email; mobile number; password, provider, session or login
/// metadata of any kind; role ids, role codes, permission rows or permission
/// codes; the Vendor organization id; the profile id; any membership in another
/// organization; any invitation field, token or hash — there are no Vendor user
/// invitations at all; and any receipt, reward, sales or audit data.
final class VendorUserDetail extends Equatable {
  const VendorUserDetail({
    required this.membershipId,
    required this.displayName,
    required this.profileStatus,
    required this.membershipStatus,
    required this.membershipCreatedAt,
    required this.joinedAt,
    required this.deactivatedAt,
    required this.roleNames,
  });

  final String membershipId;
  final String displayName;
  final VendorUserStatus profileStatus;
  final VendorUserStatus membershipStatus;
  final DateTime membershipCreatedAt;

  /// When the person joined, or null when they have not. Never fabricated.
  final DateTime? joinedAt;

  /// When the membership was deactivated, or **null** for a live membership.
  ///
  /// Never fabricated, and never inferred from the status — nor the status from
  /// it. A screen shows the date when there is one and says nothing about a
  /// deactivation when there is not.
  final DateTime? deactivatedAt;

  /// Byte-identical in content and order to the list's array, including the
  /// ACTIVE-role filter — so the roles a user shows in the directory are the
  /// roles they show when opened.
  final List<String> roleNames;

  bool get hasNoRoles => roleNames.isEmpty;

  @override
  List<Object?> get props => <Object?>[
    membershipId,
    displayName,
    profileStatus,
    membershipStatus,
    membershipCreatedAt,
    joinedAt,
    deactivatedAt,
    roleNames,
  ];
}
