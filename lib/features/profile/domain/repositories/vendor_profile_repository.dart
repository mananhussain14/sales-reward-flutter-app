import '../../../../core/result/read_result.dart';
import '../entities/vendor_administrator_profile.dart';

/// The signed-in Vendor administrator's own profile.
///
/// **One read, and it takes nothing.** `public.get_my_vendor_profile()` accepts
/// zero arguments: whose profile is answered comes from `auth.uid()`, and which
/// Vendor it is scoped to is derived server-side through
/// `get_vendor_super_admin_context()`. There is no identity, profile, membership,
/// organization, tenant, role, permission or status selector to model here,
/// which is why this interface has no parameters at all.
///
/// **Read-only.** There is no company edit, profile edit, name change, avatar
/// upload, password change or role assignment anywhere behind this interface —
/// the backend function is `STABLE` and this product has no write path for
/// company or profile data at all.
///
/// The company half of the screen is **not** here. The organization name comes
/// from the trusted Session / PortalContext the application already holds; adding
/// a company read to this interface would create a second source for it.
abstract interface class VendorProfileRepository {
  /// The caller's own display name and active Vendor role names.
  Future<ReadResult<VendorAdministratorProfile>> administratorProfile();
}
