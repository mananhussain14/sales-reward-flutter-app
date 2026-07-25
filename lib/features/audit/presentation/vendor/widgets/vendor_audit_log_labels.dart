import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../domain/entities/vendor_audit_actor_type.dart';
import '../../../domain/entities/vendor_audit_log_entry.dart';
import 'vendor_audit_log_copy.dart';

/// Backend codes → the words a reader sees.
///
/// ## Why this mapping lives here and not in SQL
///
/// `audit_logs.action` and `audit_logs.entity_type` are plain `text` with only a
/// non-empty check — no enum, no lookup table, no reference data anywhere in the
/// schema — so there is no trusted mapping for the database to return. The web's
/// own humanizer is a generic underscores-to-spaces function whose comment calls
/// itself a temporary stand-in, and promoting a placeholder into a shared
/// database contract would freeze a stop-gap into an API.
///
/// So the codes arrive raw, the entity keeps them raw, and the friendly wording
/// is a **presentation** concern that this file owns alone.
///
/// ## The rules this mapping obeys
///
/// * **Only codes proven to be written today are mapped.** Every entry below was
///   read from an `insert into public.audit_logs` in the deployed backend. None
///   is anticipated, and none is invented.
/// * **An unknown code stays visible.** It is humanized neutrally and rendered
///   in the same style as a known one, plus its raw code in subdued text so a
///   reader can at least see what was recorded. A history that hid the events its
///   reader did not recognise would be worse than useless on exactly the day it
///   mattered.
/// * **An unknown code is never guessed at.** It is never mapped to a create, an
///   update, a delete, a success or a failure, and never inferred from the entity
///   type beside it.
/// * **No label ever decides anything.** No route, no affordance, no visibility
///   and no authorization branches on any string produced here.
/// * **No outcome is asserted.** `PRODUCT_CREATED` reads "Product created"
///   because that is what the code says; nothing reads "succeeded" or "failed"
///   unless the code itself records it, which exactly one shipped code does.
abstract final class VendorAuditLogLabels {
  /// The seventeen action codes the shipped backend writes today.
  ///
  /// Read from the deployed migrations, not from documentation. Roughly a third
  /// of them are filed against a **Retailer** organization by their writers and
  /// so will not normally appear in a Vendor's own feed; they are mapped anyway
  /// because being written at all is the standard for inclusion here, and a code
  /// that did appear should not fall to the fallback for want of one line.
  static const Map<String, String> _actionLabels = <String, String>{
    // Retailer lifecycle, filed against the Vendor.
    'RETAILER_ONBOARDED': 'Retailer onboarded',
    'RETAILER_SHOP_ADDED': 'Retailer shop added',
    'RETAILER_OWNER_INVITED': 'Retailer owner invited',
    'RETAILER_OWNER_INVITATION_REVOKED': 'Retailer owner invitation revoked',
    // Filed against the Retailer organization by its writer.
    'RETAILER_OWNER_INVITATION_ACCEPTED': 'Retailer owner invitation accepted',
    // Retailer staff invitations, all filed against the Retailer organization.
    'STAFF_INVITATION_RESERVED': 'Staff invitation reserved',
    'STAFF_INVITATION_SENT': 'Staff invitation sent',
    'STAFF_INVITATION_RESENT': 'Staff invitation resent',
    'STAFF_INVITATION_REVOKED': 'Staff invitation revoked',
    // The one shipped code that records a failure. It is rendered as the code's
    // own words and is not styled as an error state: the row is a record that a
    // delivery failed, not a problem this screen is diagnosing now.
    'STAFF_INVITATION_DELIVERY_FAILED': 'Staff invitation delivery failed',
    'STAFF_INVITATION_ACCEPTED': 'Staff invitation accepted',
    // Products, filed against the Vendor.
    'PRODUCT_CREATED': 'Product created',
    'PRODUCT_UPDATED': 'Product updated',
    'PRODUCT_ACTIVATED': 'Product activated',
    'PRODUCT_DEACTIVATED': 'Product deactivated',
    'PRODUCT_ASSIGNED_TO_RETAILER': 'Product assigned to a Retailer',
    'PRODUCT_UNASSIGNED_FROM_RETAILER': 'Product unassigned from a Retailer',
  };

  /// The five entity types the backend's metadata whitelist recognises.
  ///
  /// The same five, and only these five, are the types for which an
  /// `entity_display_name` can ever arrive. Anything else falls to the neutral
  /// humanization below and carries no name — which is a fact about the
  /// contract, not a fault in the row.
  static const Map<String, String> _entityLabels = <String, String>{
    'VENDOR_PRODUCT': 'Product',
    'RETAILER_ORGANIZATION': 'Retailer',
    'RETAILER_SHOP': 'Retailer shop',
    'RETAILER_INVITATION': 'Retailer owner invitation',
    'RETAILER_STAFF_INVITATION': 'Retailer staff invitation',
  };

  /// A neutral icon per entity type.
  ///
  /// Chosen from the entity type — a fact the backend actually sent — and never
  /// from the action, so no glyph can imply that something was created, removed,
  /// succeeded or failed. Every event carries the same neutral tone for the same
  /// reason.
  static const Map<String, IconData> _entityIcons = <String, IconData>{
    'VENDOR_PRODUCT': Icons.inventory_2_outlined,
    'RETAILER_ORGANIZATION': Icons.storefront_outlined,
    'RETAILER_SHOP': Icons.store_mall_directory_outlined,
    'RETAILER_INVITATION': Icons.mail_outline_rounded,
    'RETAILER_STAFF_INVITATION': Icons.group_add_outlined,
  };

