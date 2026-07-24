import '../entities/receipt_file.dart';
import '../entities/receipt_product.dart';
import '../entities/receipt_shop.dart';
import '../entities/receipt_submission.dart';
import '../entities/receipt_submission_outcome.dart';
import 'receipt_result.dart';

/// Everything the Sales Staff receipt flow needs from the backend, expressed
/// without a single Supabase, HTTP or multipart type.
///
/// ## Four backend operations, and no fifth
///
/// | Method | Backend object | Arguments |
/// | --- | --- | --- |
/// | [assignedShops] | `public.list_my_assigned_receipt_shops()` | none |
/// | [receiptProducts] | `public.list_my_receipt_products()` | none |
/// | [submissions] | `public.list_my_receipt_submissions()` | none |
/// | [submission] | `public.get_my_receipt_submission(uuid)` | the id only |
/// | [submitReceipt] | Edge Function `submit-receipt` | `shop_id` + one file |
///
/// Three of the four reads take **zero arguments**. There is no Retailer id,
/// membership id, profile id, role code or permission code to pass, so no URL
/// segment, form field, header or preference can nominate whose data is
/// returned — identity comes from `auth.uid()` and from nothing else. The fourth
/// takes one submission id and no identity alongside it.
///
/// ## What an implementation may not do
///
/// * **No direct Storage access.** `storage.objects` has RLS enabled with zero
///   policies, so only a service-role client can write an object — and that key
///   must never reach a device. The Edge Function performs the protected upload
///   and the finalization behind it.
/// * **No duplicated authorization.** No join over profiles, memberships, roles
///   or permissions, no capability check, no role comparison. Every one of those
///   decisions is made in SQL by resolvers this layer cannot see.
/// * **No client-chosen storage path, status, hash or bucket.** All four are
///   derived server-side.
abstract interface class ReceiptRepository {
  /// The shops the caller is actively assigned to.
  ///
  /// An unauthorized caller raises in SQL rather than returning an empty list,
  /// so [ReceiptReadFailure] with [DeniedFailure] and a successful empty list
  /// are genuinely different answers and must render differently.
  Future<ReceiptResult<List<ReceiptShop>>> assignedShops();

  /// The products actively assigned to the caller's Retailer.
  ///
  /// Read-only reference data. Nothing selected here reaches [submitReceipt].
  Future<ReceiptResult<List<ReceiptProduct>>> receiptProducts();

  /// The caller's own submission history, newest first.
  Future<ReceiptResult<List<ReceiptSubmission>>> submissions();

  /// One of the caller's own submissions, or null.
  ///
  /// **Null is not an error.** An id belonging to somebody else returns zero
  /// rows, byte-identical to a nonexistent id — a distinguishable refusal would
  /// confirm that the id exists. The client must render "we could not read it
  /// back" rather than "that is not yours".
  Future<ReceiptResult<ReceiptSubmission?>> submission(String submissionId);

  /// Submits one receipt image for one assigned shop.
  ///
  /// The request carries **exactly two things**: [shopId] and the bytes of
  /// [file]. No user id, profile id, organization id, Retailer id, membership
  /// id, role, status, product id, reward, coin amount, hash, bucket, storage
  /// path or submitted-by value is sent, because the backend derives every one
  /// of them and would ignore a supplied value anyway.
  ///
  /// Never throws: every failure mode is a case of
  /// [ReceiptSubmissionOutcome], including the one where the transport gave no
  /// usable answer at all.
  Future<ReceiptSubmissionOutcome> submitReceipt({
    required String shopId,
    required ReceiptFile file,
  });
}
