import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_currency_minor_unit.dart';
import '../../../domain/entities/receipt_extraction_line_item.dart';
import 'receipt_minor_units.dart';

/// The lines read from the receipt.
///
/// **Informational, and nothing more.** Nothing in this milestone matches a line
/// to a product, prices one, or derives anything from it — there is no product
/// matching here and no calculation of any kind. The lines are shown so a
/// reviewer can sanity-check a total against what was actually bought.
///
/// Collapsed by default: most reviews never need them, and a long list above the
/// confirm control would push the primary action off a phone screen.
///
/// Every field except the line number is nullable, because the schema makes
/// every one of them nullable. A line the provider read a description for but no
/// price is exactly that, and is shown as exactly that.
///
/// ## These integers belong to the extraction, and only the extraction may
/// describe them
///
/// [currencyCode] and [minorDigits] are the **reading's own** currency and the
/// **reading's own** `currency_minor_unit`. They must never be sourced from the
/// confirmation draft the reviewer is typing into, nor from the width
/// `get_receipt_currency_minor_unit` resolved for that draft.
///
/// The reason is that these amounts were already written by somebody else. A
/// provider read `1250` off a piece of paper under a currency it also read, and
/// that pairing is a finished fact. The currency box above is a *proposal* about
/// what the receipt should be confirmed as — so wiring it here would relabel
/// AED 12.50 as JPY 1250 the moment somebody typed JPY, changing what the
/// provider is shown to have read on the strength of an edit that has not even
/// been confirmed yet. The reviewer would then be checking the total against
/// figures this screen had rewritten under them.
///
/// The two are therefore kept apart on purpose: the confirmation form resolves
/// and uses its own width, this panel uses the extraction's, and neither can
/// reach the other.
///
/// ## An amount needs both halves, or it is not shown
///
/// A width with no currency and a currency with no width are equally unusable:
/// `1250` is not an amount, and neither is `12.50` with nothing to say what
/// twelve-and-a-half of. Either one missing — absent, blank, malformed, or a
/// width outside the range the backend can report — shows an em dash. There is
/// no fallback of two decimals or of anything else behind it: these lines gate
/// nothing, so an em dash costs nothing, and a wrong figure beside a right one
/// would not.
class ReceiptReviewLineItems extends StatelessWidget {
  const ReceiptReviewLineItems({
    super.key,
    required this.items,
    required this.currencyCode,
    required this.minorDigits,
  });

  final List<ReceiptExtractionLineItem> items;

  /// The **extraction's own** currency code. Never the confirmation draft's.
  final String? currencyCode;

  /// The **extraction's own** `currency_minor_unit`, or null when the reading
  /// reported none. Never the width resolved for the confirmation draft, and
  /// never defaulted.
  final int? minorDigits;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final SrColorScheme sr = context.sr;

    return SrCard(
      padding: EdgeInsets.zero,
      // ExpansionTile paints its background and ink on the nearest Material
      // ancestor, and SrCard is a DecoratedBox — so without this the splash
      // would be painted behind the card and the framework asserts.
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(
              items.length == 1 ? '1 line item' : '${items.length} line items',
              style: SrTypography.cardTitle.copyWith(color: sr.foreground),
            ),
            subtitle: Text(
              'What we read from the body of the receipt.',
              style: SrTypography.caption.copyWith(color: sr.textSecondary),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              SrSpacing.lg,
              0,
              SrSpacing.lg,
              SrSpacing.lg,
            ),
            children: <Widget>[
              // The backend's own order, preserved. Never re-sorted here.
              for (final ReceiptExtractionLineItem item in items)
                _Line(
                  item: item,
                  currencyCode: currencyCode,
                  minorDigits: minorDigits,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.item,
    required this.currencyCode,
    required this.minorDigits,
  });

  final ReceiptExtractionLineItem item;
  final String? currencyCode;
  final int? minorDigits;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final int? total = item.lineTotalMinor;
    // Both halves of the extraction's own description of this integer, and
    // neither is optional. A total with no width to write it in, or no currency
    // to write it under, is shown as unavailable rather than under an assumed
    // one — see the class comment for why there is no fallback here.
    final String? code = _readableCode(currencyCode);
    final int? digits = _readableDigits(minorDigits);
    final String? amount = total == null || code == null || digits == null
        ? null
        : formatMinorAmount(total, code, digits);

    return Padding(
      padding: const EdgeInsets.only(bottom: SrSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Text(
              '${item.lineNumber}',
              style: SrTypography.caption.copyWith(color: sr.textMuted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  // A line with no description read is said to have none,
                  // rather than being given an invented one.
                  item.description ?? 'Item not read',
                  style: SrTypography.caption.copyWith(
                    color: item.description == null
                        ? sr.textMuted
                        : sr.textBody,
                  ),
                ),
                if (item.quantity != null)
                  Text(
                    'Quantity ${_quantity(item.quantity!)}',
                    style: SrTypography.caption.copyWith(color: sr.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: SrSpacing.sm),
          Text(
            amount ?? '—',
            style: SrTypography.caption.copyWith(
              color: amount == null ? sr.textMuted : sr.textBody,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// The extraction's currency code, when it is one at all.
  ///
  /// Absent, blank and malformed collapse to the same answer on purpose: none of
  /// the three says what these integers are denominated in, and rendering a bare
  /// `12.50` beside a figure that has no currency is the same wrong answer in a
  /// quieter voice. The *shape* rule only — which codes exist is the backend's
  /// list, and this widget carries none.
  static String? _readableCode(String? raw) {
    final String code = (raw ?? '').trim().toUpperCase();
    return _currencyShape.hasMatch(code) ? code : null;
  }

  /// The extraction's decimal width, when it is one the backend could have
  /// reported. Null stays null: there is no default of two behind this.
  static int? _readableDigits(int? raw) =>
      raw != null && isSupportedMinorDigits(raw) ? raw : null;

  /// A quantity is the one genuinely fractional value in the schema, so it is
  /// the one place a decimal is correct. Trailing zeroes are trimmed so `2.000`
  /// reads as `2`.
  static String _quantity(double value) {
    final String text = value.toStringAsFixed(3);
    if (!text.contains('.')) {
      return text;
    }
    return text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}

/// Three uppercase ASCII letters — an ISO alphabetic code as the backend stores
/// one, and nothing more than the shape.
final RegExp _currencyShape = RegExp(r'^[A-Z]{3}$');
