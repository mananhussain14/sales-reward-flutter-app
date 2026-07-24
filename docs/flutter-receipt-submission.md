# Sales Staff receipt submission

**Branch:** `feat/flutter-sales-staff-receipt-submission`
**Scope:** an authenticated Sales Staff member submits one receipt image for one
assigned shop, sees stage-based progress, and sees the status the database
returned for the row that was created.
**Backend repository:** not modified. Nothing was deployed.

The backend contract this implements is
`salesreward-admin/docs/mobile-receipt-submission-audit.md`. Where this document
and that one differ, that one is right — it describes what is deployed.

---

## 1. What a Sales Staff member can now do

| # | Step | Backend operation |
| --- | --- | --- |
| 1 | See their assigned shops | `public.list_my_assigned_receipt_shops()` |
| 2 | See the products their Retailer stocks | `public.list_my_receipt_products()` |
| 3 | Choose one assigned shop | — |
| 4 | Take or choose a receipt photo | — (device) |
| 5 | Preview it, replace it, remove it | — |
| 6 | Submit it | Edge Function `submit-receipt` |
| 7 | Watch four true progress stages | — |
| 8 | See the submission id and status | `public.get_my_receipt_submission(uuid)` |
| 9 | See their recent submissions | `public.list_my_receipt_submissions()` |
| 10 | Retry a recoverable failure | — |

Nothing else. No OCR, no product matching, no review, approval or rejection, no
reward or coin figure, and no way to view a submitted image.

---

## 2. Architecture

```text
presentation/sales_staff/
  pages/     sales_staff_submit_page.dart      the whole flow
             sales_staff_history_page.dart     SS-05, the caller's own rows
  cubit/     receipt_submission_cubit.dart     the state machine below
             receipt_history_cubit.dart        one list, shared by both tabs
  widgets/   receipt_shop_selector.dart        assigned-shop picker
             receipt_file_field.dart           upload target + preview
             receipt_progress_panel.dart       four stages, no percentage
             receipt_products_section.dart     read-only reference list
             receipt_success_card.dart         the trusted returned row
             receipt_status_badge.dart         RESERVED/SUBMITTED/UPLOAD_FAILED
             receipt_copy.dart                 every user-facing sentence
             receipt_formatting.dart           dates and sizes
        │
        ▼  domain types only — never a Supabase, HTTP or picker type
domain/
  entities/      ReceiptShop · ReceiptProduct · ReceiptSubmission
                 ReceiptSubmissionStatus · ReceiptImageType · ReceiptFile
                 ReceiptRejectionReason · ReceiptSubmissionOutcome
  repositories/  ReceiptRepository (interface) · ReceiptResult<T>
  services/      ReceiptImageSource (interface)
        │
        ▼
data/
  datasources/   receipt_rpc_data_source.dart          the four RPCs
                 submit_receipt_function_client.dart   the multipart POST
  models/        receipt_parsers.dart                  strict parsing
  repositories/  supabase_receipt_repository.dart
  services/      image_picker_receipt_image_source.dart
```

**Rules the layering enforces**, each covered by a test in
`test/security/receipt_boundary_test.dart`:

- The presentation layer never imports `supabase_flutter`, `package:http`, or
  touches `Supabase.instance`.
- The domain layer imports no SDK, no transport package, no picker package, and
  not even `package:flutter`.
- No BLoC state holds a raw SDK map — or any `dynamic` at all.
- Supabase, HTTP and multipart details stop at `data/`.

---

## 3. Exact backend operations

### 3.1 Reads

| Method | RPC | Arguments |
| --- | --- | --- |
| `assignedShops()` | `list_my_assigned_receipt_shops()` | **none** |
| `receiptProducts()` | `list_my_receipt_products()` | **none** |
| `submissions()` | `list_my_receipt_submissions()` | **none** |
| `submission(id)` | `get_my_receipt_submission(p_submission_id)` | the id only |

