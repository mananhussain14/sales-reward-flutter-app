import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/auth/domain/entities/portal_context.dart';
import '../../../features/auth/domain/entities/portal_kind.dart';
import '../../../features/auth/presentation/bloc/session_bloc.dart';
import '../../../features/retailers/domain/repositories/vendor_retailer_repository.dart';
import '../../../features/retailers/presentation/vendor/cubit/vendor_retailer_detail_cubit.dart';
import '../../../features/retailers/presentation/vendor/cubit/vendor_retailer_list_cubit.dart';
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
/// ## Why the Retailer cubits are provided here rather than per route
///
/// Three reasons, and each of them is a bug avoided rather than a preference.
///
/// * **The directory survives a round trip into a Retailer.** Opening one and
///   coming back renders rows already held instead of re-reading them, which is
///   the difference between a back gesture and a reload.
/// * **The detail cubit is reachable by the session listener below.** A cubit
///   created inside the detail route would be a level *below* that listener,
///   which is precisely the subtree that must be emptied when the signed-in
///   person changes.
/// * **Duplicate reads are impossible rather than merely unlikely.** The list is
///   loaded once, here; `open` on the detail cubit ignores a repeat of the
///   relationship it is already showing, so a router refresh or a widget rebuild
///   issues no second RPC.
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
/// moment the session stops being *this* person's, both cubits are cleared: the
/// Retailer summaries, the open Retailer, its shops, and the search term and
/// status filter — which are private too, being fragments of Retailer names.
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

/// Drops every piece of private Retailer data the moment the session stops being
/// this person's, and reloads when a new Vendor session settles.
///
/// A [BlocListener] rather than a `BlocBuilder`, because the guarantee must not
/// depend on a frame being built.
///
/// This is not a second authentication listener: [SessionBloc] is the
/// application's existing session lifecycle, and this widget only reacts to it.
/// Subscribing to Supabase's auth stream again here would create a second
/// opinion about who is signed in, and two opinions is one too many.
class _SessionIsolation extends StatelessWidget {
  const _SessionIsolation({required this.child});

  final Widget child;

  static bool _isVendor(SessionState state) =>
      state is SessionActive &&
      state.portalContext.portalKind == PortalKind.vendorSuperAdmin;

  @override
  Widget build(BuildContext context) {
    return BlocListener<SessionBloc, SessionState>(
      // Fires on entering *and* on leaving the Vendor session. A Vendor→Vendor
      // switch passes through a non-active state, so it trips this twice: clear,
      // then reload under the new caller.
      listenWhen: (SessionState previous, SessionState current) =>
          _isVendor(previous) != _isVendor(current),
      listener: (BuildContext context, SessionState state) {
        final VendorRetailerListCubit list = context
            .read<VendorRetailerListCubit>();
        final VendorRetailerDetailCubit detail = context
            .read<VendorRetailerDetailCubit>();

        // Always cleared first, in both directions. A new Vendor session must
        // not read the previous one's rows even for the instant before its own
        // response arrives.
        list.clear();
        detail.clear();

        if (_isVendor(state)) {
          // Everything is read again from the backend under the new caller's own
          // identity. The open Retailer, if any, is re-read by the detail page,
          // which notices its cubit returning to `initial`.
          list.load();
        }
      },
      child: child,
    );
  }
}
