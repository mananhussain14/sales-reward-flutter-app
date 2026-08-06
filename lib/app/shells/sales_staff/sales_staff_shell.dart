import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/auth/domain/entities/portal_context.dart';
import '../../../features/auth/domain/entities/portal_kind.dart';
import '../../../features/auth/presentation/bloc/session_bloc.dart';
import '../../../features/campaigns/domain/repositories/staff_campaign_repository.dart';
import '../../../features/campaigns/presentation/shared/campaign_detail_cubit.dart';
import '../../../features/campaigns/presentation/shared/campaign_list_cubit.dart';
import '../../../features/receipts/domain/repositories/receipt_repository.dart';
import '../../../features/receipts/domain/services/receipt_image_source.dart';
import '../../../features/receipts/presentation/sales_staff/cubit/receipt_history_cubit.dart';
import '../../../features/receipts/presentation/sales_staff/cubit/receipt_submission_cubit.dart';
import '../../../features/rewards/domain/repositories/staff_earnings_repository.dart';
import '../../../features/rewards/presentation/bloc/campaign_earnings_cubit.dart';
import '../../../features/rewards/presentation/bloc/campaign_target_progress_cubit.dart';
import '../base/role_shell_scaffold.dart';
import 'bloc/sales_staff_shell_bloc.dart';