Three of the four take **zero arguments**, and the data source models them as
nullary Dart functions — so a Retailer id, membership id, profile id, role code,
permission code, email or token is not merely absent, it is *inexpressible* at
that boundary. The fourth passes one key, `p_submission_id`, and a test greps
the source to prove no other `p_*` literal exists in the file.

Returned shapes, parsed strictly:

- shops — `shop_id` (uuid), `shop_name`, `shop_code` (nullable)
- products — `product_id` (uuid), `product_code`, `barcode` (nullable),
  `product_name`, `brand` (nullable)
- submissions — `submission_id` (uuid), `shop_name`, `shop_code` (nullable),
  `status`, `original_file_name`, `mime_type`, `file_size_bytes`,
  `submitted_at` (nullable), `created_at`

One parser deserializes both submission RPCs, because the migration made their
shapes byte-identical precisely so that one client model would serve both.

### 3.2 The Edge Function request

```http
POST https://<project>.supabase.co/functions/v1/submit-receipt
Authorization: Bearer <the caller's current access token>
apikey: <the publishable key from dart_defines.json>
Content-Type: multipart/form-data; boundary=…

--boundary
Content-Disposition: form-data; name="shop_id"

11111111-2222-3333-4444-555555555555
--boundary
Content-Disposition: form-data; name="file"; filename="receipt.png"

<the exact bytes the picker returned>
--boundary--
```

**That is the entire request.** No user id, profile id, organization id,
Retailer id, membership id, role, permission, status, product id, reward, coin
amount, hash, bucket, storage path, submitted-by value, or service-role key —
the backend derives every one of them, and none exists in this application to
send. A test asserts the header set is exactly `Authorization`, `apikey` and the
multipart `Content-Type`, and that every `fields[…]` and `files.add(…)` in the
transport names one of the two declared constants.

The part carries **no declared `Content-Type`**. The function does not read one
(*"The multipart part's own `type` is not read"*); the stored type is derived
from the leading bytes. Sending a declared type would add a value that looks
authoritative and is not.

**Transport choice.** `functions_client` 2.6.4 — the version
`supabase_flutter` 2.16.0 installs — serialises its `body` as JSON, a `String`,
or raw bytes, with no multipart mode, so it cannot express a field beside a file
part. `package:http` 1.6.0 can, its default `Client()` resolves to a browser XHR
client on web and an IO client elsewhere, and it was already in the dependency
graph beneath the SDK.

**Token handling.** `supabaseAccessTokenProvider` reads
`client.auth.currentSession` and, if it has expired, refreshes **once before any
bytes are sent** — so an app resumed from suspension does not discover a `401`
after a 10 MiB upload. No session, or a failed refresh, ends the attempt as
`unauthenticated` with no request leaving the device. This is not a retry of the
upload; it runs before it.

**Timeout:** 90 seconds, applied to the whole exchange. **No automatic retry
ever**, for any status.

---

## 4. File constraints

| Rule | Value | Also enforced by |
| --- | --- | --- |
| Formats | JPEG, PNG, WebP | bucket `allowed_mime_types`, `receipt_submissions_mime_type_allowed`, `sniffReceiptMimeType` |
| Maximum size | 10 MiB (`10 * 1024 * 1024`) | bucket `file_size_limit`, `receipt_submissions_file_size_range` |
| Files per submission | exactly one | `validateReceiptFile(fileCount)` |
| Filename | sanitized, ≤ 255 chars, non-blank | `receipt_submissions_file_name_*` |

The type is decided by **magic bytes**, never by the extension and never by the
picker's declared content type. A file named `receipt.jpg` whose contents are a
PDF is refused here and would be refused again on the server.

**The client-side check is feedback, not authorization.** Every rule is applied
again by the Edge Function against the same bytes, and its answer is what is
stored. Skipping the client check would make the app slower and ruder; weakening
it cannot make the backend accept anything more.

The bytes are **never re-encoded**: no `maxWidth`, no `imageQuality`. The
duplicate guard is a SHA-256 of the bytes the server actually receives, so any
client-side transformation would have to happen on the same side of the wire as
the hash — which is the server's. Downscaling would also destroy the detail a
future OCR step needs.

