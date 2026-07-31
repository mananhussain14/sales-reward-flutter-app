import '../../domain/entities/receipt_confirmation_input.dart';

/// The nine parameters `confirm_receipt_extraction` accepts, named exactly once
/// each.
///
/// Nine, and there is no tenth. There is deliberately no constant here for an
/// organization id, shop id, profile id, membership id, extraction id, entry
/// mode, changed-fields list, duplicate signal, attempt number or mode
/// override — every one of those is derived server-side, and the absence of a
/// name is what makes one impossible to express at this boundary.
const String confirmationSubmissionIdParameter = 'p_submission_id';
const String confirmationTransactionDateParameter = 'p_transaction_date';
const String confirmationCurrencyCodeParameter = 'p_currency_code';
const String confirmationTotalMinorParameter = 'p_total_minor';
const String confirmationMerchantNameParameter = 'p_merchant_name';
const String confirmationDocumentNumberParameter = 'p_document_number';
const String confirmationTransactionTimeParameter = 'p_transaction_time';
const String confirmationSubtotalMinorParameter = 'p_subtotal_minor';
const String confirmationTaxTotalMinorParameter = 'p_tax_total_minor';

/// Encodes one confirmation into the RPC's parameter map.
///
/// Separated from the transport so the whole encoding is testable without a
/// socket, and so that adding a parameter is a change to one pure function that
/// its own test pins.
///
/// ## The three amounts pass through as integers, untouched
///
/// No multiplication, no division, no rounding, no `toDouble`. Minor units
/// arrive as `int` and reach `bigint` as `int`. The contract's ceiling is
/// `10^12`, comfortably inside the 53 bits a JSON number carries exactly, so
/// there is no representation to lose on the way.
///
/// ## Null and zero stay apart
///
/// An omitted subtotal or tax is sent as `null`, never as `0`. The comparison
/// that derives `changed_fields` uses `is distinct from`, where *"NULL is not
/// 0 — zero tax is a fact, unknown tax is not"*, so substituting one for the
/// other would report a correction nobody made.
///
/// ## All nine keys are always present
///
/// The optional parameters have SQL defaults, so omitting a key would work.
/// They are sent explicitly anyway: a fixed key set makes the payload one shape
/// rather than 32, and a test can then assert the whole vocabulary at once
/// instead of whichever subset a particular input happened to produce.
///
/// Normalization here mirrors the function's own first statements — trim and
/// upper-case the currency, blank optional text becomes null. It is a
/// convenience, **not** the authority: the function re-normalizes every value
/// and the currency is checked against a 165-row foreign key this client does
/// not carry.
Map<String, Object?> buildReceiptConfirmationParams(
  ReceiptConfirmationInput input,
) {
  return <String, Object?>{
    confirmationSubmissionIdParameter: input.submissionId,
    confirmationTransactionDateParameter: input.transactionDate.iso,
    confirmationCurrencyCodeParameter: input.currencyCode.trim().toUpperCase(),
    confirmationTotalMinorParameter: input.totalMinor,
    confirmationMerchantNameParameter: _blankToNull(input.merchantName),
    confirmationDocumentNumberParameter: _blankToNull(input.documentNumber),
    confirmationTransactionTimeParameter: input.transactionTime?.iso,
    confirmationSubtotalMinorParameter: input.subtotalMinor,
    confirmationTaxTotalMinorParameter: input.taxTotalMinor,
  };
}

/// `nullif(btrim(...), '')`, in Dart.
String? _blankToNull(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
