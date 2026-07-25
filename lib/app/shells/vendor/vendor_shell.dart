import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/auth/domain/entities/portal_context.dart';
import '../../../features/auth/domain/entities/portal_kind.dart';
import '../../../features/auth/presentation/bloc/session_bloc.dart';
import '../../../features/products/domain/repositories/vendor_product_repository.dart';
import '../../../features/products/presentation/vendor/cubit/vendor_product_detail_cubit.dart';
import '../../../features/products/presentation/vendor/cubit/vendor_product_list_cubit.dart';
import '../../../features/retailers/domain/repositories/vendor_retailer_repository.dart';
import '../../../features/retailers/presentation/vendor/cubit/vendor_retailer_detail_cubit.dart';
import '../../../features/retailers/presentation/vendor/cubit/vendor_retailer_list_cubit.dart';
import '../../../features/roles/domain/repositories/vendor_role_repository.dart';
import '../../../features/roles/presentation/vendor/cubit/vendor_role_detail_cubit.dart';
import '../../../features/roles/presentation/vendor/cubit/vendor_role_list_cubit.dart';
import '../../../features/users/domain/repositories/vendor_user_repository.dart';
import '../../../features/users/presentation/vendor/cubit/vendor_user_detail_cubit.dart';
import '../../../features/users/presentation/vendor/cubit/vendor_user_list_cubit.dart';
import '../base/role_shell_scaffold.dart';
import 'bloc/vendor_shell_bloc.dart';

/// The Vendor Super Admin application shell.
///
/// Owns its own [VendorShellBloc] and its own navigation model. It shares chrome
/// with the other three shells through [RoleShellScaffold], and shares nothing
/// else with them — no destinations, no BLoC instance, no conditional branches.
///
/// This role uses a drawer rather than a bottom bar because its web counterpart
/// carries six active modules; see `VendorNavigation` for the reasoning.
///
/// ## Why the feature cubits are provided here rather than per route
///
/// Three reasons, and each of them is a bug avoided rather than a preference.
/// They hold for the Retailer pair, the User pair and the Role pair alike.
///
/// * **A directory survives a round trip into one of its rows.** Opening a
///   Retailer, a user or a role and coming back renders rows already held
///   instead of re-reading them, which is the difference between a back gesture
///   and a reload.
/// * **The detail cubits are reachable by the session listener below.** A cubit
///   created inside a detail route would be a level *below* that listener,
///   which is precisely the subtree that must be emptied when the signed-in
///   person changes.
/// * **Duplicate reads are impossible rather than merely unlikely.** Each list is
///   loaded once, here; `open` on a detail cubit ignores a repeat of the id it
///   is already showing, so a router refresh or a widget rebuild issues no
///   second RPC.
///
/// All four list cubits load on creation, and `BlocProvider` builds each on
/// first read — so entering the Vendor shell does not fetch the user directory
/// until something asks for it, and opening Retailers never fetches Users,
/// Roles or Products.
///
/// ## Session isolation is enforced, not inferred from the widget lifetime
///
/// The obvious argument is that the router sends every `/vendor` route away when
/// the session changes, so the subtree unmounts and takes both cubits with it.
/// That argument is **not sound**, and the Sales Staff shell documents why: a
/// user switch emits `SessionInitial` and then `SessionActive` for the new
/// person within a single microtask drain, so no frame ever renders the
/// intermediate state and the route match list never actually leaves `/vendor/…`.
/// Worse here than there: switching from one Vendor Super Admin to another keeps
/// the location *inside the same role group*, so the guard has no reason to
/// redirect at all and the element is certain to survive.
///
/// [_SessionIsolation] closes that gap by listening to [SessionBloc] directly. A
/// listener runs on every emitted state whether or not a frame was built, so the
/// moment the session stops being *this* person's, all eight cubits are cleared:
/// the Retailer summaries, the open Retailer, its shops, the user summaries with
/// their names and roles, the open user, the role catalogue with **this
/// Vendor's own assigned member counts**, the open role and its permissions, the
/// product catalogue with its codes, barcodes, brands and assignment counts, the
/// open product with the names and statuses of the Retailers holding it, and
/// every search term and status filter — which are private too, being fragments
/// of Retailer, colleague and product names.
///
/// The role *definitions* are global and are the same for whoever signs in next.
/// The counts riding on the same rows are not, which is why the Role pair is
/// cleared rather than kept as a harmless cache. Nothing about the Product pair
/// is global: a catalogue belongs to exactly one Vendor.
class VendorShell extends StatelessWidget {
  const VendorShell({
    super.key,
    required this.child,
    required this.location,
    required this.portalContext,
  });

