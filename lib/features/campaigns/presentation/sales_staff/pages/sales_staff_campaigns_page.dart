import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/shells/sales_staff/sales_staff_navigation.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../../rewards/presentation/bloc/campaign_target_progress_cubit.dart';
import '../../shared/campaign_list_cubit.dart';
import '../../shared/campaign_list_page.dart';

/// The Sales Staff campaign list.
///
/// A binding over [CampaignListPage], fixing the cubit type to
/// [SalesStaffCampaignListCubit] — so this screen can only resolve a cubit
/// reading `list_my_staff_campaigns()` — and the routes to this role's own
/// prefix.
///
/// ## Two contracts, on two permissions, joined on the campaign id
///
/// The campaigns come from `list_my_staff_campaigns()` under
/// `STAFF_CAMPAIGNS_VIEW`; the target progress comes from
/// `get_my_campaign_target_progress()` under `STAFF_EARNINGS_VIEW`. Both apply
/// the same frozen Retailer targeting, the same published-version join and the
/// same `ACTIVE`/`SCHEDULED` filter, *"so a client can join these rows to that
/// list one-to-one on campaign_id"* — which is exactly what happens here, on the
/// **id** and never on the name.
///
/// They are read by two cubits rather than one, which is what makes the
/// partial-failure rule structural: a progress read that fails cannot blank the
/// campaign list, because it does not own it.
///
/// ## What a seller sees, and what they do not
///
/// * **Only `ACTIVE` and `SCHEDULED` campaigns.** Filtered in SQL, on the
///   derived state. Nothing on the device applies or restates that rule, so a
///   campaign that is paused while the list is open simply disappears on the
///   next read.
/// * **A progress bar only where there is a target.** A `PER_UNIT_COINS`
///   campaign has no row in the progress contract and gets none — showing one a
///   bar would be inventing a goal the Vendor never set.
/// * **No Vendor name.** `list_my_staff_campaigns()` does not return one, so no
///   card here has a Vendor line. That is a recorded deviation from the
///   milestone brief and the backend's deliberate choice, not an omission here.
/// * **No coin total.** Under a Retailer team target the accumulator's coins are
///   the whole team's; a seller's own earnings live on their earnings screen and
///   nowhere else.
/// * **No actions of any kind.** Not the Owner's, and certainly not the
///   Vendor's.
class SalesStaffCampaignsPage extends StatefulWidget {
  const SalesStaffCampaignsPage({super.key});

  @override
  State<SalesStaffCampaignsPage> createState() =>
      _SalesStaffCampaignsPageState();
}

class _SalesStaffCampaignsPageState extends State<SalesStaffCampaignsPage> {
  @override
  void initState() {
    super.initState();
    // The progress read belongs to this tab, exactly as the campaign read does:
    // entering the shell issues neither, and opening this tab issues one of
    // each. `CampaignListPage` starts the campaign read from its own
    // `initState` for the same reason.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SalesStaffCampaignProgressCubit>().loadOnce();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      SalesStaffCampaignProgressCubit,
      CampaignTargetProgressState
    >(
      builder: (BuildContext context, CampaignTargetProgressState progress) {
        return CampaignListPage<SalesStaffCampaignListCubit>(
          role: PortalKind.salesStaff,
          detailPath: SalesStaffNavigation.campaignDetail,
          progressFor: progress.forCampaign,
          progressUnavailable: progress.hasFailedOutright,
          alsoRefresh: context.read<SalesStaffCampaignProgressCubit>().refresh,
        );
      },
    );
  }
}
