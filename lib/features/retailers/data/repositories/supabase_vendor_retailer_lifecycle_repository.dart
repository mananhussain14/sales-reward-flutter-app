import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/errors/sql_state.dart';
import '../../domain/entities/vendor_retailer_lifecycle_status.dart';
import '../../domain/entities/vendor_retailer_manage_capability.dart';
import '../../domain/repositories/vendor_retailer_lifecycle_repository.dart';
import '../../domain/repositories/vendor_retailer_write_result.dart';
import '../datasources/vendor_retailer_capability_rpc_data_source.dart';
import '../datasources/vendor_retailer_lifecycle_rpc_data_source.dart';
import '../models/vendor_retailer_lifecycle_parser.dart';

/// Classifies a thrown Retailer lifecycle error.
///
/// Delegates the whole decision to [mapSupabaseError] — the one place in the
/// application that inspects a backend error object — and adds exactly one thing
/// on top: `22P02`.
///
/// ## Why `22P02` is mapped here and not in the central mapper
///
/// `SqlState.invalidTextRepresentation` is a value PostgreSQL's **type system**
/// raises while parsing an argument, before any function body runs. For this
/// write it can only mean the client sent something that is not shaped like a
/// UUID, which is a defect in the request that retrying cannot fix — so
/// [InvalidFailure] is right, and `UnavailableFailure`'s "check your connection
/// and try again" would send somebody to fix a connection that is working.
///
/// **The blast radius of moving it centrally is why it stays local.**
/// `mapSupabaseError` is shared by every Vendor read (Retailers, Users, Roles,
/// Products, Audit, Dashboard, Profile) and by the Product writes. Those callers
/// currently fold `22P02` into `UnavailableFailure`, and several of them guard
/// against it *before* the request leaves the device — the Retailer reads answer
/// a malformed id with the same zero-row result the backend gives, deliberately,
/// so a mistyped URL is not distinguishable from a foreign id. Changing the
/// central mapping would alter the copy and the retry affordance on all of those
/// screens for a case none of them was written or tested against. That is a
/// change worth making deliberately, with its own tests, and not as a side
/// effect of this milestone.
///
/// So the override is confined to these four lines, and everything else is
/// returned exactly as [mapSupabaseError] classified it: `42501` →
/// [DeniedFailure], `23514` → [InvalidFailure], `55000` → [NotReadyFailure], an
/// `AuthException` → [UnauthenticatedFailure], and anything else — including
/// every transport fault — → [UnavailableFailure].
///
/// **No message is ever read**, for display or for discrimination. Only the
/// SQLSTATE.
Failure mapVendorRetailerLifecycleError(Object error) {
  if (error is PostgrestException &&
      error.code == SqlState.invalidTextRepresentation) {
    return const InvalidFailure();
  }
  return mapSupabaseError(error);
}

/// The real [VendorRetailerLifecycleRepository].
///
/// ## It reproduces no backend authorization logic
///
/// There is no join over `vendor_retailers` or `organizations` here, no Vendor
/// organization id in the write path, no role comparison and no permission
/// evaluation. Whether this caller may change a Retailer's status is decided in
/// SQL, on every call, by `get_vendor_super_admin_context()` and
/// `has_organization_permission(…, 'RETAILERS_MANAGE')` — under row locks this
/// client cannot take and against a Vendor it cannot name. Restating any of it
/// would create a second definition free to drift, and only one of the two could
/// be right.
///
/// ## The four refusals `55000` covers are deliberately indistinguishable
///
/// An inconsistent pair, a `DEACTIVATED` row, **another Vendor still holding a
/// live relationship with this Retailer**, and a compare-and-set row-count drift
/// all arrive as one [NotReadyFailure] with one wording. That is not laziness:
/// the multi-Vendor case must not disclose that another tenant exists, and a
/// client that told the four apart would hand back exactly the oracle the
/// backend's single message exists to deny.
final class SupabaseVendorRetailerLifecycleRepository
    implements VendorRetailerLifecycleRepository {
  const SupabaseVendorRetailerLifecycleRepository({
    required VendorRetailerLifecycleRpcDataSource rpc,
    required VendorRetailerCapabilityRpcDataSource capability,
  }) : _rpc = rpc,
       _capability = capability;

  final VendorRetailerLifecycleRpcDataSource _rpc;
  final VendorRetailerCapabilityRpcDataSource _capability;

  @override
  Future<VendorRetailerWriteResult> setRetailerStatus({
    required String relationshipId,
    required VendorRetailerLifecycleStatus status,
  }) async {
    final Object? raw;
    try {
      // Exactly one call. There is no retry here and no loop around it: an
      // automatic second attempt after a committed write is indistinguishable,
      // from this side, from one after a failed write.
      raw = await _rpc.setRetailerStatus(
        relationshipId: relationshipId,
        status: status.code,
      );
    } on Object catch (error) {
      // Every deployed refusal raises, and a raise rolls the function back — no
      // status change on either row and no audit row. So this branch is the one
      // place it is safe to say nothing happened.
      return VendorRetailerWriteFailure(mapVendorRetailerLifecycleError(error));
    }

    // Nothing was thrown, so the transaction committed. From here on the only
    // question is whether this build can describe what it did.
    final VendorRetailerLifecycleRow? row = parseVendorRetailerLifecycleRow(
      raw,
      relationshipId,
    );

    if (row == null) {
      // Committed, undescribable. Never a failure, never "unchanged", and never
      // retried. The caller re-reads the canonical detail instead.
      return const VendorRetailerWriteUnconfirmed();
    }

    return VendorRetailerWriteSuccess(
      // The database's answer, not the request. The two agree on the ordinary
      // path; stating the database's is what keeps this honest when they do not.
      confirmedStatus: row.confirmedStatus,
      statusChanged: row.statusChanged,
    );
  }

  @override
  Future<VendorRetailerManageCapability> manageCapability(
    String vendorOrganizationId,
  ) async {
    final Object? raw;
    try {
      raw = await _capability.hasRetailersManage(vendorOrganizationId);
    } on Object {
      // Deliberately not classified. There is no refusal to tell apart here —
      // the helper returns a boolean or it fails — and a page that cannot ask
      // the question gains nothing from knowing why. The thrown value is not
      // bound, inspected or logged: it can carry request URLs, headers or token
      // material.
      return VendorRetailerManageCapability.unavailable;
    }

    // A non-boolean is treated as unavailable rather than coerced. Reading a
    // null, a string or a number as `false` would assert a definite denial this
    // client has no grounds for — and `denied` and `unavailable` mean different
    // things even though both hide the control.
    if (raw is! bool) {
      return VendorRetailerManageCapability.unavailable;
    }

    return raw
        ? VendorRetailerManageCapability.confirmed
        : VendorRetailerManageCapability.denied;
  }
}
