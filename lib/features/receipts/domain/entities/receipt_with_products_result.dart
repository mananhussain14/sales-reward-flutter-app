import 'package:equatable/equatable.dart';

import 'receipt_with_products_outcome.dart';

/// What `confirm_receipt_with_products` returned.
///
/// Four columns. [confirmationId] and [lineCount] describe the **stored**
/// confirmation for [ReceiptWithProductsOutcome.alreadyConfirmed], not the
/// values just submitted, and [confirmationId] is null on the
/// [ReceiptWithProductsOutcome.conflict] branch — the one branch that
/// deliberately identifies nothing, so a caller cannot use a refusal to learn
/// another submission's id.
final class ReceiptWithProductsResult extends Equatable {
  const ReceiptWithProductsResult({
    required this.outcome,
    required this.lineCount,
    required this.changed,
    this.confirmationId,
  });

  final ReceiptWithProductsOutcome outcome;

  /// Null on conflict, and on an unreadable answer.
  final String? confirmationId;

  /// How many proposal lines the stored confirmation carries.
  final int lineCount;

  /// True only when **this** call created the confirmation and proposal.
  final bool changed;

  @override
  List<Object?> get props => <Object?>[
    outcome,
    confirmationId,
    lineCount,
    changed,
  ];
}
