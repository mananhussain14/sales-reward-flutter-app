import 'dart:async';

import 'package:sale_reward/features/campaigns/data/models/campaign_parsers.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_lifecycle_state.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_measurement.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_offer.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_product.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_product_eligibility.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_reward.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_schedule.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_stacking_mode.dart';
import 'package:sale_reward/features/campaigns/domain/entities/retailer_campaign.dart';
import 'package:sale_reward/features/campaigns/domain/entities/staff_campaign.dart';
import 'package:sale_reward/features/campaigns/domain/repositories/retailer_campaign_repository.dart';
import 'package:sale_reward/features/campaigns/domain/repositories/staff_campaign_repository.dart';

// ---------------------------------------------------------------------------
// Raw rows, in the exact shape PostgREST renders the deployed contracts.
// ---------------------------------------------------------------------------

/// A well-formed campaign id, and two more for tests that need distinct ones.
const String campaignIdA = '11111111-2222-4333-8444-555555555555';
const String campaignIdB = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

/// One row of `list_my_retailer_campaigns()` / `get_my_retailer_campaign()`.
///
/// Every key the deployed contract's `returns table` clause declares, with
/// defaults that form a coherent `PER_UNIT_COINS` / `SELECTED_PRODUCTS` /
/// `SNAPSHOT` campaign. A test overrides only the column it is about, so a
/// change to the contract shape shows up in one place.
Map<String, Object?> retailerCampaignRow({
  Object? campaignId = campaignIdA,
  Object? campaignName = 'Summer Push',
  Object? description = 'Sell more of the summer range.',
  Object? vendorName = 'Northwind Trading',
  Object? derivedState = 'ACTIVE',
  Object? campaignStatus = 'PUBLISHED',
  Object? startsAt = '2026-07-01T00:00:00Z',
  Object? endsAt = '2026-09-30T23:59:59Z',
  Object? timezoneName = 'Asia/Dubai',
  Object? performanceScope = 'INDIVIDUAL_STAFF',
  Object? productScope = 'SELECTED_PRODUCTS',
  Object? productEligibilityResolution = 'SNAPSHOT',
  Object? stackingMode = 'STACKABLE',
  Object? rewardRecipientScope = 'CONTRIBUTING_STAFF',
  Object? ruleType = 'PER_UNIT_COINS',
  Object? metricType = 'UNITS_SOLD',
  Object? coinsPerUnit = 10,
  Object? maxRewardCoins = 100,
  Object? thresholdUnits,
  Object? rewardCoins,
  Object? eligibleProductCount = 3,
}) {
  return <String, Object?>{
    'campaign_id': campaignId,
    'campaign_name': campaignName,
    'description': description,
    'vendor_name': vendorName,
    'derived_state': derivedState,
    'campaign_status': campaignStatus,
    'starts_at': startsAt,
    'ends_at': endsAt,
    'timezone_name': timezoneName,
    'performance_scope': performanceScope,
    'product_scope': productScope,
    'product_eligibility_resolution': productEligibilityResolution,
    'stacking_mode': stackingMode,
    'reward_recipient_scope': rewardRecipientScope,
    'rule_type': ruleType,
    'metric_type': metricType,
    'coins_per_unit': coinsPerUnit,
    'max_reward_coins': maxRewardCoins,
    'threshold_units': thresholdUnits,
    'reward_coins': rewardCoins,
    'eligible_product_count': eligibleProductCount,
  };
}

/// One row of `list_my_staff_campaigns()` / `get_my_staff_campaign()`.
///
/// The Retailer row **minus** `vendor_name` and `campaign_status`, which the
/// staff contract does not return. Built by removing them rather than by
/// listing nineteen keys again, so the "two columns fewer" relationship is
/// stated once and cannot drift.
Map<String, Object?> staffCampaignRow({
  Object? campaignId = campaignIdA,
  Object? campaignName = 'Summer Push',
  Object? description = 'Sell more of the summer range.',
  Object? derivedState = 'ACTIVE',
  Object? startsAt = '2026-07-01T00:00:00Z',
  Object? endsAt = '2026-09-30T23:59:59Z',
  Object? timezoneName = 'Asia/Dubai',
  Object? performanceScope = 'INDIVIDUAL_STAFF',
  Object? productScope = 'SELECTED_PRODUCTS',
  Object? productEligibilityResolution = 'SNAPSHOT',
  Object? stackingMode = 'STACKABLE',
  Object? rewardRecipientScope = 'CONTRIBUTING_STAFF',
  Object? ruleType = 'PER_UNIT_COINS',
  Object? metricType = 'UNITS_SOLD',
  Object? coinsPerUnit = 10,
  Object? maxRewardCoins = 100,
  Object? thresholdUnits,
  Object? rewardCoins,
  Object? eligibleProductCount = 3,
}) {
  return retailerCampaignRow(
    campaignId: campaignId,
    campaignName: campaignName,
    description: description,
    derivedState: derivedState,
    startsAt: startsAt,
    endsAt: endsAt,
    timezoneName: timezoneName,
    performanceScope: performanceScope,
    productScope: productScope,
    productEligibilityResolution: productEligibilityResolution,
    stackingMode: stackingMode,
    rewardRecipientScope: rewardRecipientScope,
    ruleType: ruleType,
    metricType: metricType,
    coinsPerUnit: coinsPerUnit,
    maxRewardCoins: maxRewardCoins,
    thresholdUnits: thresholdUnits,
    rewardCoins: rewardCoins,
    eligibleProductCount: eligibleProductCount,
  )..removeWhere(
    (String key, Object? _) => key == 'vendor_name' || key == 'campaign_status',
  );
}

