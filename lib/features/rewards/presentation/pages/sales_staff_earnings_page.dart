import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/domain/entities/portal_kind.dart';
import '../bloc/campaign_earnings_cubit.dart';
import '../widgets/earnings_body.dart';
import '../widgets/earnings_copy.dart';

/// A Sales Staff member's own campaign earnings.
///
/// ## What a seller sees, and what they do not
///
/// * **Only their own rewards.** `get_my_campaign_rewards()` filters on
///   `beneficiary_profile_id = sales_staff_earnings_profile()` and takes no
///   argument that names a person, so there is no request this screen could make
///   for somebody else's earnings.
/// * **No wallet, balance, payout or redemption.** None exists in the deployed
///   schema. The screen says so once, above the totals, rather than leaving the
///   absence to be discovered.
/// * **No verified sale id.** The contract does not return one — Migration 69
///   exists to keep that key out of a client — and the receipt reference stands
///   in its place.
/// * **No action of any kind.** No claim, redeem, withdraw, transfer or dispute,
///   and none disabled.
///
/// ## The first read belongs to the tab, not the shell
///
/// The shell creates the cubit and deliberately does not load it. `loadOnce`
/// runs from `initState`, so entering the shell issues no earnings request and
/// opening this tab issues exactly one pair. Returning to an already-loaded tab
/// reads nothing; Refresh or pull-to-refresh is the way to re-read.
class SalesStaffEarningsPage extends StatefulWidget {
  const SalesStaffEarningsPage({super.key});

  @override
  State<SalesStaffEarningsPage> createState() => _SalesStaffEarningsPageState();
}

class _SalesStaffEarningsPageState extends State<SalesStaffEarningsPage> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame so the read cannot emit into a widget
    // tree that is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SalesStaffEarningsCubit>().loadOnce();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SalesStaffEarningsCubit, SalesStaffEarningsState>(
      builder: (BuildContext context, SalesStaffEarningsState state) {
        final SalesStaffEarningsCubit cubit = context
            .read<SalesStaffEarningsCubit>();

        if (state.isInitialLoading) {
          return const SrLoadingView(label: EarningsCopy.loading);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            // Always scrollable, so pull-to-refresh works on an empty history
            // and on a short one rather than only when the content overflows.
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SrPageHeader(
                eyebrow: PortalKind.salesStaff.displayName,
                title: EarningsCopy.title,
                description: EarningsCopy.description,
                actions: <Widget>[
                  Semantics(
                    button: true,
                    label: EarningsCopy.refresh,
                    child: SrButton(
                      label: EarningsCopy.refresh,
                      variant: SrButtonVariant.outline,
                      icon: Icons.refresh_rounded,
                      loading: state.isRefreshing,
                      loadingLabel: EarningsCopy.refreshing,
                      onPressed: state.isRefreshing ? null : cubit.refresh,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SrSpacing.xxl),
              EarningsBody(
                state: state,
                onRetry: cubit.load,
                onLoadOlder: cubit.loadOlder,
              ),
            ],
          ),
        );
      },
    );
  }
}
