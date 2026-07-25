import 'vendor_role_copy.dart';

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `12 Mar 2026`, in the device's own time zone.
///
/// Hand-rolled rather than `package:intl`, matching the receipt, Retailer and
/// User features: the application ships one locale, so a localisation dependency
/// would be weight for a handful of strings. Timestamps arrive as UTC from the
/// parser and are converted here — the single place a time zone is applied.
///
/// No time of day: "when was this definition created" is a date-grained fact,
/// and a minute would imply a precision the question does not have.
String formatRoleDate(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// `6 permissions mapped` / `1 permission mapped` / `No permissions mapped`.
///
/// **"Mapped" is doing the work.** The count says what the definition holds, not
/// what anybody can currently do with it: an inactive role reports its mappings
/// truthfully and grants none of them. Nothing in this phrase changes with the
/// role's status, because the number does not.
String formatPermissionCount(int count) {
  if (count == 0) {
    return 'No permissions mapped';
  }
  return count == 1 ? '1 permission mapped' : '$count permissions mapped';
}

/// `3 members in your Vendor` / `1 member in your Vendor` /
/// `No members in your Vendor`.
///
/// The possessive is deliberate and load-bearing. The role definition is shared
/// platform-wide, so a phrase like "3 members" beside a global row would read as
/// a platform-wide figure; it is not. It counts memberships of the **caller's
/// own Vendor** and of no other organization, which is also why a Retailer role
/// legitimately reads zero here rather than being hidden.
///
/// It is an assignment count, not a headcount of active staff: the backend
/// filters neither membership status nor role status, so a retired definition
/// still held by four people reports four.
String formatAssignedMembers(int count) {
  if (count == 0) {
    return 'No members in your Vendor';
  }
  return count == 1
      ? '1 member in your Vendor'
      : '$count members in your Vendor';
}

/// A nullable description, as something a screen can always render.
///
/// Null is a real answer — several catalogue roles have no description — and the
/// honest rendering of it is a neutral phrase, never a sentence invented from
/// the role name and never a blank that leaves a reader wondering whether the
/// value failed to load.
String formatDescription(String? description) =>
    description ?? VendorRoleCopy.noDescription;

/// The same, for a permission's own nullable description.
String formatPermissionDescription(String? description) =>
    description ?? VendorRoleCopy.noPermissionDescription;
