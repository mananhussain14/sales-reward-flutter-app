import 'package:flutter/material.dart';

import '../../../../../app/shells/sales_staff/sales_staff_navigation.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../shared/campaign_list_cubit.dart';
import '../../shared/campaign_list_page.dart';

/// The Sales Staff campaign list.
///
/// A binding over [CampaignListPage], fixing the cubit type to
/// [SalesStaffCampaignListCubit] — so this screen can only resolve a cubit
/// reading `list_my_staff_campaigns()` — and the routes to this role's own
/// prefix.
///
/// ## What a seller sees, and what they do not
///
/// * **Only `ACTIVE` and `SCHEDULED` campaigns.** Filtered in SQL, on the
///   derived state. Nothing on the device applies or restates that rule, so a
///   campaign that is paused while the list is open simply disappears on the
///   next read.
/// * **No Vendor name.** `list_my_staff_campaigns()` does not return one, so no
///   card here has a Vendor line. That is a recorded deviation from the
///   milestone brief — see [StaffCampaign] — and it is the backend's deliberate
///   choice, not an omission here.
/// * **No Retailer Owner surface.** No campaign history, no other Retailer, no
///   Retailer group, no exclusivity key or priority, no internal id. None is
///   returned by this contract, and the Owner contract that returns some of them
///   refuses a seller with `42501`.
/// * **No actions of any kind.** Not the Owner's, and certainly not the
///   Vendor's.
class SalesStaffCampaignsPage extends StatelessWidget {
  const SalesStaffCampaignsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CampaignListPage<SalesStaffCampaignListCubit>(
      role: PortalKind.salesStaff,
      detailPath: SalesStaffNavigation.campaignDetail,
    );
  }
}
