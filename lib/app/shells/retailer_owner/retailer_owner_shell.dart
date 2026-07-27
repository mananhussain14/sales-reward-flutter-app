import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/auth/domain/entities/portal_context.dart';
import '../../../features/auth/domain/entities/portal_kind.dart';
import '../../../features/auth/presentation/bloc/session_bloc.dart';
import '../../../features/dashboard/domain/repositories/retailer_owner_overview_repository.dart';
import '../../../features/dashboard/presentation/retailer_owner/cubit/retailer_owner_overview_cubit.dart';
import '../base/role_shell_scaffold.dart';
import 'bloc/retailer_owner_shell_bloc.dart';

/// The Retailer Owner application shell.
///
/// Four destinations, so it uses bottom navigation — promoted to a rail on a
/// tablet or on Flutter web. Owns its own [RetailerOwnerShellBloc] and its own
/// navigation model, and shares nothing with the Vendor shell but the chrome in
/// [RoleShellScaffold]: no destinations, no BLoC instance, no cubit, and no
/// conditional branches. A Vendor selection, notice or cached row has no path
/// into this subtree, because no Vendor cubit is provided anywhere within it.
///
/// ## Why the overview cubit is provided here rather than on the route
///
/// Two reasons, and each is a bug avoided rather than a preference.
///
/// * **The overview survives a round trip through another destination.** Moving
///   to Shops and back renders the values already held instead of re-reading
///   them, which is the difference between a tab switch and a reload.
/// * **It is reachable by the session listener below.** A cubit created inside
///   the Overview route would be a level *below* that listener, which is
///   precisely the subtree that must be emptied when the signed-in person
///   changes.
///
/// It loads on creation, and `BlocProvider` builds it on first read.
///
/// ## Session isolation is enforced, not inferred from the widget lifetime
///
/// The obvious argument is that the router sends every `/retailer-owner` route
/// away when the session changes, so the subtree unmounts and takes the cubit
/// with it. That argument is **not sound**: a user switch emits `SessionInitial`
/// and then `SessionActive` for the new person within a single microtask drain,
/// so no frame ever renders the intermediate state and the route match list never
/// actually leaves `/retailer-owner/…`. Worse here than elsewhere: switching from
/// one Retailer Owner to another keeps the location *inside the same role group*,
/// so the guard has no reason to redirect at all and the element is certain to
/// survive.
///
/// [_SessionIsolation] closes that gap by listening to [SessionBloc] directly. A
/// listener runs on every emitted state whether or not a frame was built, so the
/// moment the session stops being *this* person's, the overview is cleared: the
/// Retailer's name, its trading status, this person's membership status, and how
/// many shops the organization runs — every one of which is private to one
/// organization.
class RetailerOwnerShell extends StatelessWidget {
  const RetailerOwnerShell({
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
        BlocProvider<RetailerOwnerShellBloc>(
          create: (_) => RetailerOwnerShellBloc(),
        ),
        BlocProvider<RetailerOwnerOverviewCubit>(
          create: (BuildContext providerContext) => RetailerOwnerOverviewCubit(
            providerContext.read<RetailerOwnerOverviewRepository>(),
          )..load(),
        ),
      ],
      child: _SessionIsolation(
        child: RoleShellScaffold<RetailerOwnerShellBloc>(
          location: location,
          portalContext: portalContext,
          child: child,
        ),
      ),
    );
  }
}

/// The identity a Retailer Owner shell's private data belongs to.
///
/// Null whenever there is no active Retailer Owner session at all — signed out,
/// another role, resolving, denied or unavailable. Otherwise the pair that
/// together decides whose data this is:
///
/// * the **authenticated subject** the context was resolved for, and
/// * the **trusted Retailer organization** the backend derived for them.
///
/// Both matter. The organization scopes what the RPC returns, so a change of
/// organization changes the row. The subject scopes what is *personal* — the
/// membership status on this screen is one individual's standing in the
/// organization, and it belongs to the person it describes even when two owners
/// share a Retailer.
///
/// Nothing here is inferred from an email, a display name, a role label or a
/// navigation path. The subject comes from [SessionActive.authUserId], which
/// `SessionBloc` sets from the value it already validated the resolution
/// against; the organization comes from the resolved context. **No organization
/// id is ever sent anywhere** — it is compared locally to detect a change, and
/// the RPC that reloads afterwards takes no arguments at all.
typedef _RetailerOwnerIdentity = ({String? authUserId, String organizationId});

/// Drops the overview the moment the session stops being this person's, and
/// reloads under whoever replaced them.
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
/// The obvious test — "did this stop being a Retailer Owner session?" — cannot
/// tell one Owner from another. Under it, a **direct** `Owner A → Owner B`
/// transition is `true → true`, the listener never runs, and A's organization
/// name, statuses and shop counts stay on screen under B's session.
///
/// Today `SessionBloc` happens to emit `SessionInitial` and `SessionResolving`
/// between the two, so a boolean would flip twice and appear to work. That is an
/// accident of another bloc's internals, not a guarantee: it is undocumented,
/// nothing enforces it, and a perfectly reasonable optimisation there would
/// silently reintroduce the leak here. **This listener therefore assumes no
/// intermediate state at all** — comparing identities makes the direct
/// transition detectable on its own terms.
///
/// It also makes the *absence* of a change detectable, which the boolean could
/// not: a re-emitted identical session — the shape a same-user token refresh
/// takes if it ever reaches this far — compares equal and is ignored, so it costs
/// no clear and no duplicate load.
class _SessionIsolation extends StatelessWidget {
  const _SessionIsolation({required this.child});

  final Widget child;

  /// The identity [state] carries, or null if it is not an active Retailer Owner
  /// session.
  ///
  /// A Retailer Owner session with no retailer block is treated as no identity:
  /// the context is not one this shell can hold data for, and returning
  /// something comparable would be inventing a tenant.
  static _RetailerOwnerIdentity? _identityOf(SessionState state) {
    if (state is! SessionActive ||
        state.portalContext.portalKind != PortalKind.retailerOwner) {
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
      // Any change of identity, in either direction and with or without an
      // intermediate state: entering a Retailer Owner session, leaving one, and
      // swapping one for another. Records compare by value, so this is a
      // structural comparison of the pair rather than of the state object.
      listenWhen: (SessionState previous, SessionState current) =>
          _identityOf(previous) != _identityOf(current),
      listener: (BuildContext context, SessionState state) {
        final RetailerOwnerOverviewCubit overview = context
            .read<RetailerOwnerOverviewCubit>();

        // Always cleared first, in every direction, and before anything is
        // requested for the new identity. A new Retailer Owner session must not
        // see the previous one's organization even for the instant before its
        // own response arrives — and `clear()` advances a request token, so a
        // response already in flight for the previous identity is dropped on
        // arrival rather than repopulating state that has just been emptied.
        //
        // Clearing also drops the selected navigation implicitly: the shell BLoC
        // is rebuilt from the router's location, which the guard has already
        // moved for any transition that leaves this role.
        overview.clear();

        if (_identityOf(state) != null) {
          // Read again from the backend under the new caller's own identity —
          // which is derived server-side from `auth.uid()`, not from anything
          // passed from here. The RPC takes no arguments, so the reload cannot
          // carry the previous organization forward even by accident.
          overview.load();
        }
      },
      child: child,
    );
  }
}