/// The Sales Staff application shell.
///
/// The narrowest shell in the product: four destinations, bottom navigation, and
/// nothing borrowed from any other role.
///
/// ## Why the receipt cubits are provided here rather than per page
///
/// Both tabs read the same submission history, and the submit screen refreshes
/// it after every settled attempt. Providing the history cubit once, above both,
/// means there is one list rather than two that can disagree — so the submit
/// screen's "recent submissions" section and the History tab are guaranteed to
/// show the same rows.
///
/// ## Session isolation is enforced, not inferred from the widget lifetime
///
/// The obvious argument is that the router sends every `/sales-staff` route away
/// when the session changes, so the subtree unmounts and takes both cubits with
/// it. That argument is **not sound**, and a test proves it: a user switch
/// emits `SessionInitial` and then `SessionActive` for the new person within a
/// single microtask drain, so no frame ever renders the intermediate state, the
/// route match list never actually leaves `/sales-staff/submit`, and the element
/// — along with the previous person's chosen receipt image — survives.
///
/// [_SessionIsolation] closes that gap by listening to [SessionBloc] directly.
/// A listener runs on every emitted state whether or not a frame was built, so
/// the moment the session stops being *this* person's, both cubits are cleared:
/// the shops, the products, the history and the bytes of any chosen receipt.
/// When a new Sales Staff session settles, both reload from scratch.
class SalesStaffShell extends StatelessWidget {
  const SalesStaffShell({
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
    return BlocProvider<ReceiptHistoryCubit>(
      create: (BuildContext providerContext) =>
          ReceiptHistoryCubit(providerContext.read<ReceiptRepository>())
            ..load(),
      // Nested rather than a sibling inside one MultiBlocProvider: the
      // submission cubit refreshes the history after every settled attempt, so
      // it has to be able to read it while it is being constructed.
      child: Builder(
        builder: (BuildContext historyContext) {
          return BlocProvider<ReceiptSubmissionCubit>(
            create: (BuildContext providerContext) => ReceiptSubmissionCubit(
              repository: providerContext.read<ReceiptRepository>(),
              imageSource: providerContext.read<ReceiptImageSource>(),
              onSubmissionSettled: historyContext
                  .read<ReceiptHistoryCubit>()
                  .refresh,
            )..load(),
            child: MultiBlocProvider(
              providers: <BlocProvider<dynamic>>[
                BlocProvider<SalesStaffShellBloc>(
                  create: (_) => SalesStaffShellBloc(),
                ),
                // The campaign cubits, deliberately NOT loaded on creation —
                // unlike the two receipt cubits above. The screen that needs
                // them reads them: the Home screen is now the landing route and
                // starts all three from its own `initState`, and the Campaigns
                // tab does the same if it is opened first through a deep link.
                // `loadOnce` makes the second of those a no-op, so a seller who
                // lands on Home and then opens Campaigns issues one read, not
                // two.
                //
                // Provided here rather than on the routes so both sit ABOVE the
                // session listener below, which is the subtree that has to be
                // emptied when the signed-in person changes.
                BlocProvider<SalesStaffCampaignListCubit>(
                  create: (BuildContext providerContext) =>
                      SalesStaffCampaignListCubit(
                        providerContext.read<StaffCampaignRepository>(),
                      ),
                ),
                BlocProvider<SalesStaffCampaignDetailCubit>(
                  create: (BuildContext providerContext) =>
                      SalesStaffCampaignDetailCubit(
                        providerContext.read<StaffCampaignRepository>(),
                      ),
                ),
                // The two earnings cubits, on a SEPARATE repository behind a
                // SEPARATE permission — STAFF_EARNINGS_VIEW rather than
                // STAFF_CAMPAIGNS_VIEW. Neither can reach the campaign
                // contract and neither campaign cubit can reach this one,
                // because the field types do not permit it.
                //
                // Deliberately NOT loaded on creation, like the campaign
                // cubits above: the Campaigns and Earnings tabs read
                // themselves when a user actually opens them.
                //
                // The progress cubit is provided at the SHELL rather than on
                // the Campaigns route, because both the campaign list and one
                // campaign's detail read from it — one round trip serves both,
                // and opening a detail issues no second request.
                BlocProvider<SalesStaffCampaignProgressCubit>(
                  create: (BuildContext providerContext) =>
                      SalesStaffCampaignProgressCubit(
                        providerContext.read<StaffEarningsRepository>(),
                      ),
                ),
                BlocProvider<SalesStaffEarningsCubit>(
                  create: (BuildContext providerContext) =>
                      SalesStaffEarningsCubit(
                        providerContext.read<StaffEarningsRepository>(),
                      ),
                ),
              ],
              child: _SessionIsolation(
                child: RoleShellScaffold<SalesStaffShellBloc>(
                  location: location,
                  portalContext: portalContext,
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Drops every piece of private receipt data the moment the session stops being
/// this person's, and reloads when a new Sales Staff session settles.
///
/// A [BlocListener] rather than a `BlocBuilder`, because the guarantee must not
/// depend on a frame being built: a user switch can emit `SessionInitial` and
/// the next person's `SessionActive` inside one microtask drain, and nothing
/// would ever paint in between.
class _SessionIsolation extends StatelessWidget {
  const _SessionIsolation({required this.child});

  final Widget child;

  static bool _isSalesStaff(SessionState state) =>
      state is SessionActive &&
      state.portalContext.portalKind == PortalKind.salesStaff;

  @override
  Widget build(BuildContext context) {
    return BlocListener<SessionBloc, SessionState>(
      listenWhen: (SessionState previous, SessionState current) =>
          _isSalesStaff(previous) != _isSalesStaff(current),
      listener: (BuildContext context, SessionState state) {
        final ReceiptSubmissionCubit submission = context
            .read<ReceiptSubmissionCubit>();
        final ReceiptHistoryCubit history = context.read<ReceiptHistoryCubit>();
        final SalesStaffCampaignListCubit campaigns = context
            .read<SalesStaffCampaignListCubit>();
        final SalesStaffCampaignDetailCubit campaignDetail = context
            .read<SalesStaffCampaignDetailCubit>();
        final SalesStaffCampaignProgressCubit campaignProgress = context
            .read<SalesStaffCampaignProgressCubit>();
        final SalesStaffEarningsCubit earnings = context
            .read<SalesStaffEarningsCubit>();

        if (_isSalesStaff(state)) {
          // A new Sales Staff session. Everything is read again from the
          // backend under the new caller's own identity.
          submission.load();
          history.load();
          // The campaign, progress and earnings cubits are reloaded with them,
          // and that is a change from the previous milestone — which left them
          // at `initial` on the grounds that "eagerly refetching a screen
          // nobody is looking at would issue a request for nothing".
          //
          // Somebody IS looking at them now. The Home screen is the landing
          // route and renders all three, and its `initState` has already run
          // for the previous person: the element survives a user switch inside
          // one microtask drain, so nothing would re-read them and the new
          // seller would land on a screen of empty sections until they pulled
          // to refresh. The detail cubit is left cleared — no campaign is open
          // at the moment a session changes.
          campaigns.load();
          campaignProgress.load();
          earnings.load();
          return;
        }

        submission.clear();
        history.clear();
        // The campaigns go with them. What a Vendor offers a Retailer, on what
        // terms and against which products, is private to that commercial
        // relationship and must not survive into another person's session.
        // `clear()` advances a request token too, so a read already in flight
        // for the previous identity is dropped on arrival.
        campaigns.clear();
        campaignDetail.clear();
        // And the earnings go with them — the most private thing this
        // application holds. What somebody has been paid, how far their team
        // has got towards a target and which receipts produced a reward must
        // not survive into another person's session for even one frame.
        // `clear()` advances a request token in both, so a read already in
        // flight for the previous identity is dropped on arrival.
        campaignProgress.clear();
        earnings.clear();
      },
      child: child,
    );
  }
}
