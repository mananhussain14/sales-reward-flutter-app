import 'package:equatable/equatable.dart';

/// One line read from a receipt.
///
/// **Informational, and nothing more.** Line items are worker-written, written
/// once, and never revised. Nothing in Milestone A matches them to products,
/// prices them, or derives a reward from them — there is no product matching and
/// no incentive calculation anywhere in this feature.
///
/// Every field except [lineNumber] is nullable, because the schema makes every
/// one of them nullable: a provider that read a description but no price
/// produces exactly that row. As with the header fields, a source text may be
/// present while its normalized counterpart is null.
final class ReceiptExtractionLineItem extends Equatable {
  const ReceiptExtractionLineItem({
    required this.lineNumber,
    this.description,
    this.descriptionSourceText,
    this.quantity,
    this.quantitySourceText,
    this.unitPriceMinor,
    this.unitPriceSourceText,
    this.lineTotalMinor,
    this.lineTotalSourceText,
    this.confidence,
  });

  /// `line_number` — 1-based, dense, unique within the extraction, and the
  /// backend's own ordering. It is not re-sorted here.
  final int lineNumber;

  final String? description;
  final String? descriptionSourceText;

  /// `quantity` — `numeric(12,3)`, and *"the ONLY non-integer numeric in the
  /// extraction schema. Money is never numeric here."*
  ///
  /// A double is correct for a quantity and wrong for money, which is why the
  /// two amounts below are integers.
  final double? quantity;
  final String? quantitySourceText;

  /// `unit_price_minor` — integer minor units, never a double.
  final int? unitPriceMinor;
  final String? unitPriceSourceText;

  /// `line_total_minor` — integer minor units, never a double.
  final int? lineTotalMinor;
  final String? lineTotalSourceText;

  /// `confidence` — `0.0`–`1.0`, or null.
  final double? confidence;

  @override
  List<Object?> get props => <Object?>[
    lineNumber,
    description,
    descriptionSourceText,
    quantity,
    quantitySourceText,
    unitPriceMinor,
    unitPriceSourceText,
    lineTotalMinor,
    lineTotalSourceText,
    confidence,
  ];
}
