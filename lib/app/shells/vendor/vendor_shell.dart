import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/audit/domain/repositories/vendor_audit_log_repository.dart';
import '../../../features/audit/presentation/vendor/cubit/vendor_audit_log_cubit.dart';
import '../../../features/auth/domain/entities/portal_context.dart';
import '../../../features/auth/domain/entities/portal_kind.dart';
import '../../../features/auth/presentation/bloc/session_bloc.dart';
import '../../../features/dashboard/domain/repositories/vendor_dashboard_repository.dart';
import '../../../features/dashboard/presentation/vendor/cubit/vendor_dashboard_cubit.dart';
import '../../../features/products/domain/repositories/vendor_product_repository.dart';
import '../../../features/products/presentation/vendor/cubit/vendor_product_assignment_cubit.dart';
import '../../../features/products/presentation/vendor/cubit/vendor_product_create_cubit.dart';
import '../../../features/products/presentation/vendor/cubit/vendor_product_detail_cubit.dart';
import '../../../features/products/presentation/vendor/cubit/vendor_product_edit_cubit.dart';
import '../../../features/products/presentation/vendor/cubit/vendor_product_list_cubit.dart';
import '../../../features/products/presentation/vendor/cubit/vendor_product_status_cubit.dart';
import '../../../features/products/presentation/vendor/cubit/vendor_product_write_notice.dart';
import '../../../features/profile/domain/repositories/vendor_profile_repository.dart';
import '../../../features/profile/presentation/vendor/cubit/vendor_profile_cubit.dart';
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
/// All six loading cubits load on creation, and `BlocProvider` builds each on
/// first read — so entering the Vendor shell does not fetch the user directory
/// until something asks for it, and opening Retailers never fetches Users,
/// Roles, Products, the audit feed or the dashboard summary.
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
/// moment the session stops being *this* person's, all fourteen cubits are cleared:
/// the Retailer summaries, the open Retailer, its shops, the user summaries with
/// their names and roles, the open user, the role catalogue with **this
/// Vendor's own assigned member counts**, the open role and its permissions, the
/// product catalogue with its codes, barcodes, brands and assignment counts, the
/// open product with the names and statuses of the Retailers holding it, the
/// loaded pages of the audit feed with the colleague, Retailer, shop and product
/// names riding on them, the dashboard summary with **this Vendor's own active
/// membership count and all-time recorded-event total**, the signed-in
/// administrator's **own name and own active role names**, every search term
/// and status filter — which are private too, being fragments of Retailer,
/// colleague and product names — and the three product **write** cubits: a
/// half-typed product code and description, a seeded edit form, a pending
/// activate-or-deactivate decision, and any write progress, refusal or success.
///
/// Clearing the audit cubit also drops its **cursor position**, which is why the
/// next Vendor cannot continue paging from where the previous one stopped.
///
/// The role *definitions* are global and are the same for whoever signs in next.
/// The counts riding on the same rows are not, which is why the Role pair is
/// cleared rather than kept as a harmless cache. Nothing about the Product pair
/// or the audit feed is global: a catalogue and a history each belong to exactly
/// one Vendor. The dashboard summary is a mixture — two Vendor counts and two
/// deployment-wide catalogue counts — and it is cleared **whole**, because the
/// four figures are one snapshot from one statement and a summary carrying only
/// its global half is a shape no backend answer ever produces.
///
/// The write cubits are cleared for a reason the read cubits do not have. Stale rows
/// are a disclosure problem; an in-flight *write* is worse. A create, edit or status
/// answer that landed after a `Vendor A → Vendor B` switch could otherwise report a
/// duplicate against A's catalogue into B's session, acknowledge a save B never made,
/// or navigate B to A's product. Each `clear()` advances a request token, so those
/// answers are dropped on arrival rather than emitted into the new session.
///
/// The administrator profile is the most personal of them all — it is a name and
/// an entitlement about one individual — and it is cleared for a direct
/// `Vendor A → Vendor B` switch as much as for a sign-out, because that is
/// precisely the transition in which one administrator's name could otherwise be
/// left on screen under another's session. The **company** half of that screen
/// needs no clearing at all: it is read from the session on every build, so it
/// changes with the session by construction rather than by being emptied.
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
        // The three product WRITE cubits, owned here for the same three reasons the
        // read cubits are — and for a fourth that is specific to a write.
        //
        // A cubit created inside the create or edit route would be a level *below*
        // the session listener, which is precisely the subtree that must be emptied
        // when the signed-in person changes. A half-typed product code, a seeded
        // edit form and a pending status decision are all private Vendor data, and
        // an in-flight write is worse than stale data: an answer that landed after a
        // Vendor A → Vendor B switch could otherwise report a duplicate against A's
        // catalogue into B's session, or navigate B to A's product. Clearing each of
        // them advances a request token, so those answers are dropped on arrival.
        //
        // Declared AFTER the list and detail cubits so their callbacks can read
        // them: `MultiBlocProvider` nests, so a later provider's `create` sees every
        // earlier one. Those callbacks are the whole read-after-write path — the
        // three RPCs return `uuid`, `void` and `void`, never a product row, so the
        // canonical values always come from `get_vendor_product_detail` and the
        // catalogue is always re-read rather than patched in place.
        BlocProvider<VendorProductCreateCubit>(
          create: (BuildContext providerContext) {
            final VendorProductListCubit list = providerContext
                .read<VendorProductListCubit>();
            final VendorProductDetailCubit detail = providerContext
                .read<VendorProductDetailCubit>();
            return VendorProductCreateCubit(
              providerContext.read<VendorProductRepository>(),
              onProductCreated: (String productId) {
                // The canonical read for the new product starts here, before the
                // router moves — so the product screen's own idempotent `open`
                // recognises it and issues no second call.
                detail.openCreated(productId);
                list.refresh();
              },
              // The create succeeded and its id could not be read. The catalogue is
              // the only authority on what exists, so it is re-read; nothing
              // re-attempts the create.
              onCatalogueStale: list.refresh,
            );
          },
        ),
        BlocProvider<VendorProductEditCubit>(
          create: (BuildContext providerContext) {
            final VendorProductListCubit list = providerContext
                .read<VendorProductListCubit>();
            final VendorProductDetailCubit detail = providerContext
                .read<VendorProductDetailCubit>();
            return VendorProductEditCubit(
              providerContext.read<VendorProductRepository>(),
              onProductWritten: (VendorProductWriteNotice notice) {
                detail.refreshDetail(notice: notice);
                list.refresh();
              },
            );
          },
        ),
        BlocProvider<VendorProductStatusCubit>(
          create: (BuildContext providerContext) {
            final VendorProductListCubit list = providerContext
                .read<VendorProductListCubit>();
            final VendorProductDetailCubit detail = providerContext
                .read<VendorProductDetailCubit>();
            return VendorProductStatusCubit(
              providerContext.read<VendorProductRepository>(),
              onProductWritten: (VendorProductWriteNotice notice) {
                // Re-reads the product row alone. Assignment rows are deliberately
                // NOT re-read: a status change touches none of them, not even their
                // `updated_at`, so a second call would learn nothing — and both
                // counts still come from the freshly-read product row rather than
                // from anything computed here.
                detail.refreshDetail(notice: notice);
                list.refresh();
              },
            );
          },
        ),
        // The Product ASSIGNMENT cubit — the fourth product write cubit, and the
        // one on a different entitlement. `assign_vendor_product_to_retailer` and
        // `unassign_vendor_product_from_retailer` are gated on
        // `PRODUCT_RETAILER_ASSIGN`, which the backend proved is distinct from
        // `PRODUCTS_MANAGE` in both directions, so it is neither folded into the
        // status cubit nor allowed to infer anything from it.
        //
        // It reads two repositories: the Product one for the writes, and the
        // Retailer one for `list_vendor_retailers()`, which is the only honest
        // source of "which Retailers may this product be assigned to" — the same
        // `vendor_retailers` set the write reaches a Retailer through, carrying
        // the two statuses the assign gate consults. No third contract is added,
        // and no table is read.
        BlocProvider<VendorProductAssignmentCubit>(
          create: (BuildContext providerContext) {
            final VendorProductListCubit list = providerContext
                .read<VendorProductListCubit>();
            final VendorProductDetailCubit detail = providerContext
                .read<VendorProductDetailCubit>();
            return VendorProductAssignmentCubit(
              providerContext.read<VendorProductRepository>(),
              providerContext.read<VendorRetailerRepository>(),
              onAssignmentWritten: (VendorProductWriteNotice notice) {
                // Both canonical reads, because an assignment transition moves
                // values in both: the history gains or changes a row, and
                // `assignment_count` / `active_assignment_count` are recomputed
                // by the detail statement. Nothing is inserted, removed or
                // re-statused locally on the way — both RPCs return `void`.
                detail.refreshAfterAssignment(notice: notice);
                // And the catalogue, whose `active_assignment_count` moved too.
                list.refresh();
              },
            );
          },
        ),
        // The audit feed is private Vendor data in its entirety — it names
        // colleagues, Retailers, shops and products, and the moment each was
        // touched — so it is owned and cleared here exactly like the other four.
        // A single cubit rather than a pair: there is no detail read to hold.
        BlocProvider<VendorAuditLogCubit>(
          create: (BuildContext providerContext) => VendorAuditLogCubit(
            providerContext.read<VendorAuditLogRepository>(),
          )..load(),
        ),
        // The dashboard summary. Two of its four counts are private Vendor data
        // — how many people work in the organization, and how much has ever
        // happened in it — so it is owned and cleared here exactly like the other
        // five. The two catalogue counts are global, but the snapshot is cleared
        // whole: a half-cleared summary would be a shape no backend answer ever
        // produces.
        BlocProvider<VendorDashboardCubit>(
          create: (BuildContext providerContext) => VendorDashboardCubit(
            providerContext.read<VendorDashboardRepository>(),
          )..load(),
        ),
        // The signed-in administrator's own profile. Personal data in its
        // entirety — the person's name, and what they are entitled to do in this
        // organization — so it is owned and cleared here exactly like the other
        // ten. It holds only the administrator half of that screen: the company
        // name stays in the session, which is why nothing here caches it.
        BlocProvider<VendorProfileCubit>(
          create: (BuildContext providerContext) => VendorProfileCubit(
            providerContext.read<VendorProfileRepository>(),
          )..load(),
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
        final VendorProductCreateCubit productCreate = context
            .read<VendorProductCreateCubit>();
        final VendorProductEditCubit productEdit = context
            .read<VendorProductEditCubit>();
        final VendorProductStatusCubit productStatus = context
            .read<VendorProductStatusCubit>();
        final VendorProductAssignmentCubit productAssignment = context
            .read<VendorProductAssignmentCubit>();
        final VendorAuditLogCubit auditLogs = context
            .read<VendorAuditLogCubit>();
        final VendorDashboardCubit dashboard = context
            .read<VendorDashboardCubit>();
        final VendorProfileCubit profile = context.read<VendorProfileCubit>();

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
        // The three write cubits go with them, and this is the half a boolean test
        // could not have covered: a form, its validation, its progress, its errors,
        // its success and any pending status decision all belong to one person in one
        // Vendor. Each `clear()` also advances a request token, so a create, an edit
        // or a status change already in flight for the previous identity is dropped on
        // arrival — it cannot repopulate a form, report a duplicate against the
        // previous Vendor's catalogue, or navigate this session to their product.
        productCreate.clear();
        productEdit.clear();
        productStatus.clear();
        // The assignment surface goes with them, and it carries more than a
        // pending decision: the names and trading statuses of every Retailer the
        // previous Vendor works with, a search term that is a fragment of one of
        // those names, and any in-flight assign or withdrawal. `clear()` advances
        // its request token too, so an answer that lands after the switch is
        // dropped rather than leaving an "Assignment withdrawn" notice over
        // somebody else's product — or, worse, a stale candidate list inviting a
        // write against a Retailer this session does not manage.
        productAssignment.clear();
        auditLogs.clear();
        dashboard.clear();
        profile.clear();

        if (_identityOf(state) != null) {
          // Read again from the backend under the new caller's own identity —
          // which is derived server-side from `auth.uid()`, not from anything
          // passed from here. An open Retailer or user, if any, is re-read by
          // its detail page, which notices its cubit returning to `initial`.
          retailers.load();
          users.load();
          roles.load();
          products.load();
          auditLogs.load();
          dashboard.load();
          profile.load();
        }
      },
      child: child,
    );
  }
}
