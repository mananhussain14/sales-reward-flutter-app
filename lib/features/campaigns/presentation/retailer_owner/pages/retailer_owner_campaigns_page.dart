import 'package:flutter/material.dart';

import '../../../../../app/shells/retailer_owner/retailer_owner_navigation.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../shared/campaign_list_cubit.dart';
import '../../shared/campaign_list_page.dart';

/// The Retailer Owner's campaign list.
///
/// A binding, not an implementation. It fixes three things and contributes no
/// behaviour of its own:
///
/// * the **cubit type** — [RetailerCampaignListCubit], so this screen can only
///   resolve a cubit reading `list_my_retailer_campaigns()`;
/// * the **routes** — [RetailerOwnerNavigation.campaignDetail], inside this
///   role's own prefix and no other's;
/// * the **eyebrow** — [PortalKind.retailerOwner].
///
/// Everything else lives in [CampaignListPage], which both roles share, so
/// neither role owns a copy of the sections, the cards, the empty state, the
/// stale banner or the refresh rules.
///
/// ## Read-only, and there is nothing here that could become a control
///
/// A Retailer Owner cannot create, edit, publish, pause, resume, version or
/// cancel a campaign: every one is a Vendor operation on `CAMPAIGNS_MANAGE`,
/// performed on the Web application, and no such RPC is named anywhere in this
/// Flutter application.
class RetailerOwnerCampaignsPage extends StatelessWidget {
  const RetailerOwnerCampaignsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CampaignListPage<RetailerCampaignListCubit>(
      role: PortalKind.retailerOwner,
      detailPath: RetailerOwnerNavigation.campaignDetail,
    );
  }
}
