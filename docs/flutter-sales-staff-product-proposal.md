# Sales Staff product proposal (Phase 1D-B)

**Branch:** `feature/flutter-sales-staff-product-proposal`
**Scope:** an authenticated Sales Staff member states **which products a receipt
is for**, and submits that list together with the transaction details as one
immutable assertion.
**Backend repository:** not modified. Nothing was deployed.

The contract this implements is deployed migration **64**,
`receipt_product_proposals_and_sale_items`. Where this document and that
migration differ, the migration is right — it describes what is deployed.

---

## 1. What a Sales Staff member can now do

| # | Step | Backend operation |
| --- | --- | --- |
| 1 | See the products their Retailer is assigned | `public.list_my_receipt_products()` |
| 2 | Search that list by name, code or barcode | — (local) |
| 3 | Add products, and set how many of each | — (local) |
| 4 | Confirm the receipt **and** its products, in one step | `public.confirm_receipt_with_products(…)` |
| 5 | Read back the immutable submitted proposal | `public.get_my_receipt_product_proposal(uuid)` |
| 6 | Check what is stored, after an unclear result | the two reads above, by hand |

Nothing else. No OCR product matching, no campaign evaluation, no reward, no
coin, no correction, no backfill and no way to change a proposal once sent.

Receipt **extraction** remains disabled; this flow does not depend on it, and a
receipt whose reading failed can still be confirmed by typing the details in.

---

## 2. Building the proposal

### The catalogue is the only door

`list_my_receipt_products()` returns only products that are ACTIVE **and**
actively assigned to the caller's own Retailer. It is read **once** per screen;
search, selection, quantity and removal never touch the network again.

There is no free-text product field, no "add a product" affordance and no
product-id input anywhere in this feature. A product can only enter the list by
being selected from that read, so a product the Retailer is not entitled to
cannot be expressed — and the database re-checks eligibility inside the write
transaction regardless.

### The rules the client applies before sending

| Rule | Behaviour |
| --- | --- |
| At least one product | A receipt cannot be submitted without products |
| At most **50** lines | The 51st is refused; nothing is evicted |
| Quantity **1–100**, whole numbers | A stepper, so `2.5`, `-1`, `250` and empty are unreachable |
| No duplicate product | Refused, and **never** merged into the existing line |
| Order is the proposal | Adding appends, removing closes the gap, nothing sorts |

Every one of these is enforced again in SQL. They exist here so a staff member
is stopped at the control rather than by a refused immutable write.

A duplicate is deliberately **not** silently added to the first line's quantity:
quietly changing a number nobody typed is how a proposal stops matching what a
person meant. The UI points at the existing line instead.

---

## 3. Submitting: one call, and only one

### The write

```
public.confirm_receipt_with_products(
  p_submission_id, p_transaction_date, p_currency_code, p_currency_minor_unit,
  p_total_minor, p_lines,
  p_merchant_name, p_document_number, p_transaction_time,
  p_subtotal_minor, p_tax_total_minor
)
```

Eleven parameters and no twelfth. The header half is serialized by exactly the
same code as the older header-only path, so currency normalization, the
blank-to-null rule, the null-is-not-zero rule and integer minor units all behave
identically.

### `p_lines` carries two keys

```json
[ { "product_id": "…", "quantity": 2 } ]
```

There is no constant in the serializer for a product name, code, barcode, brand,
status, line number, Vendor id, Retailer id, shop id, staff id, actor id,
campaign field or reward field. The absence of a *name* is what makes one
impossible to express at that boundary.

`line_number` is derived by the database from array position, so array order is
the line numbering. Quantities are emitted as JSON integers, never as a `double`
and never as a string.

### The snapshots belong to the database

The proposal stores `product_name_at_proposal`, `product_code_at_proposal`,
`barcode_at_proposal`, `brand_at_proposal` and `product_status_at_proposal`. The
client sends none of them: the database copies each out of `vendor_products`
itself, and a table-level assertion refuses a row whose snapshot does not match
the catalogue. A client-supplied snapshot could not survive even if it were sent.

### The header-only write is gone from this path