/// One row of either `list_my_*_campaign_products()`.
Map<String, Object?> campaignProductRow({
  Object? productId = 'ffffffff-1111-4222-8333-444444444444',
  Object? productCode = 'SUM-001',
  Object? barcode = '05012345678900',
  Object? productName = 'Summer Cooler 500ml',
  Object? brand = 'Northwind',
}) {
  return <String, Object?>{
    'product_id': productId,
    'product_code': productCode,
    'barcode': barcode,
    'product_name': productName,
    'brand': brand,
  };
}

// ---------------------------------------------------------------------------
// Domain builders, for tests above the parser.
// ---------------------------------------------------------------------------

/// A coherent campaign offer with sensible defaults.
CampaignOffer exampleOffer({
  String campaignId = campaignIdA,
  String name = 'Summer Push',
  String? description = 'Sell more of the summer range.',
  CampaignLifecycleState lifecycleState = CampaignLifecycleState.active,
  DateTime? startsAt,
  DateTime? endsAt,

  /// Builds the evergreen case — `ends_at` genuinely null — which a null
  /// [endsAt] cannot express, because null there means "use the default".
  bool evergreen = false,
  String timeZoneName = 'Asia/Dubai',
  CampaignPerformanceScope performanceScope =
      CampaignPerformanceScope.individualStaff,
  CampaignProductScope productScope = CampaignProductScope.selectedProducts,
  CampaignStackingMode stackingMode = CampaignStackingMode.stackable,
  CampaignReward? reward,
  int eligibleProductCount = 3,
}) {
  return CampaignOffer(
    campaignId: campaignId,
    name: name,
    description: description,
    lifecycleState: lifecycleState,
    schedule: CampaignSchedule(
      startsAt: startsAt ?? DateTime.utc(2026, 7),
      endsAt: evergreen ? null : (endsAt ?? DateTime.utc(2026, 9, 30)),
      timeZoneName: timeZoneName,
    ),
    performanceScope: performanceScope,
    rewardRecipientScope: CampaignRewardRecipientScope.contributingStaff,
    productEligibility: CampaignProductEligibility(
      scope: productScope,
      // The pairing the table enforces, so a builder cannot produce a campaign
      // the backend could not have stored.
      resolution: productScope == CampaignProductScope.selectedProducts
          ? CampaignProductEligibilityResolution.snapshot
          : CampaignProductEligibilityResolution.liveTemporal,
      eligibleProductCount: eligibleProductCount,
    ),
    stackingMode: stackingMode,
    reward:
        reward ??
        const CampaignPerUnitReward(
          coinsPerUnit: 10,
          maxRewardCoins: 100,
          metric: CampaignMetricType.unitsSold,
        ),
  );
}

RetailerCampaign exampleRetailerCampaign({
  CampaignOffer? offer,
  String vendorName = 'Northwind Trading',
  CampaignManagementStatus managementStatus =
      CampaignManagementStatus.published,
}) {
  return RetailerCampaign(
    offer: offer ?? exampleOffer(),
    vendorName: vendorName,
    managementStatus: managementStatus,
  );
}

StaffCampaign exampleStaffCampaign({CampaignOffer? offer}) =>
    StaffCampaign(offer: offer ?? exampleOffer());

const List<CampaignProduct> exampleCampaignProducts = <CampaignProduct>[
  CampaignProduct(
    productCode: 'SUM-001',
    productName: 'Summer Cooler 500ml',
    barcode: '05012345678900',
    brand: 'Northwind',
  ),
  CampaignProduct(
    productCode: 'SUM-002',
    productName: 'Summer Cooler 1L',
    barcode: null,
    brand: null,
  ),
];

// ---------------------------------------------------------------------------
// Repository fakes.
// ---------------------------------------------------------------------------

