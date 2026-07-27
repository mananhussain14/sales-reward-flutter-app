import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';

/// One labelled fact about the organization.
///
/// [value] is already a display string — a name, an ISO code, or a status
/// *label*. A status enum's raw backend token never reaches this widget, and
/// neither does any identifier: the contract returns no UUID, so there is none
/// to render.
@immutable
final class RetailerOverviewFact {
  const RetailerOverviewFact({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
    this.isMuted = false,
  });

  final String label;

  /// The display value. Never a raw backend token and never an identifier.
  final String value;

  final IconData icon;

  /// Set only where the value is a status, so it renders as a badge. Null means
  /// plain text.
  final SrTone? tone;

  /// Whether the value is a stand-in for something the backend did not record
  /// ("Not recorded"), rather than a value it did.
  ///
  /// Rendered in the muted colour so an absent value cannot be misread as a
  /// recorded one — the non-colour channel being the word itself.
  final bool isMuted;
}

/// The organization facts, laid out responsively.
///
/// ## Responsiveness
///
/// One column on a phone and two from [SrSpacing.breakpointSm] upward, so a
/// narrow Android viewport stacks the rows and a browser fills the width without
/// stretching a two-word value across it. The same widget serves both — there is
/// no separate mobile page to drift from the web one.
///
/// ## Accessibility
///
/// Each fact is a single semantics node reading "label: value", so a screen
/// reader announces one sentence rather than two disconnected fragments. Status
/// values are announced by their **label** ("Active"), never by a colour, and the
/// badge's own visual tree is excluded so nothing is read twice.
class RetailerOverviewDetailGrid extends StatelessWidget {
  const RetailerOverviewDetailGrid({super.key, required this.facts});

  final List<RetailerOverviewFact> facts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth >= SrSpacing.breakpointSm;
        final int columns = isWide ? 2 : 1;

        return Wrap(
          spacing: SrSpacing.lg,
          runSpacing: SrSpacing.lg,
          children: <Widget>[
            for (final RetailerOverviewFact fact in facts)
              SizedBox(
                width: columns == 1
                    ? constraints.maxWidth
                    // The gutter is shared between the two columns, so each
                    // gives up half of it. Without this the second column wraps
                    // at exactly the breakpoint.
                    : (constraints.maxWidth - SrSpacing.lg) / 2,
                child: _FactTile(fact: fact),
              ),
          ],
        );
      },
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.fact});

  final RetailerOverviewFact fact;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final SrTone? tone = fact.tone;

    return Semantics(
      // One sentence, so the label and the value are never announced as two
      // unrelated strings.
      label: '${fact.label}: ${fact.value}',
      excludeSemantics: true,
      child: SrCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: SrSpacing.xxs),
              child: Icon(fact.icon, size: 18, color: sr.textMuted),
            ),
            const SizedBox(width: SrSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    fact.label,
                    style: SrTypography.caption.copyWith(color: sr.textMuted),
                  ),
                  const SizedBox(height: SrSpacing.xs),
                  if (tone != null)
                    SrBadge(label: fact.value, tone: tone)
                  else
                    Text(
                      fact.value,
                      style: SrTypography.sectionTitle.copyWith(
                        color: fact.isMuted ? sr.textMuted : sr.foreground,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
