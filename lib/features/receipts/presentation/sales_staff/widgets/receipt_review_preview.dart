import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../cubit/receipt_review_cubit.dart';

/// The private receipt image, fetched once through a short-lived capability.
///
/// ## The URL is a fetch credential, not a display credential
///
/// The endpoint mints a signed URL that dies after about two minutes. The
/// bytes are fetched once inside that window and the decoded image is held for
/// the screen, so the expiry is invisible in ordinary use. On any load failure —
/// including a resumed screen whose window has closed — [onRefresh] mints a new
/// one.
///
/// The URL is **never** written down. It is read from the state, handed to
/// [Image.network], and that is the whole of its life: it is not persisted, not
/// logged, not used as a cache key, and not placed in a semantics label or any
/// other string a screen reader or a debug dump could carry away.
///
/// ## Why the widget is keyed on a revision rather than on the URL
///
/// Keying on the URL would put the credential in the widget tree's identity,
/// where it shows up in diagnostics. [ReceiptReviewState.previewRevision] is a
/// plain counter that changes on every mint, so a re-minted capability rebuilds
/// the image without the URL ever becoming an identifier.
class ReceiptReviewPreview extends StatelessWidget {
  const ReceiptReviewPreview({
    super.key,
    required this.state,
    required this.onRefresh,
  });

  final ReceiptReviewState state;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: 'Your invoice / receipt',
      description: 'The photo you submitted. Check every value against it.',
      child: AspectRatio(aspectRatio: 3 / 4, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final SrColorScheme sr = context.sr;

    switch (state.previewPhase) {
      case ReceiptPreviewPhase.idle:
      case ReceiptPreviewPhase.loading:
        return const Center(
          child: SrLoadingView(
            showHeader: false,
            rows: 3,
            label: 'Loading your invoice / receipt image',
          ),
        );

      case ReceiptPreviewPhase.failed:
        return Center(
          child: SrEmptyState(
            icon: Icons.image_not_supported_outlined,
            tone: SrTone.amber,
            title: 'We could not show your invoice / receipt',
            description:
                'The image is still stored safely. You can carry on checking '
                'the values, or try loading it again.',
            action: SrButton(
              label: 'Try again',
              variant: SrButtonVariant.outline,
              icon: Icons.refresh_rounded,
              onPressed: onRefresh,
            ),
          ),
        );

      case ReceiptPreviewPhase.ready:
        final String? url = state.preview?.url;
        if (url == null) {
          return const SizedBox.shrink();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(SrRadii.surface),
          child: Semantics(
            // The label describes the image; it deliberately carries no URL,
            // no id and nothing else that outlives the screen.
            label: 'Your submitted invoice / receipt image',
            image: true,
            child: Image.network(
              url,
              // The revision, never the URL. See the class comment.
              key: ValueKey<int>(state.previewRevision),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              loadingBuilder:
                  (
                    BuildContext context,
                    Widget child,
                    ImageChunkEvent? progress,
                  ) {
                    if (progress == null) {
                      return child;
                    }
                    return Center(
                      child: CircularProgressIndicator(color: sr.brand),
                    );
                  },
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) {
                    // The capability has probably expired, which is ordinary and
                    // not an error worth naming. The error object is never bound
                    // to a message: it can quote the URL.
                    return Center(
                      child: SrButton(
                        label: 'Reload image',
                        variant: SrButtonVariant.outline,
                        icon: Icons.refresh_rounded,
                        onPressed: onRefresh,
                      ),
                    );
                  },
            ),
          ),
        );
    }
  }
}
