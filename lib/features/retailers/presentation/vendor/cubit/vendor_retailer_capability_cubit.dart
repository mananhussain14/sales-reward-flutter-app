import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/vendor_retailer_manage_capability.dart';
import '../../../domain/repositories/vendor_retailer_lifecycle_repository.dart';

part 'vendor_retailer_capability_state.dart';

/// Asks the database, once per Vendor session, whether this caller holds
/// `RETAILERS_MANAGE`.
///
/// ## The organization id is the session's, and only the session's
///
/// [load] takes the Vendor organization id, and the Vendor shell supplies it
/// from `PortalContext.vendor.organizationId` — a value the backend produced
/// from `auth.uid()` in `get_my_portal_context()`. It never comes from a route
/// parameter, a form field, local storage, or a Retailer record: a Retailer
/// organization id would be the wrong tenant entirely, and the probe would be
/// asking whether this Vendor holds a permission inside somebody else's company.
///
/// ## Nothing is persisted, and nothing is cached across sessions
///
/// The answer describes a role mapping an administrator can change at any
/// moment. It lives in memory for the life of this shell and is dropped by
/// [clear] the instant the signed-in person changes — there is no on-device
/// preference store, no disk write and no memo anywhere on this path, by
/// design. A stale `confirmed` influencing a later session is precisely the
/// failure this avoids.
///
/// ## It fails closed in every direction
///
/// Before the answer arrives, on a definite denial, on an unreadable answer and
/// on a transport failure alike, [VendorRetailerCapabilityState.isConfirmed] is
/// false and the control is hidden. `denied` and `unavailable` are still kept
/// apart in the state — only one of them is a fact about the caller — but they
/// produce the same interface, because the only safe response to not knowing is
/// to offer nothing.
///
/// ## This is presentation, never authority
///
/// A `confirmed` here permits a control to *render*.
/// `public.set_vendor_retailer_status()` re-derives the acting Vendor from
/// `auth.uid()` and re-proves the permission under its own row locks on every
/// call, whatever this cubit decided.
final class VendorRetailerCapabilityCubit
    extends Cubit<VendorRetailerCapabilityState> {
  VendorRetailerCapabilityCubit(this._repository)
    : super(const VendorRetailerCapabilityState());

  final VendorRetailerLifecycleRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a probe
  /// already in flight for the previous Vendor cannot resolve into the next
  /// one's state — which is the one way a `confirmed` could otherwise cross a
  /// session boundary.
  int _token = 0;

  /// Probes `RETAILERS_MANAGE` for [vendorOrganizationId].
  ///
  /// Idempotent for the organization it is already answering or has answered, so
  /// a widget rebuild, a router refresh or a second entry into the Retailer
  /// detail issues no second request. A *different* organization always starts a
  /// fresh probe, and so does the same one after [clear].
  Future<void> load(String vendorOrganizationId) async {
    if (state.organizationId == vendorOrganizationId &&
        state.phase != VendorRetailerCapabilityPhase.initial) {
      return;
    }

    final int token = ++_token;
    emit(
      VendorRetailerCapabilityState(
        organizationId: vendorOrganizationId,
        phase: VendorRetailerCapabilityPhase.loading,
      ),
    );

    final VendorRetailerManageCapability capability = await _repository
        .manageCapability(vendorOrganizationId);

    if (isClosed || token != _token) {
      return;
    }

    emit(
      state.copyWith(
        phase: VendorRetailerCapabilityPhase.resolved,
        capability: capability,
      ),
    );
  }

  /// Drops the resolved capability.
  ///
  /// Called when the signed-in person changes. The token is advanced first, so a
  /// probe already in flight for the previous identity is dropped on arrival
  /// rather than confirming a capability for whoever replaced them.
  void clear() {
    _token++;
    emit(const VendorRetailerCapabilityState());
  }
}
