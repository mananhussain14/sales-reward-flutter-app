import 'package:equatable/equatable.dart';

import 'vendor_retailer_lifecycle_status.dart';
import 'vendor_retailer_status.dart';

/// What the lifecycle control may offer for one **current** pair of statuses.
///
/// Pure: no I/O, no Supabase, no Flutter. Every rule below is decided again,
/// independently, by `public.set_vendor_retailer_status()` under the caller's
/// own token — which derives the acting Vendor from `auth.uid()` through
/// `get_vendor_super_admin_context()`, requires `RETAILERS_MANAGE` through
/// `has_organization_permission()`, matches the relationship on **both** its own
/// id and that derived Vendor, locks both rows in a fixed order, requires the
/// organization to be a `RETAILER`, refuses a Retailer any other Vendor still
/// holds a live relationship with, and refuses any current pair that is not
/// exactly `ACTIVE`/`ACTIVE` or `SUSPENDED`/`SUSPENDED`.
///
/// This type exists so a control that could only ever be refused is never
/// rendered — **not** so the client can be trusted.
///
/// ## Three values, one table, so they cannot drift
///
/// [displayLabel] is the word for the current state, [actionLabel] is the verb
/// offered, and [requestedStatus] is the **only** place in this application a
/// value destined for `p_status` is produced. Keeping all three in one table is
/// what makes it impossible for the button to say "Deactivate Retailer" while
/// the request asks for `ACTIVE`.
///
/// The requested status is emphatically **not** derived from the button's text.
final class VendorRetailerLifecycleAction extends Equatable {
  const VendorRetailerLifecycleAction._({
    required this.currentStatus,
    required this.displayLabel,
    required this.actionLabel,
    required this.requestedStatus,
  });

  /// The status both rows currently hold — by definition the same value on
  /// both, because that is what [forPair] proves before it reaches this type.
  final VendorRetailerLifecycleStatus currentStatus;

  /// The user-facing word for [currentStatus]. `Active` or `Inactive`, never
  /// `Suspended` and never a raw backend token.
  final String displayLabel;

  /// The verb offered. `Deactivate Retailer` or `Reactivate Retailer`.
  final String actionLabel;

  /// The stored value that will be sent as `p_status`. Never a display word.
  final VendorRetailerLifecycleStatus requestedStatus;

  /// Whether this action deactivates. Used to choose copy and an icon, never to
  /// derive the requested status.
  bool get isDeactivation =>
      requestedStatus == VendorRetailerLifecycleStatus.suspended;

  /// The two supported pairs, and what each offers.
  ///
  /// Keyed by the **shared** status, because a supported pair is by definition
  /// one where both rows hold the same value.
  static const Map<VendorRetailerLifecycleStatus, VendorRetailerLifecycleAction>
  _transitions = <VendorRetailerLifecycleStatus, VendorRetailerLifecycleAction>{
    VendorRetailerLifecycleStatus.active: VendorRetailerLifecycleAction._(
      currentStatus: VendorRetailerLifecycleStatus.active,
      displayLabel: 'Active',
      actionLabel: 'Deactivate Retailer',
      requestedStatus: VendorRetailerLifecycleStatus.suspended,
    ),
    VendorRetailerLifecycleStatus.suspended: VendorRetailerLifecycleAction._(
      currentStatus: VendorRetailerLifecycleStatus.suspended,
      displayLabel: 'Inactive',
      actionLabel: 'Reactivate Retailer',
      requestedStatus: VendorRetailerLifecycleStatus.active,
    ),
  };

  /// The action offered for a current pair, or **null** when none is.
  ///
  /// ## Only two pairs qualify
  ///
  /// `ACTIVE`/`ACTIVE` and `SUSPENDED`/`SUSPENDED` — the two this operation can
  /// itself produce, and the two the RPC accepts as a starting state.
  ///
  /// ## Everything else is null, and the mismatch is the important one
  ///
  /// An `ACTIVE` relationship against a `SUSPENDED` organization, or the
  /// reverse, is a state this operation **cannot have created**. It means
  /// something wrote one of those rows outside this path. The RPC refuses it
  /// with `55000` and deliberately does not reconcile it, because quietly
  /// "repairing" it would overwrite whatever the other writer intended and erase
  /// the only evidence that a second writer exists. Offering a control the
  /// database will refuse is worse than offering nothing, so nothing is offered.
  ///
  /// A `DEACTIVATED` value on either row is null too: terminal, and not this
  /// operation's to clear. So is [VendorRetailerStatus.unknown] — which is what
  /// a token this build does not recognise degrades to, and which therefore also
  /// covers a stray `INACTIVE`, a blank status and any future value. A status
  /// this build does not know is a status it must not act on.
  ///
  /// The vocabulary test runs **before** the equality test on purpose: an
  /// unrecognised value that happened to appear on both rows would otherwise
  /// satisfy "the pair agrees" and be treated as supported.
  static VendorRetailerLifecycleAction? forPair({
    required VendorRetailerStatus retailerStatus,
    required VendorRetailerStatus relationshipStatus,
  }) {
    final VendorRetailerLifecycleStatus? retailer = _lifecycle(retailerStatus);
    if (retailer == null) {
      return null;
    }
    final VendorRetailerLifecycleStatus? relationship = _lifecycle(
      relationshipStatus,
    );
    if (relationship == null) {
      return null;
    }
    // Synchronized, or nothing. The two rows move together in one transaction,
    // so a pair that disagrees is not a state this control may act on.
    if (retailer != relationship) {
      return null;
    }
    return _transitions[retailer];
  }

  /// Narrows a **response** status to the lifecycle vocabulary, or null.
  ///
  /// Written as positive matching rather than as an exclusion list, so a future
  /// member added to [VendorRetailerStatus] is excluded by default instead of
  /// falling through into a supported pair.
  static VendorRetailerLifecycleStatus? _lifecycle(
    VendorRetailerStatus status,
  ) {
    return switch (status) {
      VendorRetailerStatus.active => VendorRetailerLifecycleStatus.active,
      VendorRetailerStatus.suspended => VendorRetailerLifecycleStatus.suspended,
      VendorRetailerStatus.deactivated => null,
      VendorRetailerStatus.unknown => null,
    };
  }

  @override
  List<Object?> get props => <Object?>[
    currentStatus,
    displayLabel,
    actionLabel,
    requestedStatus,
  ];
}