A new receipt is **never** confirmed with `confirm_receipt_extraction` first.
Writing the header alone would create a receipt that can never acquire products
— the combined RPC answers `CONFLICT` to every later attempt to top one up. The
header-only method remains in the repository for reading historical rows and for
the tests that describe them, and is unreachable from the review screen.

---

## 4. What the database can answer, and what the screen does

| Outcome | Meaning | Screen |
| --- | --- | --- |
| `CONFIRMED` | This call created the confirmation and the proposal | Success; reads the stored proposal; read-only forever |
| `ALREADY_CONFIRMED` | The identical header and identical ordered list already existed | Success, worded so it never claims a new record; reads the stored proposal |
| `CONFLICT` | Something different is already stored | No retry, no resend; offers a read |
| *unrecognised token* | This build cannot read the answer | **Never** success; treated as uncertain |

### Nothing is ever retried automatically

There is no automatic retry and no polling anywhere around this write. A repeat
cannot duplicate anything — the database answers `ALREADY_CONFIRMED` — but it
remains the person's explicit act, never the app's.

### Double submission is prevented structurally

A submission is editable only while it is `idle`. From the moment a write starts
— and in every state it can reach afterwards — a second submit returns without
touching the repository, the transaction fields refuse edits at the *state*
level (not merely in the widget), and the selection is frozen. The list that is
travelling is a **value snapshot** taken at the tap, so nothing above can change
it mid-flight.

### Slow, and uncertain, are different things

After a fixed delay a pending write shows *"This is taking longer than expected.
Do not submit again."* That timer changes presentation only: it sends nothing,
retries nothing, polls nothing, cancels nothing and fails nothing, and it is
cancelled the moment an answer arrives or the screen closes.

A transport fault, an unreadable reply or an unknown token is **uncertain**: the
write may have committed. The screen claims neither success nor failure, keeps
the submitted snapshot visible, never re-enables the submit control, and offers
one manual **Check receipt status** — a read.

Definite server refusals are separated from uncertainty. A refusal raised inside
the function rolls the whole transaction back, so nothing is stored and the form
is safely handed back with every typed value intact.

---

## 5. The manual status check

Two reads and no write. There is no path from it to any write RPC.

`get_my_receipt_product_proposal` answers first, because rows settle the question
in one round trip. An **empty** proposal is ambiguous by design — it means "no
proposal", "not yours" and "does not exist" alike — so
`get_my_receipt_confirmation` is asked next to tell a header-only receipt from
one with nothing stored at all.

| Result | Screen |
| --- | --- |
| Proposal rows | Immutable submitted proposal; read-only |
| No proposal, confirmation exists | Legacy header-only state; read-only |
| Neither | Editable again — **only** here, with the draft and the chosen products preserved exactly |
| A read failed | Stays uncertain; may be asked again by hand; no polling |

It is guarded against double taps independently of the write guard.

---

## 6. The submitted proposal is immutable

Once a proposal exists, the screen shows what the **database** holds. It is never
rebuilt from the editable selection: that list was a proposal, these rows are the
record.

Each line shows its stored line number, frozen product name and code, frozen
barcode and brand where present, the quantity, and the product's status **at
proposal time**, labelled as such. A summary gives the line count and the total
quantity, both counted from the stored rows.

### Frozen values do not drift

A later rename, rebrand, barcode reassignment, deactivation or un-assignment
changes none of it. The submitted display performs **no current-catalogue
lookup** — the widget receives typed values and has no repository — so today's
catalogue cannot overwrite yesterday's assertion. This is verified against a real
database in §8.

### There is nothing to press

No edit, remove, increment, decrement, search, add, resubmit, correct, replace or
reopen control exists in the submitted state. Those widgets are **absent**, not
disabled, so there is nothing for a stale frame or a queued callback to reach.

### The whole list is judged together

A Claim Reviewer accepts or rejects the **complete** product list. If one line is
wrong, the whole list can be rejected — the copy says so plainly, because it
changes how carefully a person should check before submitting.

Checking the receipt photo itself is a **separate** decision, made on its own. A
verified sale header may exist without accepted products.

Submitting a proposal evaluates no campaign and creates no reward and no coins.
The screen states this.

---

## 7. The legacy header-only state

