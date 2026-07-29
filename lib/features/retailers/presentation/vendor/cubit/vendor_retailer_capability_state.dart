part of 'vendor_retailer_capability_cubit.dart';

/// Where the capability probe has reached.
enum VendorRetailerCapabilityPhase {
  /// Nothing has been asked. The control is hidden.
  initial,

  /// `has_organization_permission` is in flight. Still hidden — a control that
  /// appeared while the answer was unknown would appear for a caller who may not
  /// use it, for as long as the request took.
  loading,

  /// The probe settled. [VendorRetailerCapabilityState.capability] says how.
  resolved,
}

/// The capability this Vendor session holds, as far as the database has said.
final class VendorRetailerCapabilityState extends Equatable {
  const VendorRetailerCapabilityState({
    this.organizationId,
    this.phase = VendorRetailerCapabilityPhase.initial,
    this.capability = VendorRetailerManageCapability.unavailable,
  });

  /// The Vendor organization the probe was made for, or null before one was.
  ///
  /// Held so a repeat probe for the same organization can be skipped, and so a
  /// session change to a *different* Vendor is guaranteed to re-ask rather than
  /// reuse an answer about somebody else's organization.
  final String? organizationId;

  final VendorRetailerCapabilityPhase phase;

  /// The database's answer.
  ///
  /// Defaults to [VendorRetailerManageCapability.unavailable] rather than
  /// `denied`, because before the probe has run this client genuinely does not
  /// know — and asserting a definite denial it has no grounds for would be a
  /// claim about the caller. Both hide the control either way.
  final VendorRetailerManageCapability capability;

  /// Whether the lifecycle control may be rendered.
  ///
  /// **Both** conditions, positively: the probe has settled, and its answer is
  /// exactly `confirmed`. Neither is expressed as an exclusion, so a member
  /// added to either enum is hidden by default rather than falling through into
  /// a rendered control.
  bool get isConfirmed =>
      phase == VendorRetailerCapabilityPhase.resolved && capability.isConfirmed;

  VendorRetailerCapabilityState copyWith({
    String? organizationId,
    VendorRetailerCapabilityPhase? phase,
    VendorRetailerManageCapability? capability,
  }) {
    return VendorRetailerCapabilityState(
      organizationId: organizationId ?? this.organizationId,
      phase: phase ?? this.phase,
      capability: capability ?? this.capability,
    );
  }

  @override
  List<Object?> get props => <Object?>[organizationId, phase, capability];
}
