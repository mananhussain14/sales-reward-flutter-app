import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_file.dart';
import '../../../domain/services/receipt_image_source.dart';

/// The receipt image control: an upload target when nothing is chosen, a preview
/// when something is, and a locked panel while the shop is still unanswered.
///
/// ## What it shows about the file, and what it never shows
///
/// The preview shows the image, its sanitized name, its size and its detected
/// format — everything a person needs to confirm they picked the right
/// photograph. It never shows a device path, a storage bucket, an object path or
/// a hash: the first is private to the device and the other three are private to
/// the server, which is why none of them exists in this layer to display.
///
/// ## Locked is a state of its own, not a disabled button
///
/// [locked] replaces the upload target with an explanation, rather than dimming
/// it. The difference matters on a shop floor: a greyed-out "Take photo" reads
/// as a fault in the app, while a panel saying which field to fill in first
/// reads as an instruction. The buttons are gone in that state, so there is
/// nothing to tap and nothing to be puzzled by.
class ReceiptFileField extends StatelessWidget {
  const ReceiptFileField({
    super.key,
    required this.file,
    required this.enabled,
    required this.supportsCamera,
    required this.onChoose,
    required this.onRemove,
    this.locked = false,
  });

  final ReceiptFile? file;
  final bool enabled;

  /// Whether to offer capture at all. Presentation only — the operating system
  /// still decides access when the camera is opened.
  final bool supportsCamera;

  /// Whether a prerequisite of this field is still unmet — in practice, an
  /// assigned shop that has not been chosen.
  ///
  /// Presentation only, and never the enforcement: the state's `canChooseFile`
  /// and the cubit's own guard both refuse a pick regardless of what this widget
  /// happens to be rendering.
  final bool locked;

  final ValueChanged<ReceiptImageOrigin> onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ReceiptFile? selected = file;

    return SrField(
      label: 'Receipt image',
      required: true,
      hint: 'JPEG, PNG or WebP, up to 10 MB.',
      // A file already chosen keeps its preview even if the field re-locks —
      // losing somebody's photograph to a state change is exactly what this
      // feature is meant to prevent. The actions on it are disabled by
      // [enabled], which is false in that state.
      child: selected != null
          ? _Preview(
              file: selected,
              enabled: enabled,
              supportsCamera: supportsCamera,
              onChoose: onChoose,
              onRemove: onRemove,
            )
          : locked
          ? const _LockedTarget()
          : _EmptyTarget(
              enabled: enabled,
              supportsCamera: supportsCamera,
              onChoose: onChoose,
            ),
    );
  }
}

/// What stands in for the upload target until a shop has been chosen.
///
/// It names the field to answer and the order to answer it in, and it carries no
/// control at all — there is nothing here that could be tapped into a state the
/// form would then refuse.
class _LockedTarget extends StatelessWidget {
  const _LockedTarget();

  @override
  Widget build(BuildContext context) {
    return const SrEmptyState(
      icon: Icons.lock_outline_rounded,
      title: 'Choose a shop first',
      description:
          'Select the shop above first, then add the '
          'invoice / receipt.',
    );
  }
}

/// The dashed tap-to-upload area (§ 4.3 of the design handoff), with the two
/// mobile affordances the web's file input cannot offer.
class _EmptyTarget extends StatelessWidget {
  const _EmptyTarget({
    required this.enabled,
    required this.supportsCamera,
    required this.onChoose,
  });

  final bool enabled;
  final bool supportsCamera;
  final ValueChanged<ReceiptImageOrigin> onChoose;

