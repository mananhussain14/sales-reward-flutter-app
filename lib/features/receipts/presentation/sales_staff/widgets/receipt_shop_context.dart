import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_shop.dart';

/// The assigned shop, shown as context rather than offered as a choice.
///
/// Rendered in place of `ReceiptShopSelector` when the caller is assigned to
/// exactly one shop. There is nothing to pick: the submission cubit selects that
/// shop the moment `list_my_assigned_receipt_shops()` answers, so the person's
/// only remaining job is the image.
///
/// ## Why this is not a disabled selector
///
/// A greyed-out control still reads as a control — it says "you could change
/// this, but not now", which is the wrong sentence. The shop is not temporarily
/// unavailable; there is genuinely only one, and this states which one it is so
/// the person can see where the invoice / receipt is about to be filed.
///
/// ## It asserts nothing the backend has not said
///
/// The shop displayed here came from the authenticated zero-argument RPC and
/// carries only what that RPC returns — a name and an optional code. No
/// organization, membership or profile id reaches this layer, and the id behind
/// this label is re-proved server-side by `reserve_receipt_submission` under the
/// caller's own token before anything is uploaded. Showing the shop is a
/// courtesy to the reader; it is not, and must never be read as, the
/// authorization.
class ReceiptShopContext extends StatelessWidget {
  const ReceiptShopContext({super.key, required this.shop});

  final ReceiptShop shop;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      container: true,
      // Read as one statement rather than as two orphaned strings, and
      // explicitly not a button: there is nothing here to activate.
      label: 'Submitting for ${shop.displayLabel}',
      child: ExcludeSemantics(
        child: SrCard(
          variant: SrCardVariant.muted,
          padding: const EdgeInsets.all(SrSpacing.lg),
          child: Row(
            children: <Widget>[
              const SrIconDisc(
                icon: Icons.storefront_rounded,
                tone: SrTone.indigo,
                size: 40,
              ),
              const SizedBox(width: SrSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Submitting for',
                      style: SrTypography.caption.copyWith(
                        color: sr.textSecondary,
                      ),
                    ),
                    const SizedBox(height: SrSpacing.xxs),
                    Text(
                      shop.displayLabel,
                      style: SrTypography.label.copyWith(color: sr.foreground),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
