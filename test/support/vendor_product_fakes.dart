import 'dart:async';

import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assigned_retailer.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_detail.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_summary.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_repository.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_status.dart';

/// A hand-written [VendorProductRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *what was
/// sent* and *in what order* as much as what came back: [requestedDetailIds] and
/// [requestedAssignmentIds] are how a test proves that one product id — and
/// nothing beside it — ever leaves the client, and [callLog] is how it proves
/// the assignment read is never issued for a product the detail read could not
/// return.
class FakeVendorProductRepository implements VendorProductRepository {
  ReadResult<List<VendorProductSummary>> productsResult =
      ReadSuccess<List<VendorProductSummary>>(productCatalogueSummaries);

  /// When set, every detail read answers this whatever id was asked for — how a
  /// test scripts a failure or a blanket "not addressable".
  ReadResult<VendorProductDetail?>? detailResult;

  /// Otherwise the fake answers the way the backend does: an id that names one
  /// of this Vendor's products returns its row, and **every** other id —
  /// unknown, another Vendor's, from another table, or malformed — returns zero
  /// rows, indistinguishably.
  Map<String, VendorProductDetail> knownDetails = <String, VendorProductDetail>{
    espressoProductUuid: espressoDetail,
    decafProductUuid: decafDetail,
    retiredProductUuid: retiredDetail,
    unassignedProductUuid: unassignedDetail,
  };

  /// When set, every assignment read answers this.
  ReadResult<List<VendorProductAssignedRetailer>>? assignmentsResult;

  /// Otherwise: the assignments for the requested product, or an empty list —
  /// which is also what an id naming no product produces.
  Map<String, List<VendorProductAssignedRetailer>> knownAssignments =
      <String, List<VendorProductAssignedRetailer>>{
        espressoProductUuid: espressoAssignments,
        retiredProductUuid: retiredAssignments,
      };

  int productsCallCount = 0;
  final List<String> requestedDetailIds = <String>[];
  final List<String> requestedAssignmentIds = <String>[];

  int get detailCallCount => requestedDetailIds.length;
  int get assignmentsCallCount => requestedAssignmentIds.length;

  /// The order the reads were issued in, so a test can assert the sequence
  /// rather than only the counts.
  final List<String> callLog = <String>[];

  /// When true, every [products] call stays pending until [completeProducts] is
  /// called — so "a second refresh while one is in flight" is deterministic
  /// rather than a sleep-and-hope.
  bool manualProducts = false;
  final List<Completer<ReadResult<List<VendorProductSummary>>>>
  _pendingProducts = <Completer<ReadResult<List<VendorProductSummary>>>>[];

  int get pendingProductCount => _pendingProducts.length;

  void completeProducts([ReadResult<List<VendorProductSummary>>? override]) {
    _pendingProducts.removeAt(0).complete(override ?? productsResult);
  }

  /// The same control for the detail read.
  bool manualDetail = false;
  final List<Completer<ReadResult<VendorProductDetail?>>> _pendingDetail =
      <Completer<ReadResult<VendorProductDetail?>>>[];

  int get pendingDetailCount => _pendingDetail.length;

  void completeDetail([ReadResult<VendorProductDetail?>? override]) =>
      completeDetailAt(0, override);

  /// Completes a pending detail read **out of order**, so a test can make an
  /// *older* request answer after a newer one — the stale-response race the
  /// request token exists to close. [index] is into the pending queue, oldest
  /// first.
  void completeDetailAt(
    int index, [
    ReadResult<VendorProductDetail?>? override,
  ]) {
    final Completer<ReadResult<VendorProductDetail?>> completer = _pendingDetail
        .removeAt(index);
    completer.complete(override ?? _detailFor(requestedDetailIds[index]));
  }

  /// And for the assignment companion.
  bool manualAssignments = false;
  final List<Completer<ReadResult<List<VendorProductAssignedRetailer>>>>
  _pendingAssignments =
      <Completer<ReadResult<List<VendorProductAssignedRetailer>>>>[];

  int get pendingAssignmentCount => _pendingAssignments.length;

  void completeAssignments([
    ReadResult<List<VendorProductAssignedRetailer>>? override,
  ]) {
    _pendingAssignments
        .removeAt(0)
        .complete(override ?? _assignmentsFor(requestedAssignmentIds.last));
  }