**Nothing is persisted.** The bytes live in memory for one submission and are
dropped on a confirmed success or an explicit removal. No cache directory, no
gallery album, no `path_provider`, no `File` write. A private receipt left on a
shared shop-floor phone is a leak with no upside.

**File picking** is `image_picker` (flutter.dev-maintained, federated) behind
`ReceiptImageSource`. Permissions declared: iOS
`NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` only — no
microphone string, and **nothing on Android**, because `image_picker` captures
through an `ACTION_IMAGE_CAPTURE` intent and reads through the photo picker,
neither of which needs a manifest permission. Declaring `CAMERA` would make the
app *ask* for something it does not need. On web the browser's own file input is
used and no permission is declared.

---

## 5. The progress state machine

### 5.1 Phases

`ReceiptSubmissionPhase`:

```text
initialLoading ──► loadFailed ──(retry)──► initialLoading
       │
       ▼
     ready ◄──────────────── removeFile / startAnother
       │  choose image
       ▼
  validating ──► rejected        (client-side refusal; selection kept)
       │      └► retryable       (the picker itself failed)
       ▼
 fileSelected ──(submit)──► submitting
                                │
      ┌─────────────────────────┼───────────────────────────┐
      ▼            ▼            ▼            ▼              ▼
   success     duplicate     denied    unauthenticated   rejected
                                                    retryable / unconfirmed
```

`canSubmit` is true only in `fileSelected`, `rejected`, `denied`, `retryable`
and `unconfirmed` — and only with a shop and a file. It is false while busy,
which is the visible half of the duplicate-tap guard; `submit()` re-checks the
same rule, so a stale frame cannot get past it either.

`duplicate` is deliberately **not** retryable. The duplicate index is
`(retailer, submitter, file_sha256)` regardless of shop, so the same bytes would
be refused at any shop. Only a different receipt clears it.

### 5.2 Stages

`ReceiptUploadStage`: `preparing` → `uploading` → `confirming` → `complete`.

Stage-based, not percentage-based. Neither of `package:http`'s two clients
exposes reliable upload progress for a multipart body across Android, iOS and
web, so any percentage would be animated from a timer rather than measured — a
lie that looks like information. The bar is indeterminate, which is the only
claim the transport supports. The panel is a live region announcing the current
stage.

### 5.3 Session isolation

A user switch emits `SessionInitial` and the next person's `SessionActive`
inside one microtask drain, so **no frame ever renders the intermediate state**,
the route match list never leaves `/sales-staff/submit`, and the shell element —
along with the previous person's chosen receipt — survives. Relying on the
router to unmount the subtree is therefore not sound, and a widget test proves
it.

`_SessionIsolation` in `SalesStaffShell` closes the gap with a
`BlocListener<SessionBloc, …>`, which runs on every emitted state whether or not
a frame was built. The moment the session stops being this person's, both cubits
are cleared — shops, products, history, and the bytes of any chosen image. When
a new Sales Staff session settles, both reload from scratch.

---

## 6. Error mapping

### 6.1 HTTP

| HTTP | Function `status` | Outcome | Message shown |
| --- | --- | --- | --- |
| 200 + valid uuid | `submitted` | `Accepted` | "Receipt submitted" + the returned row |
| 200, unusable body | — | `Unconfirmed` | "We could not confirm this submission" |
| 400 | `invalid` | `Refused(reason)` | per reason, see below |
| 401 | `unauthenticated` | `Unauthenticated` | "Your session has ended" |
| 403 | `denied` | `Denied` | "That shop is not available to you" |
| 409 | `duplicate` | `Duplicate` | "You already submitted this receipt" |
| 502 | `upload-failed` | `UploadFailed` | "Upload failed … you can send the same photo again" |
| 503 / any other | `unavailable` | `Unavailable` | same retryable copy |
| timeout | — | `Unconfirmed` | "…may or may not have been saved" |
| dropped connection | — | `Unconfirmed` | as above |

### 6.2 Rejection reasons (`400`)