  final Widget child;
  final String location;
  final PortalContext portalContext;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<VendorShellBloc>(create: (_) => VendorShellBloc()),
        BlocProvider<VendorRetailerListCubit>(
          create: (BuildContext providerContext) => VendorRetailerListCubit(
            providerContext.read<VendorRetailerRepository>(),
          )..load(),
        ),
        // Not loaded on creation: it has nothing to load until a route names a
        // relationship. The detail page starts it, once.
        BlocProvider<VendorRetailerDetailCubit>(
          create: (BuildContext providerContext) => VendorRetailerDetailCubit(
            providerContext.read<VendorRetailerRepository>(),
          ),
        ),
        BlocProvider<VendorUserListCubit>(
          create: (BuildContext providerContext) =>
              VendorUserListCubit(providerContext.read<VendorUserRepository>())
                ..load(),
        ),
        BlocProvider<VendorUserDetailCubit>(
          create: (BuildContext providerContext) => VendorUserDetailCubit(
            providerContext.read<VendorUserRepository>(),
          ),
        ),
        // The role catalogue's *definitions* are global, but every row carries
        // this Vendor's own assigned member count — so the pair is owned and
        // cleared here exactly like the other two.
        BlocProvider<VendorRoleListCubit>(
          create: (BuildContext providerContext) =>
              VendorRoleListCubit(providerContext.read<VendorRoleRepository>())
                ..load(),
        ),
        BlocProvider<VendorRoleDetailCubit>(
          create: (BuildContext providerContext) => VendorRoleDetailCubit(
            providerContext.read<VendorRoleRepository>(),
          ),
        ),
        // The product catalogue is private Vendor data in its entirety — names,
        // codes, barcodes, brands and assignment counts — so the pair is owned
        // and cleared here exactly like the other three.
        BlocProvider<VendorProductListCubit>(
          create: (BuildContext providerContext) => VendorProductListCubit(
            providerContext.read<VendorProductRepository>(),
          )..load(),
        ),
        BlocProvider<VendorProductDetailCubit>(
          create: (BuildContext providerContext) => VendorProductDetailCubit(
            providerContext.read<VendorProductRepository>(),
          ),
        ),
      ],
      child: _SessionIsolation(
        child: RoleShellScaffold<VendorShellBloc>(
          location: location,
          portalContext: portalContext,
          child: child,
        ),
      ),
    );
  }
}

/// The identity a Vendor shell's private data belongs to.
///
/// Null whenever there is no active Vendor session at all — signed out, another
/// role, resolving, denied or unavailable. Otherwise the pair that together
/// decides whose data this is:
///
/// * the **authenticated subject** the context was resolved for, and
/// * the **trusted Vendor organization** the backend derived for them.
///
/// Both matter. The organization scopes what the RPCs return, so a change of
/// organization changes the rows. The subject scopes what is *personal* — a
/// half-typed search term is a fragment of a colleague's name, and it belongs to
/// the person who typed it even when two administrators share an organization.
///
/// Nothing here is inferred from an email, a display name, a role label or a
/// navigation path. The subject comes from [SessionActive.authUserId], which
/// `SessionBloc` sets from the value it already validated the resolution
/// against; the organization comes from the resolved context.
typedef _VendorIdentity = ({String? authUserId, String organizationId});

