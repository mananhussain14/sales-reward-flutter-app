import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../cubit/receipt_submission_cubit.dart';

/// The four-stage progress panel.
///
/// ## Why stages and not a percentage
///
/// `package:http` does not expose upload progress for a multipart body on either
/// of the two clients this app runs on — the browser XHR client and the IO
/// client — so a percentage would have to be animated from a timer rather than
/// measured. A number that moves without measuring anything is a lie that looks
/// like information, and a person watching a stalled upload would trust it. Four
/// true stages tell them exactly as much as is actually known.
///
/// The bar itself is deliberately **indeterminate**: it says "working", which is
/// the only claim the transport supports.
///
/// ## Accessibility
///
/// The panel is a live region announcing the current stage, so a screen-reader
/// user hears "Uploading receipt" without having to hunt for it, and the stage
/// list marks the finished, current and pending steps with a glyph as well as a
/// colour.
class ReceiptProgressPanel extends StatelessWidget {
  const ReceiptProgressPanel({super.key, required this.stage});

  final ReceiptUploadStage stage;

  static const List<ReceiptUploadStage> _order = <ReceiptUploadStage>[
    ReceiptUploadStage.preparing,
    ReceiptUploadStage.uploading,
    ReceiptUploadStage.confirming,
  ];

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final int currentIndex = _order.indexOf(stage);
    final bool complete = stage == ReceiptUploadStage.complete;

    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Submission progress',
      value: stage.label,
      child: SrCard(
        variant: SrCardVariant.muted,
        padding: const EdgeInsets.all(SrSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    stage.label,
                    style: SrTypography.label.copyWith(color: sr.foreground),
                  ),
                ),
                Text(
                  complete
                      ? 'Done'
                      : 'Step ${currentIndex + 1} of ${_order.length}',
                  style: SrTypography.caption.copyWith(color: sr.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(SrRadii.full),
              child: complete
                  ? LinearProgressIndicator(
                      value: 1,
                      minHeight: 4,
                      backgroundColor: sr.border,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        sr.emerald.foreground,
                      ),
                    )
                  : LinearProgressIndicator(
                      minHeight: 4,
                      backgroundColor: sr.border,
                      valueColor: AlwaysStoppedAnimation<Color>(sr.brand),
                    ),
            ),
            const SizedBox(height: SrSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int i = 0; i < _order.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: SrSpacing.xs),
                    child: _StageRow(
                      label: _order[i].label,
                      done: complete || i < currentIndex,
                      active: !complete && i == currentIndex,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    final (IconData icon, Color colour) = done
        ? (Icons.check_circle_rounded, sr.emerald.foreground)
        : active
        ? (Icons.radio_button_checked_rounded, sr.brand)
        : (Icons.radio_button_unchecked_rounded, sr.textMuted);

    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: colour),
        const SizedBox(width: SrSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: SrTypography.caption.copyWith(
              color: active ? sr.foreground : sr.textSecondary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
