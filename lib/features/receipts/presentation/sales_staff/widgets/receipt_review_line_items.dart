import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_currency_minor_unit.dart';
import '../../../domain/entities/receipt_extraction_line_item.dart';
import 'receipt_minor_units.dart';

/// The lines read from the invoice / receipt.
///
/// **Informational, and nothing more.** Nothing in this milestone matches a line
/// to a product, prices one, or derives anything from it — there is no product
/// matching here and no calculation of any kind. The lines are shown so a
/// reviewer can check what was read against the paper in their hand.
///
/// ## Always open, and above the controls
///
/// This used to be a collapsed `ExpansionTile` at the foot of the screen. It is
/// now an ordinary section, expanded, rendered before the confirmation form.
/// What the provider read *is* the thing a person came to this screen to see;
/// putting it behind a tap asked them to go looking for the answer, and putting
/// it below the form asked them to confirm figures they had not been shown yet.
///
/// ## Read-only, and structurally so
///
/// There is no text field, stepper, delete control, product selector or
/// approval anywhere in this widget, and no callback through which one could be
/// added — it takes data and returns pixels. A line is a fact somebody else
/// wrote; this screen reports it.
///
/// ## Every returned line is rendered
///
/// No `take`, no cap, no page, no filter, and no sort: the backend's own order
/// is the order, and the count in the header is the number of lines that were
/// actually returned. If a document held five items and the provider read four,
/// this says four — it never implies a fifth was found.
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
/// that pairing is a finished fact. The currency box in the form below is a
/// *proposal* about what the receipt should be confirmed as — so wiring it here
/// would relabel AED 12.50 as JPY 1250 the moment somebody typed JPY, changing
/// what the provider is shown to have read on the strength of an edit that has
/// not even been confirmed yet. The reviewer would then be checking the total
/// against figures this screen had rewritten under them.
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
///
/// The same rule governs the unit price and the line amount alike. Neither is
/// ever derived from the other: an amount is not a unit price multiplied by a
/// quantity this client decided to trust, and a unit price is not an amount
/// divided by one. A figure the provider did not read is a figure this screen
/// does not have.
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
    // The number of lines that came back, and nothing else. It is not the
    // number of items on the paper, and it is never rounded up to look
    // complete.
    final String detected = items.length == 1
        ? '1 item detected'
        : '${items.length} items detected';

    return SrSectionCard(
      title: 'Extracted items',
      description: detected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Read from the invoice / receipt. Nothing here can be changed.',
            style: SrTypography.caption.copyWith(color: sr.textSecondary),
          ),
          const SizedBox(height: SrSpacing.lg),
          // The backend's own order, preserved. Never re-sorted here.
          for (final ReceiptExtractionLineItem item in items)
            _Line(
              item: item,
              currencyCode: currencyCode,
              minorDigits: minorDigits,
            ),
        ],
      ),
    );
  }
}

/// One extracted line: what it was, and the three figures read about it.
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

    // Both halves of the extraction's own description of these integers, and
    // neither is optional. An amount with no width to write it in, or no
    // currency to write it under, is shown as unavailable rather than under an
    // assumed one — see the class comment for why there is no fallback here.
    final String? code = _readableCode(currencyCode);
    final int? digits = _readableDigits(minorDigits);

    String? money(int? minor) => minor == null || code == null || digits == null
        ? null
        : formatMinorAmount(minor, code, digits);

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: SrSpacing.lg),
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
                    // rather than being given an invented one. Unbounded, so a
                    // long item name wraps rather than being cut off — there is
                    // nothing below it that a second line could push away.
                    item.description ?? 'Item not read',
                    style: SrTypography.body.copyWith(
                      color: item.description == null
                          ? sr.textMuted
                          : sr.textBody,
                    ),
                  ),
                  const SizedBox(height: SrSpacing.xs),
                  // Wrapped rather than laid out in a row, so three long
                  // figures on a narrow phone run onto a second line instead of
                  // overflowing.
                  Wrap(
                    spacing: SrSpacing.md,
                    runSpacing: SrSpacing.xxs,
                    children: <Widget>[
                      // Quantity is omitted when the provider read none. It is
                      // never defaulted to one: "one of something" and "an
                      // unknown number of something" are different facts, and
                      // only one of them was on the paper.
                      if (item.quantity != null)
                        _Fact(label: 'Qty', value: _quantity(item.quantity!)),
                      // Shown only when a unit price was actually read. Never
                      // computed from the amount and the quantity.
                      if (item.unitPriceMinor != null)
                        _Fact(
                          label: 'Unit',
                          value: money(item.unitPriceMinor) ?? '—',
                          muted: money(item.unitPriceMinor) == null,
                        ),
                      _Fact(
                        label: 'Amount',
                        value: money(item.lineTotalMinor) ?? '—',
                        muted: money(item.lineTotalMinor) == null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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

/// One labelled figure — `Qty 2`, `Unit AED 12.50`, `Amount AED 25.00`.
///
/// One [Text] rather than a label and a value side by side, so a screen reader
/// announces "Unit AED 12.50" as a phrase instead of reading a caption and a
/// number it has to pair up itself.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;

  /// Whether this figure is the em dash rather than a number, in which case it
  /// is drawn back so a row of real figures reads first.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Text(
      '$label $value',
      style: SrTypography.caption.copyWith(
        color: muted ? sr.textMuted : sr.textSecondary,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Three uppercase ASCII letters — an ISO alphabetic code as the backend stores
/// one, and nothing more than the shape.
final RegExp _currencyShape = RegExp(r'^[A-Z]{3}$');
