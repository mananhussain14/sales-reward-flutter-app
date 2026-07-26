import 'package:flutter/material.dart';

import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_audit_log_entry.dart';
import 'vendor_audit_log_copy.dart';
import 'vendor_audit_log_labels.dart';

/// The pill that names — or honestly declines to name — an event's actor.
///
/// A pill rather than a plain line because the actor is the single most
/// consequential fact on an audit row and the three states must be
/// distinguishable at a glance. The distinction is carried by the **wording**
/// first and by an icon second; the tint only marks the attributed state and
/// never encodes an outcome, because an audit row records no outcome.
///
/// ## The three states, and why none of them may be simplified
///
/// * A named person — resolved through a membership of *this* Vendor, which is
///   the whole reason a name may be shown at all.
/// * *"Unknown actor"* — an actor id is on the row but resolves to no membership
///   here. It may belong to another Vendor, so nothing further is said.
/// * *"System or unavailable actor"* — no actor identity remains. Never rendered
///   as a bare "System": an event born without an actor and an event whose actor
///   was deleted produce byte-identical rows, so a confident "System" would
///   assert something the schema cannot support.
///
/// A fourth, neutral state exists for an actor type this build does not know, so
/// a newer backend cannot make a row disappear or be misattributed.
class VendorAuditActorBadge extends StatelessWidget {
  const VendorAuditActorBadge({super.key, required this.entry});

  final VendorAuditLogEntry entry;

  /// What this badge is spoken as.
  ///
  /// Prefixed with the field name, so a listener hears *"Recorded actor: System
  /// or unavailable actor"* rather than a bare phrase whose subject they have to
  /// infer from position.
  static String semanticsFor(VendorAuditLogEntry entry) =>
      '${VendorAuditLogCopy.actorLabel}: '
      '${VendorAuditLogLabels.actorLabel(entry)}';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsFor(entry),
      excludeSemantics: true,
      child: SrBadge(
        label: VendorAuditLogLabels.actorLabel(entry),
        tone: VendorAuditLogLabels.actorTone(entry.actorType),
        icon: VendorAuditLogLabels.actorIcon(entry.actorType),
      ),
    );
  }
}