  @override
  Future<ReadResult<List<VendorProductSummary>>> products() {
    productsCallCount++;
    callLog.add('products');
    if (manualProducts) {
      final Completer<ReadResult<List<VendorProductSummary>>> completer =
          Completer<ReadResult<List<VendorProductSummary>>>();
      _pendingProducts.add(completer);
      return completer.future;
    }
    return Future<ReadResult<List<VendorProductSummary>>>.value(productsResult);
  }

  @override
  Future<ReadResult<VendorProductDetail?>> productDetail(String productId) {
    requestedDetailIds.add(productId);
    callLog.add('detail');
    if (manualDetail) {
      final Completer<ReadResult<VendorProductDetail?>> completer =
          Completer<ReadResult<VendorProductDetail?>>();
      _pendingDetail.add(completer);
      return completer.future;
    }
    return Future<ReadResult<VendorProductDetail?>>.value(
      _detailFor(productId),
    );
  }

  @override
  Future<ReadResult<List<VendorProductAssignedRetailer>>> assignedRetailers(
    String productId,
  ) {
    requestedAssignmentIds.add(productId);
    callLog.add('assignments');
    if (manualAssignments) {
      final Completer<ReadResult<List<VendorProductAssignedRetailer>>>
      completer = Completer<ReadResult<List<VendorProductAssignedRetailer>>>();
      _pendingAssignments.add(completer);
      return completer.future;
    }
    return Future<ReadResult<List<VendorProductAssignedRetailer>>>.value(
      _assignmentsFor(productId),
    );
  }

  ReadResult<VendorProductDetail?> _detailFor(String productId) =>
      detailResult ??
      ReadSuccess<VendorProductDetail?>(knownDetails[productId]);

  ReadResult<List<VendorProductAssignedRetailer>> _assignmentsFor(
    String productId,
  ) =>
      assignmentsResult ??
      ReadSuccess<List<VendorProductAssignedRetailer>>(
        knownAssignments[productId] ?? const <VendorProductAssignedRetailer>[],
      );
}

// ---------------------------------------------------------------------------
// Fixtures
//
// Invented product names, codes, barcodes and ids. Nothing here is a real
// identifier from any environment. The shape follows the deployed contract:
//
//   * an ACTIVE product with a barcode, a brand, a description and both active
//     and withdrawn assignments — including one whose relationship row is gone;
//   * an ACTIVE product with NO barcode, NO brand and NO description, so the
//     three nullable cases have to render honestly rather than be filled in;
//   * an INACTIVE product that KEEPS its assignments and counts, which is the
//     case the whole "deactivating is not deleting" distinction exists for;
//   * an ACTIVE product that has never been assigned to anybody, so the empty
//     assignment state is distinguishable from a foreign id.
// ---------------------------------------------------------------------------

const String espressoProductUuid = '7a1b2c3d-4e5f-4061-8273-94a5b6c7d8e9';
const String decafProductUuid = '8b2c3d4e-5f60-4172-8384-a5b6c7d8e9f0';
const String retiredProductUuid = '9c3d4e5f-6071-4283-8495-b6c7d8e9f0a1';
const String unassignedProductUuid = '0d4e5f60-7182-4394-85a6-c7d8e9f0a1b2';

/// A well-formed id that names no product this caller can read. Well formed on
/// purpose: the point is that a *valid-looking* id is inert. It stands in
/// equally for an unknown product, for another Vendor's product and for an id
/// belonging to some other table — the backend answers zero rows for all three,
/// indistinguishably.
const String unknownProductUuid = '1e5f6071-8293-44a5-b6c7-d8e9f0a1b2c3';

/// `vendor_retailers.id` values — the address the shipped Retailer detail route
/// accepts, and the only thing an assignment row may navigate by.
const String northwindRelationshipId = '2f607182-93a4-45b6-c7d8-e9f0a1b2c3d4';
const String harbourRelationshipId = '30718293-a4b5-46c7-d8e9-f0a1b2c3d4e5';

/// `organizations.id` values — output only. Never a route selector and never
/// sent to a read.
const String northwindOrgId = '41829304-b5c6-47d8-e9f0-a1b2c3d4e5f6';
const String harbourOrgId = '5293a4b5-c6d7-48e9-f0a1-b2c3d4e5f607';
const String orphanedOrgId = '63a4b5c6-d7e8-49f0-a1b2-c3d4e5f60718';

