import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/shells/sales_staff/sales_staff_navigation.dart';
import '../../../../rewards/presentation/bloc/campaign_target_progress_cubit.dart';
import '../../shared/campaign_detail_cubit.dart';
import '../../shared/campaign_detail_page.dart';

/// One campaign, for a Sales Staff member.
///
/// A binding over [CampaignDetailPage], fixing the cubit type to
/// [SalesStaffCampaignDetailCubit] — so this route can only resolve a cubit
/// reading `get_my_staff_campaign()` — and the fallback route to this role's own
/// campaign list.
///
/// ## The progress row is selected by id, from the read the list already made
///
/// `get_my_campaign_target_progress()` takes no arguments and returns every
/// visible target campaign in one round trip, so opening a detail issues **no**
/// additional progress request: the row for this campaign is picked out of the
/// map the shell's progress cubit already holds. A campaign with no row — a
/// per-unit campaign, or a session where the progress read has not run — shows
/// no indicator, which renders identically either way because in neither case is
/// there a target to draw.
///
/// The selection is on the **campaign id** this route carries, never on the
/// name: two campaigns may share a name and only the id is unique.
///
/// ## The not-found screen covers one case more here than for an Owner
///
/// `get_my_staff_campaign()` re-applies the `ACTIVE`/`SCHEDULED` filter, so a
/// seller who addresses a paused, ended or cancelled campaign directly reaches
/// the same screen as one who addresses an unknown id or another Retailer's. The
/// copy says nothing about why, which is what keeps a seller from learning that
/// a campaign exists but has been paused.
class SalesStaffCampaignDetailPage extends StatelessWidget {
  const SalesStaffCampaignDetailPage({super.key, required this.campaignId});

  /// The `:campaignId` route segment, verbatim.
  final String campaignId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      SalesStaffCampaignProgressCubit,
      CampaignTargetProgressState
    >(
      builder: (BuildContext context, CampaignTargetProgressState progress) {
        return CampaignDetailPage<SalesStaffCampaignDetailCubit>(
          campaignId: campaignId,
          listPath: SalesStaffNavigation.campaigns,
          progress: progress.forCampaign(campaignId),
        );
      },
    );
  }
}
