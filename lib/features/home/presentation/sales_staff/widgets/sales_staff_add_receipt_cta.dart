import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import 'sales_staff_home_copy.dart';

/// The primary action, floating above the bottom navigation on a phone.
///
/// ## It opens the existing flow and owns nothing
///
/// [onPressed] navigates to the Sales Staff submit route. There is no second
/// submission workflow behind this button, no sheet that uploads, and no
/// duplicate of the receipt form — the screen this opens is the one that has
/// always performed the write, with its own cubit, its own duplicate-tap guard
/// and its own progress states.
///
/// ## A floating pill, not a full-width bar
///
/// The first version drew an edge-to-edge bar with a hairline above it, which
/// read as a second navigation strip stacked on the real one. A rounded pill
/// inset from both edges, lifted on the brand gradient and its own shadow,
/// reads as an *object on top of* the page — which is what a floating action
/// is — and leaves the bottom bar visibly separate beneath it.
///
/// It is centred and content-width rather than stretched, so the two-line
/// label stays a comfortable reading measure on a tablet.
///
/// ## It clears the chrome by construction
///
/// [reservedHeight] is the room the scrolling content leaves for it, and the
/// pill sits inside the page body — above the `NavigationBar`, never over it.
/// `SafeArea` adds the home-indicator inset underneath.
///
/// ## It gets out of the way
///
/// Hidden while a software keyboard is up. Nothing on the home screen takes
/// text, but a pill that floated over a keyboard on a device that shows one for
/// some other reason would cover the field being typed into.
class SalesStaffAddReceiptBar extends StatelessWidget {
  const SalesStaffAddReceiptBar({super.key, required this.onPressed});

  final VoidCallback onPressed;

  /// The room the scrolling content leaves for this pill, so the last card is
  /// never trapped behind it.
  static const double reservedHeight = 108;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SrSpacing.xl,
          0,
          SrSpacing.xl,
          SrSpacing.lg,
        ),
        // Right-aligned rather than centred, and the reason is a collision
        // rather than a preference: a centred pill lands exactly on the hero
        // card's own full-width action, so two different controls occupy one
        // patch of screen and a thumb between them is ambiguous. The hero's
        // action is left-aligned and this one is right-aligned, so neither ever
        // covers the other at any scroll position.
        child: Align(
          alignment: Alignment.bottomRight,
          child: SalesStaffAddReceiptPill(onPressed: onPressed),
        ),
      ),
    );
  }
}

/// The pill itself: brand gradient, receipt glyph, label and supporting line.
///
/// Built here rather than from [SrButton] because this is the one control in
/// the product that carries a gradient and a two-line label. Everything else it
/// keeps — the 12-radius family, the semibold label, the 8px icon gap, the
/// press scale — matches the shared button exactly.
class SalesStaffAddReceiptPill extends StatelessWidget {
  const SalesStaffAddReceiptPill({
    super.key,
    required this.onPressed,
    this.compact = false,
  });

  final VoidCallback onPressed;

  /// Drops the supporting line, for a header where the hint would be noise.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final BorderRadius shape = BorderRadius.circular(SrRadii.full);

    return Semantics(
      button: true,
      label: SalesStaffHomeCopy.addReceiptSemanticLabel,
      excludeSemantics: true,
      child: SrPressScale(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: shape,
            boxShadow: sr.elevatedShadow,
          ),
          child: ClipRRect(
            borderRadius: shape,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[sr.brand, sr.brandHover],
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: shape,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: SrSpacing.xxl,
                      vertical: compact ? SrSpacing.md : SrSpacing.mdPlus,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: sr.onBrand.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(SrRadii.full),
                          ),
                          child: Icon(
                            Icons.add_a_photo_rounded,
                            size: 16,
                            color: sr.onBrand,
                          ),
                        ),
                        const SizedBox(width: SrSpacing.md),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                SalesStaffHomeCopy.addReceipt,
                                style: SrTypography.buttonLarge.copyWith(
                                  color: sr.onBrand,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (!compact)
                                Text(
                                  SalesStaffHomeCopy.addReceiptHint,
                                  style: SrTypography.caption.copyWith(
                                    color: sr.onBrand.withValues(alpha: 0.82),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The same action, as a compact pill for a layout with room in its header.
///
/// Used from `SrSpacing.breakpointSm` up, where the shell has already promoted
/// its bottom bar to a navigation rail and there is no bottom chrome for a
/// floating pill to sit above.
class SalesStaffAddReceiptButton extends StatelessWidget {
  const SalesStaffAddReceiptButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SalesStaffAddReceiptPill(onPressed: onPressed, compact: true);
  }
}