/// Drops every piece of private Vendor data the moment the session stops being
/// this person's, and reloads under whoever replaced them.
///
/// A [BlocListener] rather than a `BlocBuilder`, because the guarantee must not
/// depend on a frame being built.
///
/// This is not a second authentication listener: [SessionBloc] is the
/// application's existing session lifecycle, and this widget only reacts to it.
/// Subscribing to Supabase's auth stream again here would create a second
/// opinion about who is signed in, and two opinions is one too many.
///
/// ## Why the trigger is an identity and not a boolean
///
/// The obvious test — "did this stop being a Vendor session?" — cannot tell one
/// Vendor Super Admin from another. Under it, a **direct** `Vendor A → Vendor B`
/// transition is `true → true`, the listener never runs, and A's colleagues,
/// Retailers, open detail, search terms and filters stay in memory under B's
/// session.
///
/// Today `SessionBloc` happens to emit `SessionInitial` and `SessionResolving`
/// between the two, so a boolean would flip twice and appear to work. That is
/// an accident of another bloc's internals, not a guarantee: it is undocumented,
/// nothing enforces it, and a perfectly reasonable optimisation there would
/// silently reintroduce the leak here. **This listener therefore assumes no
/// intermediate state at all** — comparing identities makes the direct
/// transition detectable on its own terms.
///
/// It also makes the *absence* of a change detectable, which the boolean could
/// not: a re-emitted identical session — the shape a same-user token refresh
/// takes if it ever reaches this far — compares equal and is ignored, so it
/// costs no clear and no duplicate load.
class _SessionIsolation extends StatelessWidget {
  const _SessionIsolation({required this.child});

  final Widget child;

  /// The identity [state] carries, or null if it is not an active Vendor
  /// session.
  ///
  /// A Vendor session with no vendor block is treated as no identity: the
  /// context is not one this shell can hold data for, and returning something
  /// comparable would be inventing a tenant.
  static _VendorIdentity? _identityOf(SessionState state) {
    if (state is! SessionActive ||
        state.portalContext.portalKind != PortalKind.vendorSuperAdmin) {
      return null;
    }
    final VendorContext? vendor = state.portalContext.vendor;
    if (vendor == null) {
      return null;
    }
    return (
      authUserId: state.authUserId,
      organizationId: vendor.organizationId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SessionBloc, SessionState>(
      // Any change of identity, in either direction and with or without an
      // intermediate state: entering a Vendor session, leaving one, and
      // swapping one for another. Records compare by value, so this is a
      // structural comparison of the pair rather than of the state object.
      listenWhen: (SessionState previous, SessionState current) =>
          _identityOf(previous) != _identityOf(current),
      listener: (BuildContext context, SessionState state) {
        final VendorRetailerListCubit retailers = context
            .read<VendorRetailerListCubit>();
        final VendorRetailerDetailCubit retailerDetail = context
            .read<VendorRetailerDetailCubit>();
        final VendorUserListCubit users = context.read<VendorUserListCubit>();
        final VendorUserDetailCubit userDetail = context
            .read<VendorUserDetailCubit>();
        final VendorRoleListCubit roles = context.read<VendorRoleListCubit>();
        final VendorRoleDetailCubit roleDetail = context
            .read<VendorRoleDetailCubit>();
        final VendorProductListCubit products = context
            .read<VendorProductListCubit>();
        final VendorProductDetailCubit productDetail = context
            .read<VendorProductDetailCubit>();

        // Always cleared first, in every direction, and before anything is
        // requested for the new identity. A new Vendor session must not see the
        // previous one's rows even for the instant before its own response
        // arrives — and `clear()` on each cubit advances a request token, so a
        // response already in flight for the previous identity is dropped on
        // arrival rather than repopulating state that has just been emptied.
        retailers.clear();
        retailerDetail.clear();
        users.clear();
        userDetail.clear();
        roles.clear();
        roleDetail.clear();
        products.clear();
        productDetail.clear();

        if (_identityOf(state) != null) {
          // Read again from the backend under the new caller's own identity —
          // which is derived server-side from `auth.uid()`, not from anything
          // passed from here. An open Retailer or user, if any, is re-read by
          // its detail page, which notices its cubit returning to `initial`.
          retailers.load();
          users.load();
          roles.load();
          products.load();
        }
      },
      child: child,
    );
  }
}
