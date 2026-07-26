import 'package:supabase_flutter/supabase_flutter.dart';

/// The one Vendor company/profile RPC, named exactly once.
const String vendorAdministratorProfileRpc = 'get_my_vendor_profile';

/// Invokes `get_my_vendor_profile()`.
///
/// ## Zero arguments, and that is the whole contract
///
/// The typedef takes nothing, because the function takes nothing. There is no
/// auth user id, profile id, membership id, organization id, tenant id, role
/// selector, permission selector, profile selector, organization selector,
/// status or date range to express at this boundary — so there is none to get
/// wrong, and no future edit can quietly add one without changing this type.
///
/// Two questions are answered server-side and neither is answerable from here:
///
/// * **Whose profile** — from `auth.uid()`, compared against the verified request
///   claims rather than against a parameter. A caller cannot ask for a
///   colleague's profile because there is no way to name one.
/// * **Which Vendor** — derived through `get_vendor_super_admin_context()`, with
///   the same lowest-organization-id tie-break every other Vendor RPC applies.
///   That is also the resolver behind the organization name the session already
///   holds, which is why the company name on screen and the roles on screen
///   describe the same organization without either being sent to the other.
typedef VendorAdministratorProfileInvoker = Future<Object?> Function();

/// The production invoker.
///
/// The only place in the application that names this RPC and touches the Supabase
/// client for it. Note the call site: a function name, and nothing else at all.
///
/// **No `params` map is passed, not even an empty one.** An empty map would be
/// harmless today and would be the obvious place for someone to later add "just
/// one" selector — a profile id above all, which would turn a self-read into a
/// way to read a colleague. Omitting it makes the zero-argument shape visible at
/// the call site rather than implied by an absence of keys.
VendorAdministratorProfileInvoker supabaseVendorAdministratorProfileInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(vendorAdministratorProfileRpc);
}

/// Reads the profile the signed-in Vendor Super Admin is entitled to — their own.
///
/// Thin by design: it performs the call and lets exceptions propagate. Turning an
/// exception into a `Failure` is the repository's job and turning a body into a
/// domain object is the parser's, so each of the three has one reason to change.
///
/// **No table is ever read here.** There is no query against `organizations`,
/// `profiles`, `organization_members`, `member_roles`, `roles`, `permissions`,
/// `role_permissions` or `auth.users` under any spelling. The name composition,
/// the ACTIVE-role filter, the role ordering, the self predicate and the tenant
/// predicate all happen in SQL — and reproducing any of them here would put a
/// second definition of "who am I" into a client free to drift from the database.
///
/// **The Vendor user directory is not consulted either.** `list_vendor_users()`
/// returns every colleague's name, statuses and roles but carries no marker for
/// which row is the caller, so identifying oneself in it would mean matching a
/// locally composed display name — which breaks for two colleagues who share a
/// name, and puts every colleague's private status on the wire to render one fact
/// about oneself. That is the anti-pattern this contract exists to remove.
///
/// **No write.** The function is `STABLE` and contains no insert, update or
/// delete, and none is named here. Reading one's own name is not an event, so
/// this call records no audit row of its own.
final class VendorProfileRpcDataSource {
  const VendorProfileRpcDataSource({
    required VendorAdministratorProfileInvoker administratorProfile,
  }) : _administratorProfile = administratorProfile;

  /// Builds the data source against a live client.
  factory VendorProfileRpcDataSource.forClient(SupabaseClient client) {
    return VendorProfileRpcDataSource(
      administratorProfile: supabaseVendorAdministratorProfileInvoker(client),
    );
  }

  final VendorAdministratorProfileInvoker _administratorProfile;

  /// The whole profile, in one round trip.
  Future<Object?> fetchAdministratorProfile() => _administratorProfile();
}
