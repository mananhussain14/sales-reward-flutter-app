/// Fixtures for the receipt extraction and confirmation contract.
///
/// Each builder returns the body **as the backend sends it** — the Edge
/// Function's explicit key allowlist for an extraction payload, and PostgREST's
/// row array for an RPC — and takes an `overrides` map so a test can vary one
/// field without restating thirty-seven. Removing a key (to model a missing
/// required field) is `..remove('status')` on the result.
///
/// The default extraction is a two-minor-unit AED receipt that succeeded on its
/// first attempt: the ordinary case, so a test that departs from it says so.
library;

const String extractionSubmissionUuid = '3f1c9c2a-5b7e-4c1d-9a2b-6d8e0f1a2b3c';
const String extractionAttemptUuid = '7a2b4c6d-8e0f-4a1b-9c2d-3e4f5a6b7c8d';
const String extractionConfirmationUuid =
    'b1c2d3e4-f5a6-4b7c-8d9e-0f1a2b3c4d5e';

/// One `extraction` payload, exactly as all three Edge Functions build it.
Map<String, Object?> extractionPayload([
  Map<String, Object?> overrides = const <String, Object?>{},
]) {
  return <String, Object?>{
    'submission_id': extractionSubmissionUuid,
    'extraction_id': extractionAttemptUuid,
    'status': 'SUCCEEDED',
    'attempt_number': 1,
    'attempts_used': 1,
    'attempts_remaining': 2,
    'retry_allowed': false,
    'manual_confirmation_allowed': true,
    'confirmation_exists': false,
    'failure_code': null,
    'requested_at': '2026-07-25T09:30:00+00:00',
    'completed_at': '2026-07-25T09:30:04+00:00',
    'merchant_name': 'Marina Pharmacy',
    'merchant_name_source_text': 'MARINA  PHARMACY LLC',
    'merchant_name_confidence': 0.94,
    'document_number': 'INV-2026/004512',
    'document_number_source_text': 'Invoice INV-2026/004512',
    'document_number_confidence': 0.88,
    'transaction_date': '2026-07-25',
    'transaction_date_source_text': '25/07/2026',
    'transaction_date_confidence': 0.97,
    'transaction_time': '09:24:00',
    'transaction_time_source_text': '09:24',
    'transaction_time_confidence': 0.81,
    'currency_code': 'AED',
    'currency_code_source_text': 'AED',
    'currency_code_confidence': 0.99,
    'currency_minor_unit': 2,
    'total_minor': 12550,
    'total_source_text': 'AED 125.50',
    'total_confidence': 0.96,
    'subtotal_minor': 11952,
    'subtotal_source_text': '119.52',
    'subtotal_confidence': 0.9,
    'tax_total_minor': 598,
    'tax_source_text': '5.98',
    'tax_confidence': 0.9,
    'warning_codes': <String>[],
    'line_item_count': 3,
  }..addAll(overrides);
}

/// A `request-receipt-extraction` 200 body.
Map<String, Object?> requestExtractionBody({
  String outcome = 'QUEUED',
  int attemptsUsed = 1,
  int attemptsRemaining = 2,
  bool retryAllowed = false,
  bool manualConfirmationAllowed = true,
  Object? extraction,
}) {
  return <String, Object?>{
    'status': 'ok',
    'outcome': outcome,
    'attempts_used': attemptsUsed,
    'attempts_remaining': attemptsRemaining,
    'retry_allowed': retryAllowed,
    'manual_confirmation_allowed': manualConfirmationAllowed,
    'extraction': extraction,
  };
}

/// A `get-receipt-extraction` 200 body.
Map<String, Object?> getExtractionBody([Map<String, Object?>? payload]) {
  return <String, Object?>{
    'status': 'ok',
    'extraction': payload ?? extractionPayload(),
  };
}

/// A `receipt-image-preview` 200 body. The URL is a fixture, never a real one.
Map<String, Object?> imagePreviewBody({
  Object? url = 'https://example.supabase.co/storage/v1/object/sign/fixture',
  Object? expiresInSeconds = 120,
}) {
  return <String, Object?>{
    'status': 'ok',
    'url': url,
    'expires_in_seconds': expiresInSeconds,
  };
}

/// An `invalid` refusal, as the endpoints build it.
Map<String, Object?> invalidBody(String reason) => <String, Object?>{
  'status': 'invalid',
  'reason': reason,
};

/// One `list_my_receipt_extraction_line_items` row.
Map<String, Object?> lineItemRow([
  Map<String, Object?> overrides = const <String, Object?>{},
]) {
  return <String, Object?>{
    'line_number': 1,
    'description': 'Paracetamol 500mg',
    'description_source_text': 'PARACETAMOL 500MG  x2',
    'quantity': 2.0,
    'quantity_source_text': 'x2',
    'unit_price_minor': 1250,
    'unit_price_source_text': '12.50',
    'line_total_minor': 2500,
    'line_total_source_text': '25.00',
    'confidence': 0.87,
  }..addAll(overrides);
}

/// One `get_my_receipt_confirmation` row.
Map<String, Object?> confirmationRow([
  Map<String, Object?> overrides = const <String, Object?>{},
]) {
  return <String, Object?>{
    'confirmation_id': extractionConfirmationUuid,
    'entry_mode': 'EXTRACTED',
    'changed_fields': <String>[],
    'source_extraction_id': extractionAttemptUuid,
    'transaction_date': '2026-07-25',
    'transaction_time': '09:24:00',
    'currency_code': 'AED',
    'currency_minor_unit': 2,
    'total_minor': 12550,
    'subtotal_minor': 11952,
    'tax_total_minor': 598,
    'merchant_name': 'Marina Pharmacy',
    'document_number': 'INV-2026/004512',
    'confirmed_at': '2026-07-25T10:02:00+00:00',
  }..addAll(overrides);
}

/// One `confirm_receipt_extraction` row.
Map<String, Object?> confirmationResultRow([
  Map<String, Object?> overrides = const <String, Object?>{},
]) {
  return <String, Object?>{
    'outcome': 'CONFIRMED',
    'confirmation_id': extractionConfirmationUuid,
    'entry_mode': 'EXTRACTED',
    'changed_fields': <String>[],
  }..addAll(overrides);
}
