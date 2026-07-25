import 'package:equatable/equatable.dart';

/// One row of `public.list_vendor_role_permissions(uuid)` — a permission
/// **mapped to** the selected role.
///
/// Two fields, and they are exactly the two the web `/roles` page renders
/// through one shared component: the name over the description.
///
/// ## What is deliberately absent, and why each is refused
///
/// * **The permission code.** `permissions.code` is authorization vocabulary —
///   the same literals `has_organization_permission()` matches on — and the web
///   data module says in terms that it is *"deliberately never selected"*.
///   Publishing it to a client would invite the client to reason about
///   authorization it must never compute.
/// * **The module.** `permissions.module` is a real `NOT NULL` column, and
///   grouping a long list by it would be a better screen. But the web neither
///   displays nor groups by it, the stored values are SCREAMING_CASE internal
///   category labels rather than display strings, and the backend does not
///   return it. When a design actually groups permissions, `module` is added
///   deliberately with a display mapping — not inferred now.
/// * **A status.** Neither `permissions` nor `role_permissions` has one, and no
///   migration adds one, so an inactive assigned permission is unrepresentable.
///   There is therefore no per-permission badge in this feature. What *can* make
///   a mapping ineffective is the **role's** status, which is rendered beside
///   this list and never derived from it.
/// * **An id.** The permission id is ordered *on* by the backend as a tie-break
///   and never returned; the `role_permissions` mapping has no id of its own —
///   its primary key is the pair.
///
/// ## There is no identity here to key a list by
///
/// Because no id is returned, a widget key can only be positional. That is safe
/// precisely because the list is read-only, never reordered, never filtered and
/// never re-sorted: the order the backend sent is the order rendered.
final class VendorRolePermission extends Equatable {
  const VendorRolePermission({required this.name, required this.description});

  /// The display name. Never null, never blank — never the code, which is not
  /// returned at all.
  final String name;

  /// The stored description, or **null** when the permission has none. Never
  /// fabricated and never replaced by the name.
  final String? description;

  @override
  List<Object?> get props => <Object?>[name, description];
}
