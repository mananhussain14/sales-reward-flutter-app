import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import 'receipt_copy.dart';

/// Where a submission is in its four steps.
///
/// Derived from the submission phase by the screen, never held in state: there
/// is no step counter anywhere in this feature, and adding one would be a second
/// definition of "where am I" that could disagree with the first.
enum ReceiptStep { chooseReceipt, reviewImage, submitSecurely, reviewDetails }

/// The four steps of a submission, with the current one marked.
///
/// ## Why a strip and not a stepper
///
/// Material's `Stepper` owns navigation — it expects to advance and go back on
/// its own. Nothing here navigates: the step is a *readout* of the submission
/// phase, and the only things that change it are choosing a file, submitting,
/// and the function answering. A control that looked like it could move the
/// sequence forward would be a promise this screen cannot keep.
///
/// ## Three channels, never colour alone
///
/// A finished step carries a tick, the current one carries a filled dot and a
/// semibold label, and a pending one carries an outline. The tone repeats what
/// the glyph and the weight already say.
///
/// ## Announced once, as a sentence
///
/// The strip is one semantics node reading "Step 2 of 4: Review image". Four
/// separate nodes would have a reader hear every step's name on every rebuild,
/// which is noise on a screen whose actual content is below it.
class ReceiptStepsStrip extends StatelessWidget {
  const ReceiptStepsStrip({super.key, required this.current});

  final ReceiptStep current;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final List<String> steps = ReceiptCopy.submitSteps;
    final int position = current.index;

    return Semantics(
      container: true,
      label:
          'Step ${position + 1} of ${steps.length}: '
          '${steps[position]}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(SrSpacing.lg),
        decoration: BoxDecoration(
          color: sr.surfaceMuted,
          borderRadius: BorderRadius.circular(SrRadii.surface),
          border: Border.all(color: sr.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // A Wrap rather than a Row: four labelled steps at a large text
            // scale on a narrow phone would overflow one line, and wrapping is
            // what keeps every label readable instead of shrinking them all.
            Wrap(
              spacing: SrSpacing.lg,
              runSpacing: SrSpacing.smPlus,
              children: <Widget>[
                for (int i = 0; i < steps.length; i++)
                  _Step(
                    number: i + 1,
                    label: steps[i],
                    done: i < position,
                    active: i == position,
                  ),
              ],
            ),
            const SizedBox(height: SrSpacing.md),
            Text(
              ReceiptCopy.submitStepsNote,
              style: SrTypography.caption.copyWith(color: sr.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.label,
    required this.done,
    required this.active,
  });

  final int number;
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final SrToneColors tone = sr.tone(
      done ? SrTone.emerald : (active ? SrTone.indigo : SrTone.slate),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active || done ? tone.fill : Colors.transparent,
            borderRadius: BorderRadius.circular(SrRadii.full),
            border: Border.all(color: active || done ? tone.border : sr.border),
          ),
          child: done
              ? Icon(Icons.check_rounded, size: 13, color: tone.foreground)
              : Text(
                  '$number',
                  style: SrTypography.badge.copyWith(
                    color: active ? tone.alertText : sr.textMuted,
                  ),
                ),
        ),
        const SizedBox(width: SrSpacing.sm),
        // Flexible, so the longest label wraps inside the strip rather than
        // pushing the row past its edge on a 360px phone or at a large text
        // scale. The Wrap above hands each step the full width, so a step that
        // cannot fit on one line simply takes two.
        Flexible(
          child: Text(
            label,
            style: SrTypography.caption.copyWith(
              color: active ? sr.foreground : sr.textSecondary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