A receipt confirmed before Phase 1D-B has transaction details and no product
proposal. This is a legal historical state — not a network failure, not a
malformed response, not a pending proposal, not an editable receipt and not a
rejected proposal — and it is presented as exactly that, without an apology and
without inviting anybody to report it.

Products **cannot** be added to it through this flow. A confirmation is immutable
and the combined RPC answers `CONFLICT` to any attempt to top one up, so there is
no backfill, correction, resubmit or reopen control. Such a receipt cannot go
forward for product-based campaign qualification, and no campaign, reward or
coins were created for it.

A distinction worth stating: an empty proposal read *after a write that reported
lines* is **not** treated as this state. The write is the more specific answer,
and telling somebody their receipt was "confirmed without products" seconds after
the database said otherwise would be wrong. That case is reported as "we could
not load the lines", with the confirmation still authoritative.

---

## 8. Verification

### Local synthetic end-to-end

The real repository and RPC data source were driven against a **local** Supabase
stack under a synthetic Sales Staff member's own token, with disposable fixtures
(a Retailer, a Vendor, a shop, an account, three assigned products, five
receipts). Verified:

* one confirmation row, and exactly the expected proposal lines;
* selection order preserved as `line_number` — not catalogue order;
* exact quantities;
* snapshots written **server-side** from a request carrying only `product_id`
  and `quantity`;
* exactly one `RECEIPT_PRODUCTS_PROPOSED` Audit Log per confirmed receipt;
* the identical input answered `ALREADY_CONFIRMED` with no duplicate row and no
  second Audit Log;
* a header-only confirmation read back as zero proposal lines;
* a committed write with a lost reply recovered by the read alone;
* a receipt with nothing stored read back empty;
* after renaming, rebranding, re-barcoding, deactivating and un-assigning a
  product, the stored proposal still read back its proposal-time values while
  the product was genuinely gone from the current catalogue.

Every synthetic row, account and credential was destroyed afterwards by a full
local reset. No fixture identifier, address or password is recorded here or
anywhere in the repository.

### Hosted

**No hosted business write was performed, and no hosted business write RPC was
called.** Hosted migration parity was verified read-only as 64/64, the `receipts`
bucket was confirmed private, and its object count was read as unchanged.

---

## 9. Security boundary

Asserted by source-reading tests, over executable lines only:

* no `.from(`, `.select(`, `.insert(`, `.update(`, `.upsert(` or `.delete(`
  anywhere in the feature — the extraction tables carry RLS with zero policies
  and no privilege for browser roles;
* no Supabase client, RPC name or provider type in any page or widget: widgets
  receive typed values and callbacks;
* a product line declares exactly `product_id` and `quantity`, pinned as a list,
  with fourteen forbidden field names asserted absent;
* the combined request adds exactly one parameter to the header's ten;
* one production call site for the write, and two deliberate, bounded call sites
  for the proposal read;
* no `Timer.periodic` anywhere near the write;
* no path from the status check to any write method.

No SQLSTATE, Postgres message, hint, RPC name, table name, storage path, actor
identity or confirmation id reaches a user-facing sentence. Every message is
chosen by a typed discriminant. The `CONFLICT` branch deliberately identifies
nothing, so a refusal cannot be used to learn about another submission.

---

## 10. Accessibility and layout

* Status is a **word** with an icon — "Submitted", "Selected · line 2" — never
  colour alone.
* Pending, slow and outcome states are live regions, so they are announced as
  they arrive.
* Each proposal line is announced as one sentence: line number, product,
  quantity. The summary is announced as one sentence rather than two orphaned
  numbers.
* Controls that may not fire are absent or carry a null callback and
  `Semantics(enabled: false)` — never a dimmed control that still responds.
* Steppers and destructive controls keep a 48dp target.
* The submitted and legacy states are verified not to overflow at 360/390/900 px
  and at increased text scale, including with very long names and codes.

A pre-existing overflow at 1.6× text scale in `ReceiptReviewStatusPanel` and the
review form's time-field row is **outstanding** and unrelated to this feature;
neither is rendered in the submitted or legacy states.

---

## 11. Next milestone

Claim Reviewer Web: whole-list product **acceptance or rejection**, and the sale
items that follow from it. Nothing in this Flutter feature anticipates that
decision beyond telling a staff member it is coming.
