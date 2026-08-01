import 'package:flutter/material.dart';

import '../../../../../app/shells/sales_staff/sales_staff_navigation.dart';
import '../../shared/campaign_detail_cubit.dart';
import '../../shared/campaign_detail_page.dart';

/// One campaign, for a Sales Staff member.
///
/// A binding over [CampaignDetailPage], fixing the cubit type to
/// [SalesStaffCampaignDetailCubit] — so this route can only resolve a cubit
/// reading `get_my_staff_campaign()` — and the fallback route to this role's own
/// campaign list.
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
    return CampaignDetailPage<SalesStaffCampaignDetailCubit>(
      campaignId: campaignId,
      listPath: SalesStaffNavigation.campaigns,
    );
  }
}