final DateTime espressoCreatedAt = DateTime.utc(2026, 4, 18, 9, 15);
final DateTime espressoUpdatedAt = DateTime.utc(2026, 6, 2, 14, 30);
final DateTime decafCreatedAt = DateTime.utc(2026, 3, 7, 11, 0);
final DateTime decafUpdatedAt = DateTime.utc(2026, 3, 7, 11, 0);
final DateTime retiredCreatedAt = DateTime.utc(2026, 1, 22, 8, 45);
final DateTime retiredUpdatedAt = DateTime.utc(2026, 5, 14, 16, 20);
final DateTime unassignedCreatedAt = DateTime.utc(2026, 2, 3, 10, 5);
final DateTime unassignedUpdatedAt = DateTime.utc(2026, 2, 3, 10, 5);

/// Fully populated and actively assigned. Its detail counts **3 total, 2
/// active** — which is exactly what [espressoAssignments] contains.
final VendorProductSummary espressoSummary = VendorProductSummary(
  productId: espressoProductUuid,
  productCode: 'ESP-1000',
  barcode: '5012345678900',
  productName: 'Espresso Blend 1kg',
  brand: 'Harvest Roasters',
  description: 'A dark roast blend for espresso machines.',
  status: VendorProductStatus.active,
  activeAssignmentCount: 2,
  createdAt: espressoCreatedAt,
  updatedAt: espressoUpdatedAt,
);

final VendorProductDetail espressoDetail = VendorProductDetail(
  productId: espressoProductUuid,
  productCode: 'ESP-1000',
  barcode: '5012345678900',
  productName: 'Espresso Blend 1kg',
  brand: 'Harvest Roasters',
  description: 'A dark roast blend for espresso machines.',
  status: VendorProductStatus.active,
  assignmentCount: 3,
  activeAssignmentCount: 2,
  createdAt: espressoCreatedAt,
  updatedAt: espressoUpdatedAt,
);

/// Active, **no barcode**, **no brand**, **no description** — three nullable
/// cases that must render honestly rather than be filled in from the name.
final VendorProductSummary decafSummary = VendorProductSummary(
  productId: decafProductUuid,
  productCode: 'DEC-2000',
  barcode: null,
  productName: 'Decaf Ground 500g',
  brand: null,
  description: null,
  status: VendorProductStatus.active,
  activeAssignmentCount: 0,
  createdAt: decafCreatedAt,
  updatedAt: decafUpdatedAt,
);

final VendorProductDetail decafDetail = VendorProductDetail(
  productId: decafProductUuid,
  productCode: 'DEC-2000',
  barcode: null,
  productName: 'Decaf Ground 500g',
  brand: null,
  description: null,
  status: VendorProductStatus.active,
  assignmentCount: 0,
  activeAssignmentCount: 0,
  createdAt: decafCreatedAt,
  updatedAt: decafUpdatedAt,
);

/// **Inactive, with an assignment still active.** `set_vendor_product_status`
/// does not cascade, so the counts stay real and the rows stay visible.
final VendorProductSummary retiredSummary = VendorProductSummary(
  productId: retiredProductUuid,
  productCode: 'RET-3000',
  barcode: '5012345678917',
  productName: 'Seasonal Roast 250g',
  brand: 'Harvest Roasters',
  description: 'A limited seasonal roast, no longer in the active range.',
  status: VendorProductStatus.inactive,
  activeAssignmentCount: 1,
  createdAt: retiredCreatedAt,
  updatedAt: retiredUpdatedAt,
);

final VendorProductDetail retiredDetail = VendorProductDetail(
  productId: retiredProductUuid,
  productCode: 'RET-3000',
  barcode: '5012345678917',
  productName: 'Seasonal Roast 250g',
  brand: 'Harvest Roasters',
  description: 'A limited seasonal roast, no longer in the active range.',
  status: VendorProductStatus.inactive,
  assignmentCount: 1,
  activeAssignmentCount: 1,
  createdAt: retiredCreatedAt,
  updatedAt: retiredUpdatedAt,
);

/// Active and never assigned to anybody. Both counts are `0` — a real answer,
/// never null — and the companion returns `[]`, which is only distinguishable
/// from "not your product" because the detail read came back first.
final VendorProductSummary unassignedSummary = VendorProductSummary(
  productId: unassignedProductUuid,
  productCode: 'NEW-4000',
  barcode: null,
  productName: 'Cold Brew Concentrate 1L',
  brand: 'Harvest Roasters',
  description: null,
  status: VendorProductStatus.active,
  activeAssignmentCount: 0,
  createdAt: unassignedCreatedAt,
  updatedAt: unassignedUpdatedAt,
);