`too-large` → "larger than 10 MB"; `unsupported-type` → "must be a JPEG, PNG or
WebP image"; `empty`, `missing`, `invalid-name`, `too-many-files`,
`invalid-shop` each get their own sentence; `malformed-body`, `rejected` and any
unrecognised token share one generic sentence. **The raw token is never
rendered.**

### 6.3 SQLSTATE (reads)

`42501` → `DeniedFailure`. `23505` → `DuplicateFailure`. `23514` →
`InvalidFailure`. `55000` → `NotReadyFailure`. Anything else, and any unreadable
body, → `UnavailableFailure`.

### 6.4 The three invariants

1. **An outage never reads as a denial.** A transport fault, an unrecognised
   SQLSTATE, a `502`, a `503` and an unparseable body are all operational.
   Telling a Sales Staff member they lack access when the network merely failed
   is both wrong and alarming.
2. **A denial carries no detail.** `403` covers "not assigned", "inactive",
   "another Retailer's" and "nonexistent" with one byte-identical answer, and
   the client preserves that — `ReceiptSubmissionDenied` has no field to hold a
   reason.
3. **A malformed response is never a fabricated success.** It becomes an
   operational failure, never an empty list, never a default, never a status the
   backend did not send. An unrecognised *status enum value* is the one
   forward-compatible exception: it degrades to `unknown`, renders as "Unknown",
   and unlocks nothing.

### 6.5 The ambiguous case

A timeout, a dropped connection, or a `200` this client cannot parse means the
receipt **may already be stored**. The app:

- does **not** resend;
- refreshes the submission history, which is the only authority on what exists;
- tells the person plainly that it may or may not have saved, and points at the
  list below;
- keeps the chosen receipt, so a *deliberate* second attempt is one tap away.

No raw Postgres message, Edge Function error, storage path, bucket name, request
id or stack trace can reach a screen: none of them reaches the presentation layer
to be rendered.

---

## 7. Security boundaries

| Boundary | How it is held |
| --- | --- |
| No privileged key on the device | Only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, via `AppConfig`. A source test forbids `service_role`, `sb_secret_`, `serviceRoleKey`. |
| No direct Storage access | A source test forbids `storage.from(`, `.upload(`, `uploadBinary(`, `createSignedUrl`, `getPublicUrl` anywhere in the feature; a behavioural test proves submitting produces exactly one request, to the function. |
| No client-chosen path, bucket, hash or status | None is computed, named or sent. `pubspec.yaml` declares no hashing or persistence dependency. |
| No duplicated authorization | No join over profiles, memberships, roles or permissions; no permission code in executable source; the `submit_receipts` capability hint is never read by this feature. |
| No role from email, metadata or preferences | A source test forbids `userMetadata`, `app_metadata`, `SharedPreferences`, JWT decoding and `endsWith('@`. |
| No receipt image in the repository | `git ls-files` is scanned; only the `flutter create` launcher icons are permitted. |
| Nothing logged | The transport writes no log line at all — an `Authorization` header, a response body and a transport exception can each carry material that must not reach a device log. |

`capabilities.submit_receipts` may hide the Submit destination. It is a
**presentation hint only**: the database and the Edge Function decide again on
every call, and a Vendor, Retailer Owner or Retailer Manager who types
`/sales-staff/submit` is redirected to their own landing by the route guard —
and would be refused in SQL even if they were not.

---

## 8. Tests

