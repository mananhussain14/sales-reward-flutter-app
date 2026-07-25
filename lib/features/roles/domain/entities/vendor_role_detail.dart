import 'vendor_role_summary.dart';

/// The one row `public.get_vendor_role_detail(uuid)` returns.
///
/// ## Why this is an alias rather than a second class
///
/// The detail contract is the list contract **exactly** — not a superset.
/// `public.roles` has seven columns and five of them are already in the list;
/// the sixth is `code`, which the backend refuses because it is the literal the
/// RLS policies match on, and the seventh is `updated_at`, which the seed's
/// upsert rewrites on every run. There is genuinely nothing further to show
/// about a role definition, and the backend states the consequence plainly:
///
/// > *One Flutter model therefore deserializes both reads, and a future column
/// > has to be added to both or to neither.*
///
/// A second class with the same seven fields would be a second place to add that
/// future column, and only one of the two could be right. It would also invite
/// a conversion function between two structurally identical types — code whose
/// only effect is to give a compiler something to check.
///
/// So this is a name, not a shape. It exists because the data source, the
/// repository and the detail cubit all read better saying *detail* than saying
/// *summary*, and because the same precedent already exists in this application:
/// `VendorRetailerResult<T>` is an alias of `ReadResult<T>`.
///
/// > Contrast `VendorUserDetail`, which **is** its own class — the Vendor user
/// > detail read returns the list columns *plus* `deactivated_at`, so there the
/// > two shapes genuinely differ and collapsing them would have made "did the
/// > list give me a deactivation date?" unanswerable. Here they do not differ,
/// > and the backend's own pgTAP suite asserts that as a relationship between
/// > the two column lists rather than as two literals.
typedef VendorRoleDetail = VendorRoleSummary;
