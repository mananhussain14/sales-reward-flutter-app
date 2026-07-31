import '../entities/receipt_confirmation.dart';
import '../entities/receipt_confirmation_input.dart';
import '../entities/receipt_confirmation_result.dart';
import '../entities/receipt_extraction.dart';
import '../entities/receipt_extraction_line_item.dart';
import '../entities/receipt_extraction_request_result.dart';
import '../entities/receipt_image_preview.dart';
import 'receipt_extraction_result.dart';

/// Everything the receipt review flow needs from the backend, expressed without
/// a single Supabase, HTTP or JSON type.
///
/// ## Six backend operations, and no seventh
///
/// | Method | Backend object | Arguments | Writes |
/// | --- | --- | --- | --- |
/// | [requestExtraction] | Edge Fn `request-receipt-extraction` | the id only | **yes** |
/// | [extraction] | Edge Fn `get-receipt-extraction` | the id only | **yes**¹ |
/// | [lineItems] | `list_my_receipt_extraction_line_items(uuid)` | the id only | no |
/// | [imagePreview] | Edge Fn `receipt-image-preview` | the id only | no |
/// | [confirm] | `confirm_receipt_extraction(uuid, date, text, bigint, …)` | nine values | **yes** |
/// | [confirmation] | `get_my_receipt_confirmation(uuid)` | the id only | no |
///
/// ¹ [extraction] reads, but it is the only function that *completes* an
/// attempt, and it may also expire one stale claim. It is idempotent and safe to
/// call repeatedly; it is not, however, a pure read, and this table says so
/// rather than letting a caller assume otherwise.
///
/// Five of the six take one submission id and no identity beside it. The sixth
/// takes eight values about the receipt and, again, no identity: the caller
/// comes from `auth.uid()`, the Retailer is resolved in SQL, and there is no
/// argument through which either could be nominated.
///
/// ## What an implementation may not do
///
/// * **No direct table access.** All five extraction tables have RLS enabled,
///   zero policies, and every privilege revoked from `authenticated`. A query
///   against `receipt_extractions`, `receipt_extraction_line_items`,
///   `receipt_confirmations`, `receipt_extraction_runtime` or
///   `iso_currency_codes` would not merely be poor layering — it would return
///   nothing, and the attempt to make it work is the first step toward putting
///   a privileged key on a device.
/// * **No worker RPC.** The seven worker functions are granted to the
///   privileged database role alone. This client cannot claim a job, record an
///   operation, record a success or a failure, read worker state, obtain the
///   object reference, or run the reaper — and must never be given a credential
///   that would let it.
/// * **No storage access of any kind.** No bucket name, no object path, no
///   listing, no deletion, no public URL. The preview endpoint mints a
///   short-lived URL server-side and that URL is the entire surface.
/// * **No client-derived entry mode, changed-fields list, retry permission,
///   attempt count or failure mapping.** Every one is computed in SQL.
/// * **No automatic retry of a mutating call.** See [requestExtraction].
abstract interface class ReceiptExtractionRepository {
  /// Asks that a submitted receipt be read.
  ///
  /// **Mutating, and never retried automatically.** A repeat of this call can
  /// consume one of the three attempts a receipt gets in its lifetime, and no
  /// layer beneath the person tapping the button has the information to decide
  /// that is acceptable. A transport fault therefore surfaces as
  /// `ExtractionNetworkProblem` and stops there.
  ///
  /// A successful result may report that nothing was created — an existing
  /// attempt, an existing confirmation, exhausted attempts or an unavailable
  /// provider are all ordinary outcomes.
  Future<ReceiptExtractionResult<ReceiptExtractionRequestResult>>
  requestExtraction(String submissionId);

  /// Reads the latest attempt, and completes it when it is genuinely in flight.
  ///
  /// One poll per call, never a loop — *"a loop would hold the invocation open
  /// and hide latency the client must be able to see"*. Deciding **when** to
  /// call this again is a caller's job and is not implemented in this slice.
  ///
  /// A `SUCCEEDED` or `FAILED` attempt comes back regardless of any gate:
  /// disabling execution must never hide stored evidence.
  Future<ReceiptExtractionResult<ReceiptExtraction>> extraction(
    String submissionId,
  );

  /// The line items of the successful attempt, in the backend's own order.
  ///
  /// An empty list is a real answer and means exactly that — no line items were
  /// recorded, or there is no successful attempt. It is never a refusal: the
  /// function returns zero rows for an unauthorized caller too, and that
  /// collapse is deliberate.
  Future<ReceiptExtractionResult<List<ReceiptExtractionLineItem>>> lineItems(
    String submissionId,
  );

  /// A short-lived capability to fetch the receipt image once.
  ///
  /// The returned URL must not be persisted anywhere — not to disk, not to a
  /// log, not to an image-cache key. Call this again rather than storing it.
  Future<ReceiptExtractionResult<ReceiptImagePreview>> imagePreview(
    String submissionId,
  );

  /// Confirms the receipt's values.
  ///
  /// **Mutating, immutable and never retried automatically.** A confirmation
  /// cannot be updated, deleted or revised. A resend after a lost reply is safe
  /// in the sense that it cannot create a second row — the unique constraint
  /// settles it and the answer becomes `ALREADY_CONFIRMED` — but it is the
  /// caller's explicit act, not this layer's.
  Future<ReceiptExtractionResult<ReceiptConfirmationResult>> confirm(
    ReceiptConfirmationInput input,
  );

  /// The stored confirmation, or null when there is none.
  ///
  /// **Null is not an error**, and it is not "not yours" either: the function
  /// returns zero rows for an unreadable receipt and for an unconfirmed one
  /// alike, which is what stops it confirming that somebody else's receipt
  /// exists.
  Future<ReceiptExtractionResult<ReceiptConfirmation?>> confirmation(
    String submissionId,
  );
}
