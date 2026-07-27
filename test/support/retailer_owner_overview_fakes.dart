import 'dart:async';

import 'package:sale_reward/features/dashboard/domain/entities/retailer_owner_overview.dart';
import 'package:sale_reward/features/dashboard/domain/repositories/retailer_owner_overview_repository.dart';

/// A hand-written [RetailerOwnerOverviewRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *how many
/// times* the overview was asked for as much as what came back: [callCount] is
/// how a test proves that a duplicate refresh is suppressed, that a session
/// change reloads exactly once, and that an identical re-emitted session reloads
/// not at all.
///
/// There is nothing to record about *what was sent*, because nothing is ever
/// sent — the contract takes zero arguments, which is why this fake has no
/// captured-parameter list at all. That absence is itself the shape of the
/// contract, and a future edit that added a parameter would have to change this
/// file to compile.
class FakeRetailerOwnerOverviewRepository
    implements RetailerOwnerOverviewRepository {
  /// When set, every call answers this — how a test scripts a failure or the
  /// ineligible answer.
  RetailerOverviewResult? result;

  /// The overview returned when [result] is unset.
  RetailerOwnerOverview nextOverview = exampleRetailerOverview;

  int callCount = 0;

  /// When true, every call stays pending until it is completed by hand — so "a
  /// second refresh while one is in flight" and "a stale answer arriving after a
  /// session change" are deterministic rather than a sleep-and-hope.
  bool manual = false;
  final List<Completer<RetailerOverviewResult>> _pending =
      <Completer<RetailerOverviewResult>>[];

  int get pendingCount => _pending.length;

  /// Completes the oldest pending call.
  void complete([RetailerOverviewResult? override]) => completeAt(0, override);

  /// Completes a pending call **out of order**, so a test can make an older
  /// request answer after a newer one — the stale-response race the request
  /// token exists to close. [index] is into the pending queue, oldest first.
  void completeAt(int index, [RetailerOverviewResult? override]) {
    _pending
        .removeAt(index)
        .complete(override ?? result ?? RetailerOverviewLoaded(nextOverview));
  }

  @override
  Future<RetailerOverviewResult> overview() {
    callCount++;
    if (manual) {
      final Completer<RetailerOverviewResult> completer =
          Completer<RetailerOverviewResult>();
      _pending.add(completer);
      return completer.future;
    }
    return Future<RetailerOverviewResult>.value(
      result ?? RetailerOverviewLoaded(nextOverview),
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures
//
// Invented values. Nothing here is a real organization or a real count from any
// environment. The figures are deliberately distinct so a test asserting "the
// Total shops card shows 12" cannot pass by accidentally reading the other card.
// ---------------------------------------------------------------------------

/// An ordinary answer for an established Retailer.
const RetailerOwnerOverview exampleRetailerOverview = RetailerOwnerOverview(
  retailerName: 'Northwind Retail',
  retailerStatus: RetailerLifecycleStatus.active,
  countryCode: 'AE',
  defaultCurrency: 'AED',
  membershipStatus: RetailerMembershipStatus.active,
  totalShopCount: 12,
  activeShopCount: 9,
);

/// A **second** Retailer's answer, for session-isolation tests.
///
/// Every value differs from [exampleRetailerOverview], so "A's overview is gone"
/// is assertable on any field rather than on a single lucky one.
const RetailerOwnerOverview otherRetailerOverview = RetailerOwnerOverview(
  retailerName: 'Southgate Stores',
  retailerStatus: RetailerLifecycleStatus.active,
  countryCode: 'SA',
  defaultCurrency: 'SAR',
  membershipStatus: RetailerMembershipStatus.active,
  totalShopCount: 3,
  activeShopCount: 1,
);

/// An authorized Owner with no shops yet.
///
/// Both counts are `0` — the legitimate shape for a newly onboarded Retailer,
/// and the one a client must never confuse with a denial or a malformed answer.
const RetailerOwnerOverview newRetailerOverview = RetailerOwnerOverview(
  retailerName: 'Fresh Start Trading',
  retailerStatus: RetailerLifecycleStatus.active,
  countryCode: 'AE',
  defaultCurrency: 'AED',
  membershipStatus: RetailerMembershipStatus.active,
  totalShopCount: 0,
  activeShopCount: 0,
);

/// A Retailer whose organization is suspended.
///
/// Not reachable through the deployed resolver, which requires an ACTIVE
/// organization — modelled so the client's warning path is exercised rather than
/// assumed.
const RetailerOwnerOverview suspendedRetailerOverview = RetailerOwnerOverview(
  retailerName: 'Paused Traders',
  retailerStatus: RetailerLifecycleStatus.suspended,
  countryCode: 'AE',
  defaultCurrency: 'AED',
  membershipStatus: RetailerMembershipStatus.active,
  totalShopCount: 4,
  activeShopCount: 0,
);

/// An Owner whose own membership is suspended.
const RetailerOwnerOverview suspendedMembershipOverview = RetailerOwnerOverview(
  retailerName: 'Northwind Retail',
  retailerStatus: RetailerLifecycleStatus.active,
  countryCode: 'AE',
  defaultCurrency: 'AED',
  membershipStatus: RetailerMembershipStatus.suspended,
  totalShopCount: 12,
  activeShopCount: 9,
);

/// An organization with neither code recorded — both columns are nullable, so
/// this is a real answer and not a malformed one.
const RetailerOwnerOverview unrecordedCodesOverview = RetailerOwnerOverview(
  retailerName: 'Minimal Records Ltd',
  retailerStatus: RetailerLifecycleStatus.active,
  countryCode: null,
  defaultCurrency: null,
  membershipStatus: RetailerMembershipStatus.active,
  totalShopCount: 2,
  activeShopCount: 2,
);

/// A well-formed backend row, as PostgREST would render it.
///
/// Used by the parser tests as the baseline that individual cases mutate, so
/// each case differs from a *valid* body in exactly one way.
Map<String, Object?> retailerOverviewRow({
  Object? retailerName = 'Northwind Retail',
  Object? retailerStatus = 'ACTIVE',
  Object? countryCode = 'AE',
  Object? defaultCurrency = 'AED',
  Object? membershipStatus = 'ACTIVE',
  Object? totalShopCount = 12,
  Object? activeShopCount = 9,
}) {
  return <String, Object?>{
    'retailer_name': retailerName,
    'retailer_status': retailerStatus,
    'country_code': countryCode,
    'default_currency': defaultCurrency,
    'membership_status': membershipStatus,
    'total_shop_count': totalShopCount,
    'active_shop_count': activeShopCount,
  };
}
