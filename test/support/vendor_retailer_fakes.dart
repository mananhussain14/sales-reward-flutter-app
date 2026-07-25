import 'dart:async';

import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/retailers/domain/entities/retailer_owner_state.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_detail.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_shop.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_summary.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_repository.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_result.dart';

/// A hand-written [VendorRetailerRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *what was
/// sent* as much as what came back: [requestedDetailIds] and
/// [requestedShopIds] are how a test proves that one relationship id — and
/// nothing beside it — ever leaves the client, and that the shop read is not
/// issued for a Retailer the detail read refused.
class FakeVendorRetailerRepository implements VendorRetailerRepository {
  VendorRetailerResult<List<VendorRetailerSummary>> retailersResult =
      VendorRetailerReadSuccess<List<VendorRetailerSummary>>(
        <VendorRetailerSummary>[northwindSummary, contosoSummary],
      );

  /// When set, every detail read answers this whatever id was asked for — how a
  /// test scripts a failure or a blanket "not addressable".
  VendorRetailerResult<VendorRetailerDetail?>? detailResult;

  /// Otherwise the fake answers the way the backend does: a relationship this
  /// caller may read returns its row, and **every** other id — unknown,
  /// foreign, or malformed — returns zero rows, indistinguishably.
  Map<String, VendorRetailerDetail> knownDetails =
      <String, VendorRetailerDetail>{
        northwindRelationshipUuid: northwindDetail,
        contosoRelationshipUuid: contosoDetail,
      };

  VendorRetailerResult<List<VendorRetailerShop>> shopsResult =
      const VendorRetailerReadSuccess<List<VendorRetailerShop>>(
        <VendorRetailerShop>[marinaShop, airportShop],
      );

  int retailersCallCount = 0;
  final List<String> requestedDetailIds = <String>[];
  final List<String> requestedShopIds = <String>[];

  int get detailCallCount => requestedDetailIds.length;
  int get shopsCallCount => requestedShopIds.length;

  /// When true, every [retailers] call stays pending until [completeRetailers]
  /// is called — so "a second refresh while one is in flight" is deterministic
  /// rather than a sleep-and-hope.
  bool manualRetailers = false;
  final List<Completer<VendorRetailerResult<List<VendorRetailerSummary>>>>
  _pendingRetailers =
      <Completer<VendorRetailerResult<List<VendorRetailerSummary>>>>[];

  int get pendingRetailerCount => _pendingRetailers.length;

  void completeRetailers([
    VendorRetailerResult<List<VendorRetailerSummary>>? override,
  ]) {
    _pendingRetailers.removeAt(0).complete(override ?? retailersResult);
  }

  /// The same control for the detail read, so the ordering of the two calls can
  /// be asserted rather than inferred.
  bool manualDetail = false;
  final List<Completer<VendorRetailerResult<VendorRetailerDetail?>>>
  _pendingDetail = <Completer<VendorRetailerResult<VendorRetailerDetail?>>>[];

  int get pendingDetailCount => _pendingDetail.length;

  void completeDetail([VendorRetailerResult<VendorRetailerDetail?>? override]) {
    _pendingDetail
        .removeAt(0)
        .complete(override ?? _detailFor(requestedDetailIds.last));
  }

  @override
  Future<VendorRetailerResult<List<VendorRetailerSummary>>> retailers() {
    retailersCallCount++;
    if (manualRetailers) {
      final Completer<VendorRetailerResult<List<VendorRetailerSummary>>>
      completer =
          Completer<VendorRetailerResult<List<VendorRetailerSummary>>>();
      _pendingRetailers.add(completer);
      return completer.future;
    }
    return Future<VendorRetailerResult<List<VendorRetailerSummary>>>.value(
      retailersResult,
    );
  }

  @override
  Future<VendorRetailerResult<VendorRetailerDetail?>> retailerDetail(
    String relationshipId,
  ) {
    requestedDetailIds.add(relationshipId);
    if (manualDetail) {
      final Completer<VendorRetailerResult<VendorRetailerDetail?>> completer =
          Completer<VendorRetailerResult<VendorRetailerDetail?>>();
      _pendingDetail.add(completer);
      return completer.future;
    }
    return Future<VendorRetailerResult<VendorRetailerDetail?>>.value(
      _detailFor(relationshipId),
    );
  }

