import '../../domain/entities/receipt_confirmation_input.dart';
import '../../domain/entities/receipt_product_selection.dart';
import 'receipt_confirmation_request_body.dart';
import 'receipt_product_lines_body.dart';

/// The one parameter `confirm_receipt_with_products` adds to the ten
/// `confirm_receipt_extraction` already declares.
///
/// Eleven in total, and there is no twelfth. The ten header names are reused
/// from `receipt_confirmation_request_body.dart` rather than restated, so the
/// two payloads cannot drift apart into two spellings of the same field.
const String confirmationLinesParameter = 'p_lines';

/// Every parameter name this client may send to the combined RPC.
///
/// Exported so a test can pin the complete vocabulary in one assertion.
const Set<String> receiptWithProductsParameters = <String>{
  confirmationSubmissionIdParameter,
  confirmationTransactionDateParameter,
  confirmationCurrencyCodeParameter,
  confirmationCurrencyMinorUnitParameter,
  confirmationTotalMinorParameter,
  confirmationLinesParameter,
  confirmationMerchantNameParameter,
  confirmationDocumentNumberParameter,
  confirmationTransactionTimeParameter,
  confirmationSubtotalMinorParameter,
  confirmationTaxTotalMinorParameter,
};

/// Encodes one atomic header-and-products confirmation into the RPC's parameter
/// map.
///
/// ## Why this is one call and not two
///
/// The header and the proposal are a single immutable staff assertion. The
/// database writes the confirmation, every proposal line and the Audit Log in
/// one transaction, and rolls all of it back if any line is bad — so a receipt
/// can never end up with transaction details and no products, or with a header
/// that a later request tried to top up. A client that called
/// `confirm_receipt_extraction` first and then sent products would manufacture
/// exactly that state, and the database would answer `CONFLICT` forever after.
///
/// ## The header half is unchanged
///
/// It delegates to [buildReceiptConfirmationParams] verbatim, so the currency
/// normalization, the blank-to-null rule, the null-is-not-zero rule and the
/// integer minor units all behave identically to the header-only path they were
/// written for.
Map<String, Object?> buildReceiptWithProductsParams(
  ReceiptConfirmationInput input,
  ReceiptProductSelection selection,
) {
  return <String, Object?>{
    ...buildReceiptConfirmationParams(input),
    confirmationLinesParameter: buildReceiptProductLines(selection),
  };
}
