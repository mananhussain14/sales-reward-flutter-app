import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/auth/domain/entities/portal_context.dart';
import '../../../features/auth/domain/entities/portal_kind.dart';
import '../../../features/auth/presentation/bloc/session_bloc.dart';
import '../../../features/products/domain/repositories/retailer_product_repository.dart';
import '../../../features/products/presentation/retailer/cubit/retailer_products_cubit.dart';
import '../../../features/staff/domain/repositories/retailer_staff_repository.dart';
import '../../../features/staff/presentation/retailer/cubit/retailer_staff_cubit.dart';
import '../base/role_shell_scaffold.dart';
import 'bloc/retailer_manager_shell_bloc.dart';

/// The Retailer Manager application shell.
///
/// A separate shell from the Retailer Owner's, not a narrowed copy of it. The
/// two roles share a design system, a chrome widget and — from this milestone —
/// two feature cubits' *classes*. They share no navigation data, no BLoC
/// instance and no cubit instance: each shell constructs its own, so nothing one
/// role loaded can be visible inside the other's subtree.
///
/// ## Two destinations, and the missing ones are the backend's decision
///
/// There is no Overview cubit here and no Shops cubit, because there are no such
/// destinations for this role:
///
/// * `get_retailer_owner_portal_context()` resolves through
///   `resolve_retailer_owner_organization`, which hard-filters `RETAILER_OWNER`.
///   A Manager receives zero rows, so an Overview would be a permanent empty
///   screen.
/// * `list_retailer_owner_portal_shops()` uses the same Owner-only resolver.
///   Notably it does **not** raise — its `where` clause compares against a NULL
///   and simply matches nothing — so a Manager would see an empty estate
///   indistinguishable from a Retailer that genuinely has no shops. Showing that
///   would be worse than showing nothing: it asserts a fact about the business
///   that the response does not support.
///
/// Neither omission is this client enforcing a permission. Both are the app
/// declining to render a screen whose only possible content is nothing.
///
/// ## Staff is narrowed by SQL, not here
///
/// `list_retailer_staff_members()` ends with `and (v_can_manage or m.status =
/// 'ACTIVE')`. A Manager holds no `RETAILER_STAFF_MANAGE`, so the database
/// returns only ACTIVE members. This shell applies no equivalent filter and the
/// page renders exactly the rows it was given.
class RetailerManagerShell extends StatelessWidget {
  const RetailerManagerShell({
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
        BlocProvider<RetailerManagerShellBloc>(
          create: (_) => RetailerManagerShellBloc(),
        ),
        // Not loaded on creation: each page calls `loadOnce()` when it first
        // mounts, so entering the shell issues no RPC at all and opening Staff
        // does not fetch Products.
        BlocProvider<RetailerStaffCubit>(
          create: (BuildContext providerContext) => RetailerStaffCubit(
            providerContext.read<RetailerStaffRepository>(),
            // The invitation history is not read for this role.
            // `list_retailer_staff_invitations()` resolves through
            // `RETAILER_STAFF_MANAGE` and **raises 42501** for a Manager, so the
            // request's only possible outcome is a refusal — which would put a
            // denial notice on a screen where nothing is wrong.
            //
            // This is not the client enforcing the permission. The backend
            // decides and would keep deciding; if a Manager's role were granted
            // the permission tomorrow, flipping this flag is all that would be
            // needed, and nothing in the cubit, repository or page would change.
            includeInvitations: false,
          ),
        ),
        BlocProvider<RetailerProductsCubit>(
          create: (BuildContext providerContext) => RetailerProductsCubit(
            providerContext.read<RetailerProductRepository>(),
          ),
        ),
      ],
      child: _SessionIsolation(
        child: RoleShellScaffold<RetailerManagerShellBloc>(
          location: location,
          portalContext: portalContext,
          child: child,
        ),
      ),
    );
  }
}

/// The identity a Retailer Manager shell's private data belongs to.
///
/// Null whenever there is no active Retailer Manager session — signed out,
/// another role, resolving, denied or unavailable. Otherwise the pair that
/// decides whose data this is: the authenticated subject, and the trusted
/// Retailer organization the backend derived for them.
///
/// Both matter. The organization scopes what the RPCs return; the subject scopes
/// what is personal — a half-typed search term is a fragment of a colleague's
/// name, and it belongs to the person who typed it even when two Managers share
/// a Retailer.
///
/// **No organization id is ever sent anywhere.** It is compared locally to
/// detect a change; both RPCs that reload afterwards take no arguments at all.
typedef _RetailerManagerIdentity = ({
  String? authUserId,
  String organizationId,
});

/// Drops the Manager's staff and product data the moment the session stops being
/// this person's.
///
/// A [BlocListener] rather than a `BlocBuilder`, because the guarantee must not
/// depend on a frame being built.
///
/// ## Why the trigger is an identity and not a boolean
///
/// The obvious test — "did this stop being a Retailer Manager session?" — cannot
/// tell one Manager from another. Under it, a direct `Manager A → Manager B`
/// transition is `true → true`, the listener never runs, and A's colleagues,
/// their shop assignments and A's search terms stay in memory under B's session.
///
/// `SessionBloc` happens to emit intermediate states today, so a boolean would
/// flip twice and appear to work. That is an accident of another bloc's
/// internals rather than a guarantee, so this listener **assumes no intermediate
/// state at all** — comparing identities makes the direct transition detectable
/// on its own terms, and makes a re-emitted identical session (a same-user token
/// refresh) compare equal and cost nothing.
class _SessionIsolation extends StatelessWidget {
  const _SessionIsolation({required this.child});

  final Widget child;

  static _RetailerManagerIdentity? _identityOf(SessionState state) {
    if (state is! SessionActive ||
        state.portalContext.portalKind != PortalKind.retailerManager) {
      return null;
    }
    final RetailerContext? retailer = state.portalContext.retailer;
    if (retailer == null) {
      return null;
    }
    return (
      authUserId: state.authUserId,
      organizationId: retailer.organizationId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SessionBloc, SessionState>(
      listenWhen: (SessionState previous, SessionState current) =>
          _identityOf(previous) != _identityOf(current),
      listener: (BuildContext context, SessionState state) {
        final RetailerStaffCubit staff = context.read<RetailerStaffCubit>();
        final RetailerProductsCubit products = context
            .read<RetailerProductsCubit>();

        // Always cleared, in every direction. A new session must not see the
        // previous one's colleagues or assigned catalogue even for the instant
        // before its own response arrives — and each `clear()` advances a
        // request token, so an answer already in flight for the previous
        // identity is dropped on arrival. The local search terms go with them.
        //
        // Nothing is reloaded afterwards: both cubits return to `initial`, and
        // whichever tab the new session opens reads itself through `loadOnce`.
        staff.clear();
        products.clear();
      },
      child: child,
    );
  }
}
