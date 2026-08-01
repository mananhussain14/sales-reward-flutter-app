import 'package:equatable/equatable.dart';

import 'receipt_confirmation_entry_mode.dart';
import 'receipt_confirmation_field.dart';
import 'receipt_confirmation_outcome.dart';

/// What `confirm_receipt_extraction` returned.
///
/// Four columns, and three of them are null for
/// [ReceiptConfirmationOutcome.extractionInProgress] — the one branch that
/// writes nothing. They are populated for both settled outcomes, and for
/// [ReceiptConfirmationOutcome.alreadyConfirmed] they describe the **stored**
/// row rather than the values just submitted.
final class ReceiptConfirmationResult extends Equatable {
  const ReceiptConfirmationResult({
    required this.outcome,
    required this.changedFields,
    this.confirmationId,
    this.entryMode,
  });

  final ReceiptConfirmationOutcome outcome;

  /// Null only when nothing was written and nothing already existed.
  final String? confirmationId;

  /// Null on the same branch, for the same reason.
  final ReceiptConfirmationEntryMode? entryMode;

  /// Empty rather than null when the backend sent `null::text[]`, which it does
  /// on the blocked branch. An empty list there is not a claim that nothing
  /// changed — [outcome] already says nothing was compared.
  final List<ReceiptConfirmationField> changedFields;

  @override
  List<Object?> get props => <Object?>[
    outcome,
    confirmationId,
    entryMode,
    changedFields,
  ];
}