final VendorProductDetail unassignedDetail = VendorProductDetail(
  productId: unassignedProductUuid,
  productCode: 'NEW-4000',
  barcode: null,
  productName: 'Cold Brew Concentrate 1L',
  brand: 'Harvest Roasters',
  description: null,
  status: VendorProductStatus.active,
  assignmentCount: 0,
  activeAssignmentCount: 0,
  createdAt: unassignedCreatedAt,
  updatedAt: unassignedUpdatedAt,
);

/// The catalogue in the backend's `created_at desc, product_id desc` order —
/// newest first.
final List<VendorProductSummary> productCatalogueSummaries =
    <VendorProductSummary>[
      espressoSummary,
      decafSummary,
      unassignedSummary,
      retiredSummary,
    ];

/// Espresso's three assignment rows, in the backend's
/// `retailer_name, retailer_organization_id` order.
///
/// Deliberately covers, in one fixture, every case the section has to get right:
///
///   * an ACTIVE assignment to an ACTIVE Retailer with an ACTIVE relationship —
///     the ordinary row;
///   * an ACTIVE assignment to a **SUSPENDED** Retailer with a **SUSPENDED**
///     relationship — a real, reachable state that must be shown as three
///     independent facts, not collapsed;
///   * an **INACTIVE** assignment whose `vendor_retailers` row is **gone**, so
///     both `relationship_id` and `relationship_status` are null and the row is
///     visible, counted, and not cross-linkable.
final List<VendorProductAssignedRetailer>
espressoAssignments = <VendorProductAssignedRetailer>[
  VendorProductAssignedRetailer(
    relationshipId: harbourRelationshipId,
    retailerOrganizationId: harbourOrgId,
    retailerName: 'Harbour Provisions',
    // An ACTIVE assignment against a SUSPENDED Retailer and a SUSPENDED
    // relationship. Neither count is narrowed by either.
    retailerStatus: VendorRetailerStatus.suspended,
    relationshipStatus: VendorRetailerStatus.suspended,
    assignmentStatus: VendorProductAssignmentStatus.active,
    assignedAt: DateTime.utc(2026, 4, 20, 10, 0),
    assignmentUpdatedAt: DateTime.utc(2026, 4, 20, 10, 0),
  ),
  VendorProductAssignedRetailer(
    relationshipId: northwindRelationshipId,
    retailerOrganizationId: northwindOrgId,
    retailerName: 'Northwind Retail',
    retailerStatus: VendorRetailerStatus.active,
    relationshipStatus: VendorRetailerStatus.active,
    assignmentStatus: VendorProductAssignmentStatus.active,
    assignedAt: DateTime.utc(2026, 4, 19, 9, 30),
    assignmentUpdatedAt: DateTime.utc(2026, 4, 19, 9, 30),
  ),
  VendorProductAssignedRetailer(
    // The relationship row is gone. Not an error, not a parsing failure,
    // and not a reason to drop the row — `assignment_count` still counts it.
    relationshipId: null,
    retailerOrganizationId: orphanedOrgId,
    retailerName: 'Old Town Grocers',
    retailerStatus: VendorRetailerStatus.deactivated,
    relationshipStatus: null,
    assignmentStatus: VendorProductAssignmentStatus.inactive,
    assignedAt: DateTime.utc(2026, 4, 21, 8, 0),
    // For an INACTIVE row this happens to be the moment of withdrawal, but
    // the column is `updated_at` and is never labelled as a `withdrawn_at`.
    assignmentUpdatedAt: DateTime.utc(2026, 5, 30, 12, 0),
  ),
];

/// The inactive product's single, still-active assignment.
final List<VendorProductAssignedRetailer> retiredAssignments =
    <VendorProductAssignedRetailer>[
      VendorProductAssignedRetailer(
        relationshipId: northwindRelationshipId,
        retailerOrganizationId: northwindOrgId,
        retailerName: 'Northwind Retail',
        retailerStatus: VendorRetailerStatus.active,
        relationshipStatus: VendorRetailerStatus.active,
        assignmentStatus: VendorProductAssignmentStatus.active,
        assignedAt: DateTime.utc(2026, 1, 30, 9, 0),
        assignmentUpdatedAt: DateTime.utc(2026, 1, 30, 9, 0),
      ),
    ];

