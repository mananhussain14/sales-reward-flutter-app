import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../rewards/domain/entities/campaign_target_progress.dart';
import 'campaign_copy.dart';
import 'campaign_detail_cubit.dart';
import 'campaign_detail_view.dart';

/// One campaign, read-only, parameterised by which role's cubit it reads.
///
/// Same reasoning as `CampaignListPage`: the type parameter is what stops a
/// Sales Staff route resolving a Retailer Owner cubit, while the sequencing,
/// the phases and the layout stay one implementation.
///
/// ## The route parameter is an address, not a permission
///
/// Typing an unknown id — or `not-a-uuid` — into the route reaches this screen
/// and produces [CampaignDetailPhase.notFound], the **same** state for all of
/// them: SQL returns zero rows for an id that is not this Retailer's, and the
/// repository answers a malformed one locally without a request. The screen
/// never says whether the campaign exists and never says it belongs to somebody
/// else.
///
/// For a seller it covers one case more — a campaign that is no longer `ACTIVE`
/// or `SCHEDULED` — and that too is indistinguishable here, because
/// `get_my_staff_campaign()` returns zero rows for it.
///
/// ## Read-only
///
/// No edit, publish, pause, resume, version or cancel control, and none
/// disabled. The only interactive elements are Back and, on a failure, Retry.
class CampaignDetailPage<C extends CampaignDetailCubitBase>
    extends StatefulWidget {
  const CampaignDetailPage({
    super.key,
    required this.campaignId,
    required this.listPath,
    this.progress,
    this.onOpenEarnings,
  });

  /// The `:campaignId` segment, verbatim.
  ///
  /// Not validated here: the repository refuses a malformed id and answers
  /// exactly as the backend answers for an id that names no readable campaign,
  /// so a mistyped address and an unknown one are one case.
  final String campaignId;

  /// This role's campaign list route, for the deep-link case where there is
  /// nothing underneath to pop back to.
  final String listPath;

  /// This campaign's target progress, or null when it has none.
  ///
  /// Supplied by the Sales Staff binding, which reads a second contract on a
  /// second permission. A Retailer Owner has neither and passes nothing.
  final CampaignTargetProgress? progress;

  /// Opens the reader's own campaign earnings.
  ///
  /// Supplied by the Sales Staff binding and null for a Retailer Owner, who has
  /// no earnings contract to reach — `STAFF_EARNINGS_VIEW` is mapped to
  /// `SALES_STAFF` alone. Null omits the control rather than disabling it: an
  /// affordance that led nowhere would be worse than none.
  ///
  /// Passed in rather than resolved here, so this shared widget names no role's
  /// routes and cannot send one role into another's subtree.
  final VoidCallback? onOpenEarnings;

  @override
  State<CampaignDetailPage<C>> createState() => _CampaignDetailPageState<C>();
}

class _CampaignDetailPageState<C extends CampaignDetailCubitBase>
    extends State<CampaignDetailPage<C>> {
  @override
  void initState() {
    super.initState();
    context.read<C>().open(widget.campaignId);
  }

  @override
  void didUpdateWidget(CampaignDetailPage<C> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Navigating from one campaign straight to another reuses this element with
    // a new parameter. `open` is idempotent for the same id, so this is a no-op
    // unless the id genuinely changed.
    if (oldWidget.campaignId != widget.campaignId) {
      context.read<C>().open(widget.campaignId);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Reached by a deep link or a hard reload, where there is no list page
    // beneath this one to pop back to.
    context.go(widget.listPath);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<C, CampaignDetailState>(
      // Two triggers, both meaning "the campaign this route addresses is not
      // the one the cubit holds":
      //
      //  * **`initial`** — the shell's session isolation emptied the cubit when
      //    the signed-in person changed, so the same route is re-read under the
      //    new caller's own identity.
      //  * **a different id** — the cubit is provided at the shell and holds one
      //    campaign, so another detail route can have taken it over while this
      //    one was not current.
      //
      // Re-opening emits a loading state whose id *is* this route's, so neither
      // condition holds afterwards and the listener does not re-fire.
      listenWhen: (CampaignDetailState previous, CampaignDetailState current) =>
          current.phase == CampaignDetailPhase.initial ||
          current.campaignId != widget.campaignId,
      listener: (BuildContext context, CampaignDetailState state) =>
          context.read<C>().open(widget.campaignId),
      builder: (BuildContext context, CampaignDetailState state) {
        final C cubit = context.read<C>();

        // The cubit is provided at the shell and holds ONE campaign, so a route
        // whose id is not the one currently held must render nothing of it. In
        // the shipped flow the two always agree — the list pushes a single
        // detail and Back pops it — but "render whatever the cubit happens to
        // hold" is the wrong default for a screen that describes commercial
        // terms, and the loading view is the honest answer while the right
        // campaign is read.
        if (state.campaignId != widget.campaignId ||
            state.phase == CampaignDetailPhase.initial ||
            state.phase == CampaignDetailPhase.loading) {
          return const SrLoadingView(label: CampaignCopy.loadingDetail);
        }

        return SrPageBody(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: CampaignCopy.backToCampaigns,
                child: SrButton(
                  label: CampaignCopy.backToCampaigns,
                  variant: SrButtonVariant.ghost,
                  size: SrButtonSize.sm,
                  icon: Icons.arrow_back_rounded,
                  onPressed: _back,
                ),
              ),
            ),
            const SizedBox(height: SrSpacing.lg),
            ..._content(state, cubit),
          ],
        );
      },
    );
  }

  List<Widget> _content(CampaignDetailState state, C cubit) {
    switch (state.phase) {
      case CampaignDetailPhase.initial:
      case CampaignDetailPhase.loading:
        // Handled above; the loading view replaces the whole page.
        return const <Widget>[];

      case CampaignDetailPhase.notFound:
        return <Widget>[
          SrEmptyState(
            icon: Icons.campaign_outlined,
            title: CampaignCopy.notFoundTitle,
            description: CampaignCopy.notFoundBody,
            // No retry: the backend answered, and it will answer the same way.
            // Offering one here would invite a reader to probe an address, and
            // would look like an outage rather than a settled answer.
            action: SrButton(
              label: CampaignCopy.backToCampaigns,
              variant: SrButtonVariant.outline,
              icon: Icons.arrow_back_rounded,
              onPressed: _back,
            ),
          ),
        ];

      case CampaignDetailPhase.failed:
        return <Widget>[
          SrRetailerProblemView(
            problem: state.problem!,
            onRetry: cubit.refresh,
          ),
        ];

      case CampaignDetailPhase.ready:
        return <Widget>[
          CampaignDetailView(
            campaign: state.campaign!,
            products: state.products,
            progress: widget.progress,
            onOpenEarnings: widget.onOpenEarnings,
          ),
        ];
    }
  }
}
