import 'dart:async';

import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_lifecycle_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_manage_capability.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_lifecycle_repository.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_write_result.dart';

/// A hand-written [VendorRetailerLifecycleRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *what was
/// sent* as much as what came back: [writes] records every relationship id and
/// requested status that left the client, and [capabilityOrganizationIds]
/// records which organization the permission probe was pointed at — which is how
/// a test proves the id came from the session's Vendor context and not from a
/// Retailer record.
class FakeVendorRetailerLifecycleRepository
    implements VendorRetailerLifecycleRepository {
  /// Every lifecycle write, in order.
  final List<({String relationshipId, VendorRetailerLifecycleStatus status})>
  writes = <({String relationshipId, VendorRetailerLifecycleStatus status})>[];

  /// Every organization id the capability probe was asked about, in order.
  final List<String> capabilityOrganizationIds = <String>[];

  int get writeCallCount => writes.length;
  int get capabilityCallCount => capabilityOrganizationIds.length;

  /// The answer every write produces. Defaults to a committed deactivation.
  VendorRetailerWriteResult writeResult = const VendorRetailerWriteSuccess(
    confirmedStatus: VendorRetailerLifecycleStatus.suspended,
    statusChanged: true,
  );

  /// The answer every probe produces.
  VendorRetailerManageCapability capabilityResult =
      VendorRetailerManageCapability.confirmed;

  /// When true, every write stays pending until [completeWrite] is called — so
  /// "a second confirmation while one is in flight" is deterministic rather than
  /// a sleep-and-hope.
  bool manualWrite = false;
  final List<Completer<VendorRetailerWriteResult>> _pendingWrites =
      <Completer<VendorRetailerWriteResult>>[];

  int get pendingWriteCount => _pendingWrites.length;

  void completeWrite([VendorRetailerWriteResult? override]) {
    _pendingWrites.removeAt(0).complete(override ?? writeResult);
  }

  /// The same control for the capability probe, so a test can assert that the
  /// control stays hidden while the answer is unknown.
  bool manualCapability = false;
  final List<Completer<VendorRetailerManageCapability>> _pendingCapability =
      <Completer<VendorRetailerManageCapability>>[];

  int get pendingCapabilityCount => _pendingCapability.length;

  void completeCapability([VendorRetailerManageCapability? override]) {
    _pendingCapability.removeAt(0).complete(override ?? capabilityResult);
  }

  @override
  Future<VendorRetailerWriteResult> setRetailerStatus({
    required String relationshipId,
    required VendorRetailerLifecycleStatus status,
  }) {
    writes.add((relationshipId: relationshipId, status: status));
    if (manualWrite) {
      final Completer<VendorRetailerWriteResult> completer =
          Completer<VendorRetailerWriteResult>();
      _pendingWrites.add(completer);
      return completer.future;
    }
    return Future<VendorRetailerWriteResult>.value(writeResult);
  }

  @override
  Future<VendorRetailerManageCapability> manageCapability(
    String vendorOrganizationId,
  ) {
    capabilityOrganizationIds.add(vendorOrganizationId);
    if (manualCapability) {
      final Completer<VendorRetailerManageCapability> completer =
          Completer<VendorRetailerManageCapability>();
      _pendingCapability.add(completer);
      return completer.future;
    }
    return Future<VendorRetailerManageCapability>.value(capabilityResult);
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A `set_vendor_retailer_status` body, as PostgREST returns a
/// `returns table (...)` function: a list of one row object.
List<Map<String, Object?>> lifecycleRows({
  Object? relationshipId,
  Object? retailerStatus = 'SUSPENDED',
  Object? relationshipStatus = 'SUSPENDED',
  Object? statusChanged = true,
}) => <Map<String, Object?>>[
  lifecycleRow(
    relationshipId: relationshipId,
    retailerStatus: retailerStatus,
    relationshipStatus: relationshipStatus,
    statusChanged: statusChanged,
  ),
];

Map<String, Object?> lifecycleRow({
  Object? relationshipId,
  Object? retailerStatus = 'SUSPENDED',
  Object? relationshipStatus = 'SUSPENDED',
  Object? statusChanged = true,
}) => <String, Object?>{
  'relationship_id': relationshipId,
  'retailer_status': retailerStatus,
  'relationship_status': relationshipStatus,
  'status_changed': statusChanged,
};

/// A write the backend refused with [failure].
VendorRetailerWriteResult refusedLifecycleWrite(Failure failure) =>
    VendorRetailerWriteFailure(failure);