| File | Covers |
| --- | --- |
| `test/features/receipts/receipt_parsers_test.dart` | valid/nullable/malformed parsing for all three shapes, unknown status, missing values, no privileged defaults, no withheld field surfaced |
| `test/features/receipts/receipt_file_test.dart` | magic-byte sniffing, PDF-as-JPEG, size limits, filename sanitization and traversal, identity equality, the rejection vocabulary |
| `test/features/receipts/receipt_repository_test.dart` | zero-argument RPCs, `p_submission_id` only, the exact multipart body and headers, byte fidelity, every HTTP mapping, timeout and dropped connection, malformed response, no Storage call |
| `test/features/receipts/receipt_submission_cubit_test.dart` | loading, empty shops, empty products, selection, unsupported/oversized/cancelled/replaced/removed files, duplicate-tap protection, every outcome, stage order, detail retrieval, history refresh, clearing |
| `test/features/receipts/receipt_history_cubit_test.dart` | zero-argument load, empty list vs failure, refresh keeping rows, clearing |
| `test/features/receipts/sales_staff_receipt_flow_test.dart` | routing and role isolation for all four roles, loading/empty/failure states, camera vs gallery, preview, stage progress, success, duplicate, denied, retryable, unconfirmed, expired session, four screen sizes, both themes, accessibility labels, session isolation |
| `test/security/receipt_boundary_test.dart` | every row of § 7 |

Fakes live in `test/support/receipt_fakes.dart`; the recording HTTP client in
`test/features/receipts/http_recorder.dart`. Nothing in the suite touches
Supabase, the network, or a platform channel.

---

## 9. Manual verification

Use an existing Sales Staff account. **Do not put real credentials or a real
receipt image in this repository.**

```bash
flutter run --dart-define-from-file=dart_defines.json
```

1. **Sign in** as the Sales Staff account. You land on **Submit a receipt**.
2. **Assigned shops load.** Tap the Shop field; the sheet lists exactly the
   shops that account is assigned to.
3. **Eligible products load.** Expand *Eligible products*; the list matches the
   Retailer's active assigned catalogue and is read-only.
4. **Choose a shop.** The field shows "Name · CODE".
5. **Add a receipt.** *Take photo* on a device, or *Choose image*. Use a small
   JPEG, PNG or WebP. The preview shows the image, the sanitized filename, the
   detected format and the size.
6. **Submit.** Watch *Preparing → Uploading receipt → Confirming submission →
   Complete*. No percentage appears.
7. **Confirm.** The success card shows status **Submitted**, the shop, the file,
   the size, the format, the received time and the submission ID. No storage
   path, bucket or hash appears anywhere.
8. **Recent submissions** below now contains the new row. The **History** tab
   shows the same row.
9. **Duplicate.** Tap *Submit another receipt*, choose the **same** image and
   the same shop, and submit. Expect "You already submitted this receipt" and a
   disabled submit button. Choosing a different image re-enables it.
10. **Wrong shop.** If a shop was recently unassigned from the account, choosing
    it yields "That shop is not available to you" — with the receipt kept so
    another shop can be tried.
11. **Offline.** Disable the network and submit. Expect "We could not confirm
    this submission" and *not* a second upload; the history refreshes.
12. **Log out** from the account sheet. Sign back in: the shop selection, the
    chosen image and the history are all gone.

Web: `flutter run -d chrome --dart-define-from-file=dart_defines.json`. *Take
photo* maps to a capture-hinted file input; everything else is identical.

---

## 10. Known limitations

- **No OCR.** Nothing reads the receipt. `submit-receipt` stores an image and
  metadata.
- **No secure receipt-image retrieval.** There is no signed-URL function, no
  download RPC and no storage policy anywhere in the backend, so a submitted
  image cannot be viewed. `mobile-backend-contract.md` § 7 Q1 remains open.
  History rows are deliberately not tappable.
- **No review or approval flow.** The status vocabulary is `RESERVED`,
  `SUBMITTED`, `UPLOAD_FAILED` and nothing else.
- **No reward or coin calculation.** No incentive, campaign, reward, coin or
  payout object exists.
- **No product is attached to a submission.** `list_my_receipt_products()` is
  reference data; the endpoint accepts no product parameter and
  `receipt_submissions` stores none. The UI says so in the section caption.
- **Multi-Retailer ambiguity remains fail-closed.**
  `resolve_retailer_member_organization` returns `NULL` for a person who
  qualifies at more than one Retailer, so every receipt operation is refused for
  them. That is a product question, not a defect, and this milestone does not
  touch it.
- **No real byte progress.** See § 5.2.
- **No offline queue.** A submission requires connectivity; an unconfirmed
  result is surfaced rather than queued.
