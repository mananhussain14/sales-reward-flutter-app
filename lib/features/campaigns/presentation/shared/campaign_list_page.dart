import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/domain/entities/portal_kind.dart';
import 'campaign_copy.dart';
import 'campaign_list_body.dart';
import 'campaign_list_cubit.dart';

/// The campaign list screen, parameterised by which role's cubit it reads.
///
/// ## Why the role is a type parameter rather than a field
///
/// `BlocBuilder<C, CampaignListState>` resolves `C` from the widget tree, so
/// `CampaignListPage<SalesStaffCampaignListCubit>` can only ever find a Sales
/// Staff cubit — and in a shell that provides only the other one, it fails to
/// resolve at build rather than quietly reading the wrong contract. A `role`
/// field could not offer that: it would be a value to branch on, and a wrong
/// value would compile.
///
/// The two roles' screens are therefore one implementation with no shared
/// mutable state and no role branch, while remaining two distinct types that
/// cannot be substituted for one another.
///
/// ## The first read belongs to the tab, not the shell
///
/// The shell creates the cubit but deliberately does not load it. `loadOnce`
/// runs from `initState`, so entering a shell issues no campaign request and
/// opening the Campaigns tab issues exactly one. Returning to an already-loaded
/// tab reads nothing — `loadOnce` is a no-op once the phase has left `initial` —
/// and Refresh or pull-to-refresh is the way to re-read.
class CampaignListPage<C extends CampaignListCubitBase> extends StatefulWidget {
  const CampaignListPage({
    super.key,
    required this.role,
    required this.detailPath,
  });

  /// Which shell this page is rendered in. Presentation only — it supplies the
  /// header eyebrow and nothing else.
  final PortalKind role;

  /// Builds the route for one campaign's detail, inside this role's own prefix.
  ///
  /// Supplied by the caller rather than derived here, so this shared widget
  /// names no role's routes and cannot send one role into another's subtree.
  final String Function(String campaignId) detailPath;

  @override
  State<CampaignListPage<C>> createState() => _CampaignListPageState<C>();
}

class _CampaignListPageState<C extends CampaignListCubitBase>
    extends State<CampaignListPage<C>> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame so the read cannot emit into a widget
    // tree that is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<C>().loadOnce();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<C, CampaignListState>(
      builder: (BuildContext context, CampaignListState state) {
        final C cubit = context.read<C>();

        if (state.isInitialLoading) {
          return const SrLoadingView(label: CampaignCopy.loading);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            // Always scrollable, so pull-to-refresh works on an empty list and
            // on a short one rather than only when the content overflows.
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: widget.role.displayName,
                title: CampaignCopy.title,
                description: CampaignCopy.description(state.audience),
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: CampaignCopy.refresh,
                    child: SrButton(
                      label: CampaignCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: CampaignCopy.refreshing,
                      onPressed: state.isRefreshing ? null : cubit.refresh,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SrSpacing.xxl),
              CampaignListBody(
                state: state,
                onRetry: cubit.load,
                onOpen: (String campaignId) =>
                    _open(context, cubit, campaignId),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Opens a campaign, and re-reads the list on the way back.
  ///
  /// The canonical refresh. A campaign can be paused, cancelled or superseded
  /// while its detail is open, and the list behind it would otherwise still be
  /// describing the state it had on the way in. `push` completes when the
  /// detail route pops, which is the moment to **ask the backend again** rather
  /// than to patch a card locally from anything the detail screen saw.
  ///
  /// `push` rather than the `go` used elsewhere in this application precisely
  /// because it returns that completion. The detail screen's Back still handles
  /// the deep-link case, where there is no list underneath to pop to.
  Future<void> _open(BuildContext context, C cubit, String campaignId) async {
    await context.push<void>(widget.detailPath(campaignId));
    // The screen can be disposed while the detail is open — a session change
    // redirects the whole shell away — so both guards are load-bearing.
    if (!mounted || cubit.isClosed) {
      return;
    }
    await cubit.refresh();
  }
}