/// A `list_vendor_products()` body, as PostgREST returns it.
List<Map<String, Object?>> productRows() => <Map<String, Object?>>[
  productRow(),
  productRow(
    productId: decafProductUuid,
    productCode: 'DEC-2000',
    barcode: null,
    productName: 'Decaf Ground 500g',
    brand: null,
    description: null,
    activeAssignmentCount: 0,
    createdAt: '2026-03-07T11:00:00+00:00',
    updatedAt: '2026-03-07T11:00:00+00:00',
  ),
];

/// One `list_vendor_products()` row. Ten columns, and **no** `assignment_count`
/// — the list genuinely does not return one.
Map<String, Object?> productRow({
  Object? productId = espressoProductUuid,
  Object? productCode = 'ESP-1000',
  Object? barcode = '5012345678900',
  Object? productName = 'Espresso Blend 1kg',
  Object? brand = 'Harvest Roasters',
  Object? description = 'A dark roast blend for espresso machines.',
  Object? status = 'ACTIVE',
  Object? activeAssignmentCount = 2,
  Object? createdAt = '2026-04-18T09:15:00+00:00',
  Object? updatedAt = '2026-06-02T14:30:00+00:00',
}) => <String, Object?>{
  'product_id': productId,
  'product_code': productCode,
  'barcode': barcode,
  'product_name': productName,
  'brand': brand,
  'description': description,
  'status': status,
  'active_assignment_count': activeAssignmentCount,
  'created_at': createdAt,
  'updated_at': updatedAt,
};

/// One `get_vendor_product_detail(uuid)` row — the ten list columns **plus**
/// `assignment_count`.
Map<String, Object?> productDetailRow({
  Object? productId = espressoProductUuid,
  Object? productCode = 'ESP-1000',
  Object? barcode = '5012345678900',
  Object? productName = 'Espresso Blend 1kg',
  Object? brand = 'Harvest Roasters',
  Object? description = 'A dark roast blend for espresso machines.',
  Object? status = 'ACTIVE',
  Object? assignmentCount = 3,
  Object? activeAssignmentCount = 2,
  Object? createdAt = '2026-04-18T09:15:00+00:00',
  Object? updatedAt = '2026-06-02T14:30:00+00:00',
}) => <String, Object?>{
  'product_id': productId,
  'product_code': productCode,
  'barcode': barcode,
  'product_name': productName,
  'brand': brand,
  'description': description,
  'status': status,
  'assignment_count': assignmentCount,
  'active_assignment_count': activeAssignmentCount,
  'created_at': createdAt,
  'updated_at': updatedAt,
};

/// One `list_vendor_product_assigned_retailers(uuid)` row.
Map<String, Object?> assignedRetailerRow({
  Object? relationshipId = northwindRelationshipId,
  Object? retailerOrganizationId = northwindOrgId,
  Object? retailerName = 'Northwind Retail',
  Object? retailerStatus = 'ACTIVE',
  Object? relationshipStatus = 'ACTIVE',
  Object? assignmentStatus = 'ACTIVE',
  Object? assignedAt = '2026-04-19T09:30:00+00:00',
  Object? assignmentUpdatedAt = '2026-04-19T09:30:00+00:00',
}) => <String, Object?>{
  'relationship_id': relationshipId,
  'retailer_organization_id': retailerOrganizationId,
  'retailer_name': retailerName,
  'retailer_status': retailerStatus,
  'relationship_status': relationshipStatus,
  'assignment_status': assignmentStatus,
  'assigned_at': assignedAt,
  'assignment_updated_at': assignmentUpdatedAt,
};

/// A read that failed the way an unreadable body does.
ReadResult<T> unavailableProductRead<T>() =>
    ReadFailure<T>(const UnavailableFailure());

/// A read the backend refused with `42501` — which covers a caller who is not
/// signed in, is not a Vendor Super Admin, lacks `PRODUCTS_READ`, or (on the
/// assignment read alone) lacks `RETAILERS_READ`. All four are the same answer
/// here, exactly as they are in SQL.
ReadResult<T> deniedProductRead<T>() => ReadFailure<T>(const DeniedFailure());
