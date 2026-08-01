import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../domain/entities/receipt_extraction_warning_code.dart';
import 'receipt_review_copy.dart';

/// The review hints attached to a stored reading.
///
/// **Codes only, never values.** The backend attaches these so a reviewer's eye
/// is drawn to a figure worth a second look, and for no other purpose: not one
/// of them blocks a confirmation, and this widget offers no control that could
/// suggest otherwise.
///
/// Each code arrives as an enum and leaves as a sentence. A token this build
/// does not recognise gets neutral copy rather than its raw string.
class ReceiptReviewWarnings extends StatelessWidget {
  const ReceiptReviewWarnings({super.key, required this.codes});

  final List<ReceiptExtractionWarningCode> codes;

  @override
  Widget build(BuildContext context) {
    if (codes.isEmpty) {
      return const SizedBox.shrink();
    }

    final SrColorScheme sr = context.sr;
    final SrToneColors tone = sr.tone(SrTone.amber);

    return Container(
      padding: const EdgeInsets.all(SrSpacing.lg),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(SrRadii.control),
        border: Border.all(color: tone.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: tone.foreground,
              ),
              const SizedBox(width: SrSpacing.sm),
              Expanded(
                child: Text(
                  codes.length == 1
                      ? 'One thing to check'
                      : '${codes.length} things to check',
                  style: SrTypography.label.copyWith(color: tone.foreground),
                ),
              ),
            ],
          ),
          const SizedBox(height: SrSpacing.sm),
          for (final ReceiptExtractionWarningCode code in codes)
            Padding(
              padding: const EdgeInsets.only(top: SrSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '• ',
                    style: SrTypography.caption.copyWith(color: tone.alertText),
                  ),
                  Expanded(
                    child: Text(
                      ReceiptReviewCopy.warningLabel(code),
                      style: SrTypography.caption.copyWith(
                        color: tone.alertText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
