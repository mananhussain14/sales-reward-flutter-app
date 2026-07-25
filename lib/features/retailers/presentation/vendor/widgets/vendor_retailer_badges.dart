import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/retailer_owner_state.dart';
import '../../../domain/entities/vendor_retailer_status.dart';

/// A lifecycle status, as a pill.
///
/// Wraps the design system's [SrBadge] rather than [SrStatusBadge] for one
/// reason: this screen shows **three** statuses that share a vocabulary
/// (relationship, Retailer, shop), and a bare "Active" pill three times over
/// tells a reader nothing about which is which. [prefix] puts the subject in the
/// label — "Relationship: Active" — so the meaning survives without the reader
/// having to infer it from position.
///
/// ## Colour is never the message
///
/// Every state carries its own word, and the two that matter most carry an icon
/// as well. A user who cannot distinguish amber from emerald reads exactly the
/// same facts.
///
/// ## An unknown token is neutral, and grants nothing
///
/// [VendorRetailerStatus.unknown] renders "Unknown" in the slate tone. The raw
/// backend token is never shown — a future status must not leak a database
/// literal into the interface — and because the enum's `isActive` tests `active`
/// positively, nothing downstream can mistake it for a working relationship.
class VendorRetailerStatusBadge extends StatelessWidget {
  const VendorRetailerStatusBadge({
    super.key,
    required this.status,
    this.prefix,
  });

  final VendorRetailerStatus status;

  /// The subject this status belongs to — "Relationship", "Retailer", "Shop".
  final String? prefix;

  /// The label this widget renders for [status], without the prefix. Exposed so
  /// a test can assert the mapping without building four widgets.
  static String labelFor(VendorRetailerStatus status) => switch (status) {
    VendorRetailerStatus.active => 'Active',
    VendorRetailerStatus.suspended => 'Suspended',
    VendorRetailerStatus.deactivated => 'Deactivated',
    VendorRetailerStatus.unknown => 'Unknown',
  };

  static SrTone _toneFor(VendorRetailerStatus status) => switch (status) {
    VendorRetailerStatus.active => SrTone.emerald,
    VendorRetailerStatus.suspended => SrTone.amber,
    VendorRetailerStatus.deactivated => SrTone.slate,
    VendorRetailerStatus.unknown => SrTone.slate,
  };

  static IconData? _iconFor(VendorRetailerStatus status) => switch (status) {
    VendorRetailerStatus.active => Icons.check_rounded,
    VendorRetailerStatus.suspended => Icons.pause_rounded,
    VendorRetailerStatus.deactivated => Icons.block_rounded,
    VendorRetailerStatus.unknown => Icons.help_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final String label = labelFor(status);
    return SrBadge(
      label: prefix == null ? label : '$prefix: $label',
      tone: _toneFor(status),
      icon: _iconFor(status),
    );
  }
}

/// A Retailer's owner state, as a pill.
///
/// Five states plus an unknown fallback, worded for a Vendor rather than
/// transcribed from the database: `DELIVERY_FAILED` is a fact about an
/// invitation this milestone does not show, so it reads "Invite not delivered"
/// rather than leaking the token.
///
/// ## No personal data reaches this widget
///
/// The deployed reads return the state word alone — no recipient name, email or
/// timestamp, and no invitation id, token, hash or failure code. There is
/// nothing here to render even if a screen asked for it.
///
/// ## Unknown never reads as done
///
/// [RetailerOwnerState.unknown] renders "Unknown", slate, with a question glyph.
/// It is not "Owner active", and it enables nothing — this milestone offers no
/// owner action to enable.
class RetailerOwnerStateBadge extends StatelessWidget {
  const RetailerOwnerStateBadge({super.key, required this.ownerState});

  final RetailerOwnerState ownerState;

  /// The label for [state]. Exposed so a test can assert all six at once.
  static String labelFor(RetailerOwnerState state) => switch (state) {
    RetailerOwnerState.active => 'Owner active',
    RetailerOwnerState.pending => 'Invite pending',
    RetailerOwnerState.deliveryFailed => 'Invite not delivered',
    RetailerOwnerState.expired => 'Invite expired',
    RetailerOwnerState.none => 'No owner',
    RetailerOwnerState.unknown => 'Owner state unknown',
  };

  static SrTone _toneFor(RetailerOwnerState state) => switch (state) {
    RetailerOwnerState.active => SrTone.emerald,
    RetailerOwnerState.pending => SrTone.amber,
    RetailerOwnerState.deliveryFailed => SrTone.red,
    RetailerOwnerState.expired => SrTone.amber,
    RetailerOwnerState.none => SrTone.slate,
    RetailerOwnerState.unknown => SrTone.slate,
  };

  static IconData _iconFor(RetailerOwnerState state) => switch (state) {
    RetailerOwnerState.active => Icons.person_rounded,
    RetailerOwnerState.pending => Icons.schedule_rounded,
    RetailerOwnerState.deliveryFailed => Icons.mark_email_unread_outlined,
    RetailerOwnerState.expired => Icons.history_rounded,
    RetailerOwnerState.none => Icons.person_off_outlined,
    RetailerOwnerState.unknown => Icons.help_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return SrBadge(
      label: labelFor(ownerState),
      tone: _toneFor(ownerState),
      icon: _iconFor(ownerState),
    );
  }
}
