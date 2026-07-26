import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_audit_log_entry.dart';
import 'vendor_audit_actor_badge.dart';
import 'vendor_audit_log_copy.dart';
import 'vendor_audit_log_formatting.dart';
import 'vendor_audit_log_labels.dart';

/// One recorded event in the feed.
///
/// ## It is not tappable, and it does not pretend to be
///
/// There is no chevron, no press treatment and no "view details" affordance,
/// because there is nowhere to go. No audit detail read exists — the web exposes
/// no detail surface to share, and the only thing one could add over this line is
/// exactly what the contract withholds — and no entity or actor navigation is
/// offered either: `entity_id` and `actor_profile_id` are deliberately not
/// returned, so this card holds no address for anything. A disabled affordance
/// would advertise a capability that has not been built.
///
/// ## Four facts, and no fifth inferred from them
///
/// The action, the actor, the affected item and the moment. Nothing here says an
/// action succeeded or failed, nothing states the affected item's current status,
/// and nothing claims the item still exists — the name is a snapshot taken when
/// the event was recorded.
///
/// ## The raw code, and when it earns its place
///
/// A recognised action shows its label alone. An **unrecognised** one shows the
/// label the neutral humanizer produced *and*, beneath it in subdued monospace,
/// the exact stored code — because a reader meeting an unfamiliar event is
/// precisely the reader who needs to know what was actually recorded. A known
/// code never shows it: it would be noise, and a uuid or an internal identifier
/// is never shown at all.
class VendorAuditLogTile extends StatelessWidget {
  const VendorAuditLogTile({super.key, required this.entry});

  final VendorAuditLogEntry entry;

  /// Above this width the timestamp moves to its own right-hand column and the
  /// events align down the page; below it everything stacks.
  static const double _wideThreshold = 520;

  /// The one spoken sentence this card presents.
  ///
  /// Everything visible, in the order it is read, so a screen reader user is not
  /// made to walk a pill and three lines to learn the same thing. It names no
  /// uuid: the audit log id is an address, not a fact about the event.
  static String semanticsFor(VendorAuditLogEntry entry) =>
      '${VendorAuditLogLabels.actionLabel(entry.actionCode)}. '
      '${VendorAuditActorBadge.semanticsFor(entry)}. '
      '${VendorAuditLogLabels.entitySemantics(entry)}. '
      '${VendorAuditLogCopy.occurredLabel}: '
      '${formatAuditTimestamp(entry.occurredAt)}.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsFor(entry),
      excludeSemantics: true,
      child: SrCard(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= _wideThreshold;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SrIconDisc(
                  icon: VendorAuditLogLabels.entityIcon(entry.entityType),
                  // One neutral tone for every event. A tinted glyph would be
                  // read as severity, and an audit row carries none.
                  tone: SrTone.slate,
                  size: 40,
                ),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: _Body(entry: entry, showTimestamp: !wide),
                ),
                if (wide) ...<Widget>[
                  const SizedBox(width: SrSpacing.lg),
                  _Timestamp(entry: entry, alignEnd: true),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.entry, required this.showTimestamp});

  final VendorAuditLogEntry entry;
  final bool showTimestamp;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool knownAction = VendorAuditLogLabels.isKnownAction(
      entry.actionCode,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          VendorAuditLogLabels.actionLabel(entry.actionCode),
          style: SrTypography.cardTitle.copyWith(color: sr.foreground),
          // Wraps rather than being cut at the first overflow, so a long
          // humanized code stays legible at large text scale.
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        if (!knownAction) ...<Widget>[
          const SizedBox(height: SrSpacing.xs),
          _RawActionCode(actionCode: entry.actionCode),
        ],
        const SizedBox(height: SrSpacing.md),
        // Wrap rather than Row: the pill must run onto its own line on a 360px
        // phone at large text scale instead of overflowing.
        Wrap(
          spacing: SrSpacing.sm,
          runSpacing: SrSpacing.sm,
          children: <Widget>[VendorAuditActorBadge(entry: entry)],
        ),
        const SizedBox(height: SrSpacing.md),
        _EntityLine(entry: entry),
        if (showTimestamp) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          _Timestamp(entry: entry, alignEnd: false),
        ],
      ],
    );
  }
}

/// The exact stored action code, shown only where it helps.
///
/// Subdued, monospaced and explicitly labelled, so it reads as a developer-facing
/// detail rather than as the name of the event. It is the *action* code and
/// nothing else — never an id, never a table or function name, never a SQLSTATE
/// and never a fragment of metadata.
class _RawActionCode extends StatelessWidget {
  const _RawActionCode({required this.actionCode});

  final String actionCode;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Text(
      '${VendorAuditLogCopy.unknownActionNote}: $actionCode',
      style: SrTypography.caption.copyWith(
        color: sr.textMuted,
        // The same tabular treatment the product identifier lines use, so a
        // machine token is visibly a token rather than prose.
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The affected item: its type, and its historical name when one was recorded.
class _EntityLine extends StatelessWidget {
  const _EntityLine({required this.entry});

  final VendorAuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    // A missing name is a real state, not a fault, so it is muted rather than
    // warned about — and it is still *said*, never left blank.
    final Color color = entry.hasEntityDisplayName
        ? sr.textSecondary
        : sr.textMuted;
    final String line = entry.hasEntityDisplayName
        ? VendorAuditLogLabels.entityLine(entry)
        : '${VendorAuditLogLabels.entityTypeLabel(entry.entityType)} · '
              '${VendorAuditLogCopy.entityNameUnavailable}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: SrSpacing.xxs),
          child: Icon(Icons.subject_rounded, size: 14, color: color),
        ),
        const SizedBox(width: SrSpacing.xs),
        Expanded(
          child: Text(line, style: SrTypography.caption.copyWith(color: color)),
        ),
      ],
    );
  }
}

class _Timestamp extends StatelessWidget {
  const _Timestamp({required this.entry, required this.alignEnd});

  final VendorAuditLogEntry entry;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Text(
      formatAuditTimestamp(entry.occurredAt),
      style: SrTypography.caption.copyWith(color: sr.textMuted),
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
    );
  }
}

/// The day heading above the first event of each local calendar day.
///
/// Grouping is computed from `occurred_at` alone, converted to the reader's own
/// zone — the same conversion the timestamps beside each event use, so a heading
/// can never disagree with the lines beneath it.
class VendorAuditLogDayHeading extends StatelessWidget {
  const VendorAuditLogDayHeading({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final String label = formatAuditDate(day);

    return Semantics(
      header: true,
      label: label,
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: SrTypography.caption.copyWith(
              color: sr.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: SrSpacing.md),
          Expanded(child: Divider(height: 1, color: sr.border)),
        ],
      ),
    );
  }
}
