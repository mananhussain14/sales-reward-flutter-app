import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import 'sales_staff_home_copy.dart';

/// The primary action, pinned above the bottom navigation on a phone.
///
/// ## It opens the existing flow and owns nothing
///
/// [onPressed] navigates to the Sales Staff submit route. There is no second
/// submission workflow behind this button, no sheet that uploads, and no
/// duplicate of the receipt form — the screen this opens is the one that has
/// always performed the write, with its own cubit, its own duplicate-tap guard
/// and its own progress states.
///
/// ## Why it is a bar and not a floating action button
///
/// A `FloatingActionButton` on a shell with a five-item bottom bar has nowhere
/// to sit that does not cover a destination, and a phone thumb reaching for it
/// crosses two of them. A full-width bar above the navigation is unambiguous,
/// clears the safe-area inset by construction, and is a 48-high target across
/// the whole width rather than a 56px circle.
///
/// ## It gets out of the way
///
/// Hidden while a software keyboard is up. Nothing on the home screen takes
/// text, but a bar that floated over a keyboard on a device that shows one for
/// some other reason would cover the field being typed into.
class SalesStaffAddReceiptBar extends StatelessWidget {
  const SalesStaffAddReceiptBar({super.key, required this.onPressed});

  final VoidCallback onPressed;

  /// The room the scrolling content leaves for this bar, so the last card is
  /// never trapped behind it.
  static const double reservedHeight = 96;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: sr.background,
        border: Border(top: BorderSide(color: sr.border)),
        boxShadow: sr.elevatedShadow,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SrSpacing.lg,
            SrSpacing.md,
            SrSpacing.lg,
            SrSpacing.md,
          ),
          child: SrPressScale(
            child: Semantics(
              button: true,
              label: SalesStaffHomeCopy.addReceiptSemanticLabel,
              excludeSemantics: true,
              child: SrButton(
                label: SalesStaffHomeCopy.addReceipt,
                icon: Icons.add_a_photo_rounded,
                size: SrButtonSize.lg,
                fullWidth: true,
                onPressed: onPressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The same action, as an ordinary button for a layout with room in its header.
///
/// Used from `SrSpacing.breakpointSm` up, where the shell has already promoted
/// its bottom bar to a navigation rail and there is no bottom chrome for a
/// pinned bar to sit above.
class SalesStaffAddReceiptButton extends StatelessWidget {
  const SalesStaffAddReceiptButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SrPressScale(
      child: Semantics(
        button: true,
        label: SalesStaffHomeCopy.addReceiptSemanticLabel,
        excludeSemantics: true,
        child: SrButton(
          label: SalesStaffHomeCopy.addReceipt,
          icon: Icons.add_a_photo_rounded,
          size: SrButtonSize.lg,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