  @override
  Widget build(BuildContext context) {
    return SrEmptyState(
      // The illustration is the product's own icon treatment, drawn from the
      // bundled icon font. There is no image asset here and there is none to
      // add: this application ships no artwork directory, and a remote
      // illustration would be a network dependency on a screen that has to work
      // on a shop floor.
      icon: Icons.receipt_long_rounded,
      tone: SrTone.indigo,
      title: 'Add the receipt',
      description: supportsCamera
          ? 'Take a photo of the receipt, or choose one you already have. '
                'JPEG, PNG or WebP, up to 10 MB.'
          : 'Choose a photo of the receipt from this device. JPEG, PNG or '
                'WebP, up to 10 MB.',
      action: Wrap(
        spacing: SrSpacing.sm,
        runSpacing: SrSpacing.sm,
        alignment: WrapAlignment.center,
        children: <Widget>[
          if (supportsCamera)
            SrPressScale(
              enabled: enabled,
              child: SrButton(
                label: 'Take photo',
                icon: Icons.photo_camera_rounded,
                size: SrButtonSize.lg,
                onPressed: enabled
                    ? () => onChoose(ReceiptImageOrigin.camera)
                    : null,
              ),
            ),
          SrPressScale(
            enabled: enabled,
            child: SrButton(
              label: 'Choose image',
              variant: SrButtonVariant.outline,
              size: SrButtonSize.lg,
              icon: Icons.image_outlined,
              onPressed: enabled
                  ? () => onChoose(ReceiptImageOrigin.gallery)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// The chosen receipt: a bounded preview, the file facts, and replace / remove.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.file,
    required this.enabled,
    required this.supportsCamera,
    required this.onChoose,
    required this.onRemove,
  });

  final ReceiptFile file;
  final bool enabled;
  final bool supportsCamera;
  final ValueChanged<ReceiptImageOrigin> onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SrCard(
      variant: SrCardVariant.muted,
      padding: const EdgeInsets.all(SrSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            image: true,
            container: true,
            // On the wrapper rather than on Image.memory, so the description
            // survives a file the platform decoder cannot render — the file
            // facts below are still correct, and still enough to submit with.
            label: 'Preview of the selected receipt image',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SrRadii.control),
              child: ConstrainedBox(
                // Bounded so a tall receipt cannot push the submit button off a
                // phone screen, and letterboxed rather than cropped so the whole
                // receipt stays visible.
                constraints: const BoxConstraints(maxHeight: 280),
                child: Container(
                  color: sr.backgroundSecondary,
                  width: double.infinity,
                  child: Image.memory(
                    file.bytes,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    // A picked image is decoded by the platform; if it cannot
                    // be, the file facts below are still correct and still
                    // enough to submit with.
                    errorBuilder:
                        (
                          BuildContext context,
                          Object error,
                          StackTrace? stackTrace,
                        ) => Padding(
                          padding: const EdgeInsets.all(SrSpacing.xxl),
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: sr.textMuted,
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: SrSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      file.fileName,
                      style: SrTypography.label.copyWith(color: sr.foreground),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: SrSpacing.xxs),
                    Text(
                      '${file.imageType.label} · ${file.readableSize}',
                      style: SrTypography.caption.copyWith(
                        color: sr.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SrSpacing.md),
              SrBadge(
                label: 'Ready to send',
                tone: SrTone.indigo,
                icon: Icons.check_rounded,
              ),
            ],
          ),
          const SizedBox(height: SrSpacing.lg),
          Wrap(
            spacing: SrSpacing.sm,
            runSpacing: SrSpacing.sm,
            children: <Widget>[
              if (supportsCamera)
                SrButton(
                  label: 'Retake',
                  variant: SrButtonVariant.outline,
                  size: SrButtonSize.sm,
                  icon: Icons.photo_camera_outlined,
                  onPressed: enabled
                      ? () => onChoose(ReceiptImageOrigin.camera)
                      : null,
                ),
              SrButton(
                label: 'Replace',
                variant: SrButtonVariant.outline,
                size: SrButtonSize.sm,
                icon: Icons.swap_horiz_rounded,
                onPressed: enabled
                    ? () => onChoose(ReceiptImageOrigin.gallery)
                    : null,
              ),
              SrButton(
                label: 'Remove',
                variant: SrButtonVariant.ghost,
                size: SrButtonSize.sm,
                icon: Icons.delete_outline_rounded,
                onPressed: enabled ? onRemove : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