  VendorRetailerResult<VendorRetailerDetail?> _detailFor(
    String relationshipId,
  ) =>
      detailResult ??
      VendorRetailerReadSuccess<VendorRetailerDetail?>(
        knownDetails[relationshipId],
      );

  @override
  Future<VendorRetailerResult<List<VendorRetailerShop>>> retailerShops(
    String relationshipId,
  ) {
    requestedShopIds.add(relationshipId);
    return Future<VendorRetailerResult<List<VendorRetailerShop>>>.value(
      shopsResult,
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String northwindRelationshipUuid = '3f7c1a10-2b4d-4e6f-8a90-1b2c3d4e5f60';
const String northwindOrganizationUuid = '4a8d2b21-3c5e-4f70-9b01-2c3d4e5f6071';
const String contosoRelationshipUuid = '5b9e3c32-4d6f-4081-ac12-3d4e5f607182';
const String contosoOrganizationUuid = '6caf4d43-5e70-4192-bd23-4e5f60718293';

/// A relationship id belonging to no row this caller may read. Well formed on
/// purpose: the point is that a *valid-looking* foreign id is inert.
const String foreignRelationshipUuid = '7db05e54-6f81-42a3-ce34-5f6071829304';

const String marinaShopUuid = '11111111-2222-3333-4444-555555555555';
const String airportShopUuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

final DateTime northwindOnboardedAt = DateTime.utc(2026, 3, 12, 8, 15);
final DateTime contosoOnboardedAt = DateTime.utc(2026, 5, 2, 11, 40);

final VendorRetailerSummary northwindSummary = VendorRetailerSummary(
  relationshipId: northwindRelationshipUuid,
  retailerOrganizationId: northwindOrganizationUuid,
  retailerName: 'Northwind Retail',
  retailerStatus: VendorRetailerStatus.active,
  relationshipStatus: VendorRetailerStatus.active,
  relationshipCreatedAt: northwindOnboardedAt,
  shopCount: 4,
  activeShopCount: 3,
  ownerState: RetailerOwnerState.active,
);

/// Deliberately a *suspended* relationship with **no** owner and **no** shops:
/// every one of those is a state the screens must render rather than hide.
final VendorRetailerSummary contosoSummary = VendorRetailerSummary(
  relationshipId: contosoRelationshipUuid,
  retailerOrganizationId: contosoOrganizationUuid,
  retailerName: 'Contoso Stores',
  retailerStatus: VendorRetailerStatus.active,
  relationshipStatus: VendorRetailerStatus.suspended,
  relationshipCreatedAt: contosoOnboardedAt,
  shopCount: 0,
  activeShopCount: 0,
  ownerState: RetailerOwnerState.none,
);

final VendorRetailerDetail northwindDetail = VendorRetailerDetail(
  relationshipId: northwindRelationshipUuid,
  retailerOrganizationId: northwindOrganizationUuid,
  retailerName: 'Northwind Retail',
  retailerStatus: VendorRetailerStatus.active,
  countryCode: 'AE',
  defaultCurrency: 'AED',
  relationshipStatus: VendorRetailerStatus.active,
  relationshipCreatedAt: northwindOnboardedAt,
  shopCount: 4,
  activeShopCount: 3,
  ownerState: RetailerOwnerState.active,
);

/// Deliberately without a country or a currency: both `organizations` columns
/// are nullable, so a Retailer that never recorded one must render.
final VendorRetailerDetail contosoDetail = VendorRetailerDetail(
  relationshipId: contosoRelationshipUuid,
  retailerOrganizationId: contosoOrganizationUuid,
  retailerName: 'Contoso Stores',
  retailerStatus: VendorRetailerStatus.active,
  countryCode: null,
  defaultCurrency: null,
  relationshipStatus: VendorRetailerStatus.suspended,
  relationshipCreatedAt: contosoOnboardedAt,
  shopCount: 0,
  activeShopCount: 0,
  ownerState: RetailerOwnerState.none,
);

const VendorRetailerShop marinaShop = VendorRetailerShop(
  shopId: marinaShopUuid,
  shopName: 'Marina Mall',
  shopStatus: VendorRetailerStatus.active,
  shopCode: 'MM-01',
  city: 'Dubai',
  countryCode: 'AE',
);

/// Deliberately inactive and code-less: `retailer_shops.code`, `city` and
/// `country_code` are all nullable, and a `SUSPENDED` shop stays listed.
const VendorRetailerShop airportShop = VendorRetailerShop(
  shopId: airportShopUuid,
  shopName: 'Airport Kiosk',
  shopStatus: VendorRetailerStatus.suspended,
);

/// A `list_vendor_retailers()` body, as PostgREST returns it.
List<Map<String, Object?>> retailerRows() => <Map<String, Object?>>[
  retailerRow(),
  retailerRow(
    relationshipId: contosoRelationshipUuid,
    retailerOrganizationId: contosoOrganizationUuid,
    retailerName: 'Contoso Stores',
    relationshipStatus: 'SUSPENDED',
    createdAt: '2026-05-02T11:40:00+00:00',
    shopCount: 0,
    activeShopCount: 0,
    ownerState: 'NONE',
  ),
];

Map<String, Object?> retailerRow({
  Object? relationshipId = northwindRelationshipUuid,
  Object? retailerOrganizationId = northwindOrganizationUuid,
  Object? retailerName = 'Northwind Retail',
  Object? retailerStatus = 'ACTIVE',
  Object? relationshipStatus = 'ACTIVE',
  Object? createdAt = '2026-03-12T08:15:00+00:00',
  Object? shopCount = 4,
  Object? activeShopCount = 3,
  Object? ownerState = 'ACTIVE',
}) => <String, Object?>{
  'relationship_id': relationshipId,
  'retailer_organization_id': retailerOrganizationId,
  'retailer_name': retailerName,
  'retailer_status': retailerStatus,
  'relationship_status': relationshipStatus,
  'relationship_created_at': createdAt,
  'shop_count': shopCount,
  'active_shop_count': activeShopCount,
  'owner_state': ownerState,
};

/// A `get_vendor_retailer_detail(uuid)` row — the list shape plus the two
/// Retailer profile columns.
Map<String, Object?> detailRow({
  Object? countryCode = 'AE',
  Object? defaultCurrency = 'AED',
  Object? retailerStatus = 'ACTIVE',
  Object? relationshipStatus = 'ACTIVE',
  Object? shopCount = 4,
  Object? activeShopCount = 3,
  Object? ownerState = 'ACTIVE',
}) => <String, Object?>{
  ...retailerRow(
    retailerStatus: retailerStatus,
    relationshipStatus: relationshipStatus,
    shopCount: shopCount,
    activeShopCount: activeShopCount,
    ownerState: ownerState,
  ),
  'country_code': countryCode,
  'default_currency': defaultCurrency,
};

/// A `list_vendor_retailer_shops(uuid)` body.
List<Map<String, Object?>> shopRows() => <Map<String, Object?>>[
  shopRow(),
  shopRow(
    shopId: airportShopUuid,
    shopName: 'Airport Kiosk',
    shopCode: null,
    city: null,
    countryCode: null,
    shopStatus: 'SUSPENDED',
  ),
];

Map<String, Object?> shopRow({
  Object? shopId = marinaShopUuid,
  Object? shopName = 'Marina Mall',
  Object? shopCode = 'MM-01',
  Object? city = 'Dubai',
  Object? countryCode = 'AE',
  Object? shopStatus = 'ACTIVE',
}) => <String, Object?>{
  'shop_id': shopId,
  'shop_name': shopName,
  'shop_code': shopCode,
  'city': city,
  'country_code': countryCode,
  'shop_status': shopStatus,
};

/// A read that failed the way an unreadable body does.
VendorRetailerResult<T> unavailableRetailerRead<T>() =>
    VendorRetailerReadFailure<T>(const UnavailableFailure());

/// A read the backend refused with `42501`.
VendorRetailerResult<T> deniedRetailerRead<T>() =>
    VendorRetailerReadFailure<T>(const DeniedFailure());
