import 'package:equatable/equatable.dart';

/// The signed-in Vendor administrator, as `public.get_my_vendor_profile()`
/// describes them.
///
/// ## Two fields, and deliberately nothing else
///
/// The contract returns exactly `administrator_display_name text NOT NULL` and
/// `administrator_role_names text[] NOT NULL`, in that order, and nothing more.
/// There is no id, no email, no mobile number, no status, no timestamp, no role
/// code, no permission code, no metadata and no image reference — none of them is
/// returned, so none of them has a field here to land in. A later response that
/// carried one would have nowhere to put it.
///
/// ## It is not the company
///
/// In particular there is **no organization name and no organization id**. The
/// company half of the screen is served by `get_my_portal_context()`, which the
/// session already holds, and duplicating the name into this model would give the
/// one company field this product has two sources — the exact outcome the backend
/// contract was shaped to avoid. The two are composed by the screen, never merged
/// into one model.
final class VendorAdministratorProfile extends Equatable {
  const VendorAdministratorProfile({
    required this.displayName,
    required this.roleNames,
  });

  /// The caller's own name, **already composed by the database**.
  ///
  /// `trim(first_name) + one space + trim(last_name)`, performed in SQL so that
  /// no client is the third implementation of that rule. It is rendered exactly
  /// as received: never split, never trimmed and rejoined, and never swapped for
  /// the organization name.
  ///
  /// Never null and never blank — both source columns are `NOT NULL` with a
  /// `length(trim(...)) > 0` CHECK, and the parser refuses anything else rather
  /// than inventing a placeholder.
  final String displayName;

  /// The ACTIVE role definitions assigned to the caller's **own** membership in
  /// the derived Vendor, as the product names them.
  ///
  /// Display names, never codes: `Vendor Super Admin`, not `VENDOR_SUPER_ADMIN`.
  /// The codes are the literals the RLS policies match on and no read RPC in this
  /// schema returns one.
  ///
  /// The order is the backend's — `order by r.name, r.id` in SQL — and is
  /// preserved verbatim. Re-sorting in Dart would be a second, drifting
  /// definition of the order, under a collation the database does not use, and
  /// the mobile order would drift from the web's.
  ///
  /// May be empty only defensively. For an authorized caller it always carries at
  /// least the ACTIVE `Vendor Super Admin` assignment that authorized them —
  /// removing it denies the read rather than emptying the array.
  final List<String> roleNames;

  @override
  List<Object?> get props => <Object?>[displayName, roleNames];
}