  /// Whether this build has a written label for [actionCode].
  ///
  /// Used only to decide whether to show the raw code beneath the label. It is
  /// never an authorization, navigation or visibility test — an unknown code is
  /// shown exactly as prominently as a known one.
  static bool isKnownAction(String actionCode) =>
      _actionLabels.containsKey(actionCode);

  /// The friendly label for [actionCode], or a neutral humanization of it.
  static String actionLabel(String actionCode) =>
      _actionLabels[actionCode] ?? humanizeCode(actionCode);

  /// The friendly label for [entityType], or a neutral humanization of it.
  static String entityTypeLabel(String entityType) =>
      _entityLabels[entityType] ?? humanizeCode(entityType);

  /// The neutral icon for [entityType].
  static IconData entityIcon(String entityType) =>
      _entityIcons[entityType] ?? Icons.history_rounded;

  /// `PRODUCT_STATUS_CHANGED` → `Product status changed`.
  ///
  /// The same shape as the web's generic humanizer, so an unknown code reads the
  /// same in both clients: separators become spaces, runs of whitespace collapse,
  /// the whole thing goes to lower case, and the first character is capitalised.
  ///
  /// Total by construction. A code that humanizes to nothing — all separators,
  /// or blank, neither of which the backend's non-empty check permits — falls
  /// back to a neutral phrase rather than rendering an empty line or throwing. A
  /// malformed value therefore still produces a visible, honest label.
  static String humanizeCode(String code) {
    final String words = code
        .trim()
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    if (words.isEmpty) {
      return _unlabelledCode;
    }
    return words[0].toUpperCase() + words.substring(1);
  }

  /// The label for a code with no printable characters at all. Not reachable
  /// through the deployed contract — `action` and `entity_type` both carry a
  /// non-empty check, and this client's parser rejects a blank one — but a label
  /// helper that could return an empty string is a blank line waiting to happen.
  static const String _unlabelledCode = 'Recorded activity';

  /// The wording for an event's actor.
  ///
  /// One switch, and every branch is deliberate:
  ///
  /// * [VendorAuditActorType.user] — the returned name, verbatim. It is already
  ///   the only name this caller is entitled to see: the SQL join is scoped to a
  ///   membership of the audit row's own Vendor. Nothing is appended — no id, no
  ///   email, no role — because none is returned and none exists to append.
  /// * [VendorAuditActorType.unknown] — neutral, and final.
  /// * [VendorAuditActorType.system] — the ambiguity, stated. Never a bare
  ///   "System".
  /// * [VendorAuditActorType.unrecognized] — neutral, and never folded into one
  ///   of the three above.
  ///
  /// The name is never substituted with the signed-in caller's own, and never
  /// reconstructed from anything else on the row.
  static String actorLabel(VendorAuditLogEntry entry) {
    return switch (entry.actorType) {
      // Non-null by the parser's biconditional, which is asserted on every row.
      VendorAuditActorType.user => entry.actorDisplayName!,
      VendorAuditActorType.unknown => VendorAuditLogCopy.unknownActor,
      VendorAuditActorType.system => VendorAuditLogCopy.systemActor,
      VendorAuditActorType.unrecognized => VendorAuditLogCopy.unrecognizedActor,
    };
  }

  /// The icon beside the actor wording.
  ///
  /// Meaning is never carried by the glyph alone — the wording is always present
  /// — but the three states are visually distinguishable so a scanning reader is
  /// not made to read every line to spot the attributed ones.
  static IconData actorIcon(VendorAuditActorType type) {
    return switch (type) {
      VendorAuditActorType.user => Icons.person_outline_rounded,
      VendorAuditActorType.unknown => Icons.help_outline_rounded,
      // "No actor identity remains" — deliberately not a gear, a robot or
      // anything else that would picture an automated process acting.
      VendorAuditActorType.system => Icons.no_accounts_outlined,
      VendorAuditActorType.unrecognized => Icons.help_outline_rounded,
    };
  }

  /// The tone of the actor pill.
  ///
  /// Only the attributed state is tinted, and the tint says "a person is named
  /// here" rather than "this is good". Every other state is neutral slate, and
  /// no tone anywhere in this feature encodes success, failure or severity —
  /// there is no such fact on an audit row to encode.
  static SrTone actorTone(VendorAuditActorType type) =>
      type == VendorAuditActorType.user ? SrTone.indigo : SrTone.slate;

  /// The affected thing, as one line.
  ///
  /// With a name: `Product · Espresso Blend 1kg`. Without one: the type alone.
  /// The name is the **historical snapshot** stored at the moment of the event,
  /// so it is what the thing was called then — not what it is called now, and
  /// not evidence that it still exists.
  ///
  /// Null is never repaired. No id is shown in its place, no live lookup is
  /// performed, and no name is reconstructed from another field.
  static String entityLine(VendorAuditLogEntry entry) {
    final String type = entityTypeLabel(entry.entityType);
    final String? name = entry.entityDisplayName;
    return name == null ? type : '$type · $name';
  }

  /// The affected thing as a sentence, for assistive technology.
  ///
  /// States the absence explicitly rather than skipping it, so a listener can
  /// tell "this event's target has no recorded name" from "the name was not read
  /// out".
  static String entitySemantics(VendorAuditLogEntry entry) {
    final String type = entityTypeLabel(entry.entityType);
    final String name =
        entry.entityDisplayName ?? VendorAuditLogCopy.entityNameUnavailable;
    return '${VendorAuditLogCopy.entityLabel}: $type. $name';
  }
}
