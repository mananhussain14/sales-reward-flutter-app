import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import 'receipt_review_copy.dart';

/// A receipt confirmed before products were part of one.
///
/// ## This is a legal historical state, not a fault
///
/// A transaction confirmation exists and no product proposal does, because the
/// receipt was confirmed through the header-only flow that preceded Phase
/// 1D-B. It is not a network failure, not a malformed response, not a proposal
/// still being written, not an editable new receipt and not a rejected
/// proposal — and the copy is careful to read as none of them. It is stated
/// plainly, without an apology and without inviting anybody to contact support
/// about a receipt that is behaving exactly as recorded.
///
/// ## Nothing here can add products
///
/// A confirmation is immutable and the combined RPC answers `CONFLICT` to any
/// attempt to top one up, so there is no backfill, correction, resubmit or
/// reopen control in this file. As with the submitted section, that is enforced
/// by absence rather than by a disabled flag: the widgets are not here, so
/// there is nothing for a stale frame to reach.
class ReceiptLegacyConfirmationSection extends StatelessWidget {
  const ReceiptLegacyConfirmationSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: ReceiptReviewCopy.legacyTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            liveRegion: true,
            container: true,
            label:
                '${ReceiptReviewCopy.legacyTitle}. '
                '${ReceiptReviewCopy.legacyExplanation}',
            // The card's own title already states the heading; repeating it
            // here would render it twice and read as an error banner rather
            // than an explanation.
            child: const SrAlert(
              tone: SrAlertTone.info,
              title: 'What this means',
              message:
                  '${ReceiptReviewCopy.legacyExplanation}\n\n'
                  '${ReceiptReviewCopy.legacyConsequence}',
            ),
          ),
          const SizedBox(height: SrSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: SrBadge(
              label: 'No product list',
              tone: SrTone.slate,
              icon: Icons.inventory_2_outlined,
            ),
          ),
        ],
      ),
    );
  }
}
