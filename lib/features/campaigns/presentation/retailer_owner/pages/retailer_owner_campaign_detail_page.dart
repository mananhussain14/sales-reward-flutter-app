import 'package:flutter/material.dart';

import '../../../../../app/shells/retailer_owner/retailer_owner_navigation.dart';
import '../../shared/campaign_detail_cubit.dart';
import '../../shared/campaign_detail_page.dart';

/// One campaign, for a Retailer Owner.
///
/// A binding over [CampaignDetailPage], fixing the cubit type to
/// [RetailerCampaignDetailCubit] — so this route can only resolve a cubit
/// reading `get_my_retailer_campaign()` — and the fallback route to this role's
/// own campaign list.
///
/// [campaignId] is passed through verbatim and is **not** validated here: the
/// repository refuses a malformed id, and a well-formed id belonging to another
/// Retailer reaches the identical not-found screen.
class RetailerOwnerCampaignDetailPage extends StatelessWidget {
  const RetailerOwnerCampaignDetailPage({super.key, required this.campaignId});

  /// The `:campaignId` route segment, verbatim.
  final String campaignId;

  @override
  Widget build(BuildContext context) {
    return CampaignDetailPage<RetailerCampaignDetailCubit>(
      campaignId: campaignId,
      listPath: RetailerOwnerNavigation.campaigns,
    );
  }
}