/// Completion plumbing shared by both fakes.
///
/// Hand-written rather than mocked because these tests care about *how many
/// times* each contract was asked for as much as what came back: [callCount] is
/// how a test proves a duplicate refresh is suppressed, that opening one tab
/// does not read another, and that a session change reloads exactly once.
///
/// [manual] makes a call stay pending until completed by hand, so "a second
/// refresh while one is in flight" and "a stale answer arriving after a session
/// change" are deterministic rather than a sleep-and-hope.
class _Pending<T> {
  final List<Completer<T>> _queue = <Completer<T>>[];

  int get length => _queue.length;

  Future<T> add() {
    final Completer<T> completer = Completer<T>();
    _queue.add(completer);
    return completer.future;
  }

  void completeAt(int index, T value) => _queue.removeAt(index).complete(value);
}

/// A hand-written [RetailerCampaignRepository] fake.
///
/// [campaigns] records nothing about *what was sent*, because nothing is ever
/// sent — the contract takes zero arguments, which is why there is no captured
/// parameter list for it. That absence is itself the shape of the contract: a
/// future edit adding a parameter would have to change this file to compile.
///
/// [campaignDetail] does record its argument, in [requestedCampaignIds],
/// because the id is the one value this feature transmits and a test needs to
/// prove it is exactly what the route carried — and nothing else.
class FakeRetailerCampaignRepository implements RetailerCampaignRepository {
  RetailerCampaignsResult? listResult;
  List<RetailerCampaign> nextCampaigns = <RetailerCampaign>[
    exampleRetailerCampaign(),
  ];

  RetailerCampaignDetailResult? detailResult;

  int callCount = 0;
  int detailCallCount = 0;
  bool manual = false;

  final List<String> requestedCampaignIds = <String>[];

  final _Pending<RetailerCampaignsResult> _pending =
      _Pending<RetailerCampaignsResult>();

  int get pendingCount => _pending.length;

  void complete([RetailerCampaignsResult? override]) => completeAt(0, override);

  void completeAt(int index, [RetailerCampaignsResult? override]) {
    _pending.completeAt(
      index,
      override ?? listResult ?? RetailerCampaignsLoaded(nextCampaigns),
    );
  }

  @override
  Future<RetailerCampaignsResult> campaigns() {
    callCount++;
    if (manual) {
      return _pending.add();
    }
    return Future<RetailerCampaignsResult>.value(
      listResult ?? RetailerCampaignsLoaded(nextCampaigns),
    );
  }

  @override
  Future<RetailerCampaignDetailResult> campaignDetail(String campaignId) {
    detailCallCount++;
    requestedCampaignIds.add(campaignId);
    // Mirrors the real repository, which refuses a malformed id on the device
    // before it reaches a `uuid` parameter. A fake that answered a loaded
    // campaign for `not-a-uuid` would let a flow test pass over behaviour the
    // shipped code does not have.
    if (!isCampaignIdShaped(campaignId)) {
      return Future<RetailerCampaignDetailResult>.value(
        const RetailerCampaignDetailMissing(),
      );
    }
    return Future<RetailerCampaignDetailResult>.value(
      detailResult ??
          RetailerCampaignDetailLoaded(
            campaign: exampleRetailerCampaign(),
            products: exampleCampaignProducts,
          ),
    );
  }
}

/// A hand-written [StaffCampaignRepository] fake. The twin of the above, over
/// the narrower contract.
class FakeStaffCampaignRepository implements StaffCampaignRepository {
  StaffCampaignsResult? listResult;
  List<StaffCampaign> nextCampaigns = <StaffCampaign>[exampleStaffCampaign()];

  StaffCampaignDetailResult? detailResult;

  int callCount = 0;
  int detailCallCount = 0;
  bool manual = false;

  final List<String> requestedCampaignIds = <String>[];

  final _Pending<StaffCampaignsResult> _pending =
      _Pending<StaffCampaignsResult>();

  int get pendingCount => _pending.length;

  void complete([StaffCampaignsResult? override]) => completeAt(0, override);

  void completeAt(int index, [StaffCampaignsResult? override]) {
    _pending.completeAt(
      index,
      override ?? listResult ?? StaffCampaignsLoaded(nextCampaigns),
    );
  }

  @override
  Future<StaffCampaignsResult> campaigns() {
    callCount++;
    if (manual) {
      return _pending.add();
    }
    return Future<StaffCampaignsResult>.value(
      listResult ?? StaffCampaignsLoaded(nextCampaigns),
    );
  }

  @override
  Future<StaffCampaignDetailResult> campaignDetail(String campaignId) {
    detailCallCount++;
    requestedCampaignIds.add(campaignId);
    // Mirrors the real repository — see the Retailer fake above.
    if (!isCampaignIdShaped(campaignId)) {
      return Future<StaffCampaignDetailResult>.value(
        const StaffCampaignDetailMissing(),
      );
    }
    return Future<StaffCampaignDetailResult>.value(
      detailResult ??
          StaffCampaignDetailLoaded(
            campaign: exampleStaffCampaign(),
            products: exampleCampaignProducts,
          ),
    );
  }
}
