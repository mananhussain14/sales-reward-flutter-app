# Flutter Vendor Product writes

**Milestone:** Vendor Product management in Flutter — create a product, edit its
mutable fields, and activate or deactivate it.
**Branch:** `feat/flutter-vendor-product-writes`
**Backend:** deployed, and **unchanged by this milestone**. The three write RPCs
shipped with the web catalogue in
`supabase/migrations/20260727210000_vendor_product_catalog_operations.sql`; two of
them were repaired in place — identical signatures, return types, volatility,
security context, `search_path` and grants — by
`supabase/migrations/20260807090000_repair_vendor_product_write_normalization.sql`.
**Backend audit:** `docs/mobile-vendor-product-writes-audit.md` in
`salesreward-admin`.

This milestone adds **no assignment write**, no product deletion, no image, no
pricing, no stock, no reward and no campaign — and no disabled affordance for any
of them. The assigned-Retailer section stays exactly as read-only as it was.

---

## 1. Architecture

An extension of the existing product slice rather than a parallel one. New files
are marked; everything else was already there and was widened.

```
lib/features/products/
├── domain/
│   ├── entities/
│   │   ├── vendor_product_field.dart          NEW  the five fields, as an enum
│   │   ├── vendor_product_input.dart          NEW  normalization + validation
│   │   ├── vendor_product_draft.dart          NEW  the create request
│   │   ├── vendor_product_edit.dart           NEW  the edit request
│   │   └── vendor_product_status_change.dart  NEW  ACTIVE | INACTIVE, as a request
│   └── repositories/
│       ├── vendor_product_repository.dart          + three write methods
│       └── vendor_product_write_result.dart   NEW  success | unconfirmed | failure
├── data/
│   ├── models/vendor_product_write_parsers.dart          NEW
│   ├── datasources/vendor_product_write_rpc_data_source.dart  NEW
│   └── repositories/supabase_vendor_product_repository.dart   + three writes
└── presentation/vendor/
    ├── cubit/
    │   ├── vendor_product_write_notice.dart   NEW  the acknowledgement vocabulary
    │   ├── vendor_product_create_cubit.dart   NEW  + state
    │   ├── vendor_product_edit_cubit.dart     NEW  + state
    │   ├── vendor_product_status_cubit.dart   NEW  + state
    │   └── vendor_product_detail_cubit.dart        + openCreated / refreshDetail
    ├── pages/
    │   ├── vendor_product_create_page.dart    NEW
    │   ├── vendor_product_edit_page.dart      NEW
    │   ├── vendor_products_page.dart               + Add product
    │   └── vendor_product_detail_page.dart         + Edit, status, notices
    └── widgets/
        ├── vendor_product_form_fields.dart    NEW  shared by both forms
        ├── vendor_product_status_action.dart  NEW  the confirmed status action
        ├── vendor_product_write_notices.dart  NEW  safe failure + success alerts
        ├── vendor_product_add_button.dart     NEW
        └── vendor_product_copy.dart                + every write sentence
```

**One repository, not two.** The three writes were added to
`VendorProductRepository` beside the three reads. They share a Vendor derivation,
a selector vocabulary, an id-shape guard and a failure contract, and **every write
is immediately followed by one of the reads** — so a second repository would have
split a single flow across two objects and given those four things two homes.

**Two data sources behind it.** `VendorProductRpcDataSource` (reads) and
`VendorProductWriteRpcDataSource` (writes) stay separate files, because that is
what lets each one's boundary test assert its parameter set *exactly*: the read
source passes `p_product_id` and nothing else, and the write source passes exactly
seven names and no eighth.

**Reads and writes answer different result types.** Reads answer `ReadResult<T>`;
writes answer `VendorProductWriteResult<T>`, which has a third case a read cannot
need. See § 9.

**Shared, not duplicated.** `Failure`, `mapSupabaseError`, `SrTextField`,
`SrButton`, `SrAlert`, `SrSectionCard`, `SrEmptyState`, `SrFailureView`,
`SrPageBody` and the rest of the design system are reused. `SrTextField` gained
`minLines`, `maxLines` and `textCapitalization` — three general parameters, with
single-line behaviour unchanged for every existing caller.

**No `Supabase.instance.client` in presentation**, and no `package:supabase_flutter`
import outside `data/`.

---

## 2. The exact three RPCs

| Operation | Function | Returns |
| --- | --- | --- |
| Create | `public.create_vendor_product(text, text, text, text, text)` | `uuid` |
| Edit | `public.update_vendor_product(uuid, text, text, text, text)` | `void` |
| Status | `public.set_vendor_product_status(uuid, text)` | `void` |

### Create

```
create_vendor_product(
  p_product_code text,
  p_product_name text,
  p_barcode      text default null,
  p_brand        text default null,
  p_description  text default null
) returns uuid
```

Five values, and every one is a product field. There is **no** organization,
tenant, Vendor, auth-user, profile, membership, actor, audit-metadata, role,
permission, initial-status, Retailer or assignment argument — the deployed function
has no parameter for one. The new product's status is `ACTIVE`, decided by the
function; a create writes **no assignment row**; and it writes exactly one
`PRODUCT_CREATED` audit row in the same transaction.

### Edit

```
update_vendor_product(
  p_product_id   uuid,
  p_product_name text,
  p_barcode      text default null,
  p_brand        text default null,
  p_description  text default null
) returns void
```

The id plus the four **mutable display fields**. There is no `p_product_code` and
no status parameter. All four are sent on every save, because the RPC writes all
four — this is a whole-record update, not a patch, which is also what makes
clearing an optional deliberate.

### Status

```
set_vendor_product_status(
  p_product_id uuid,
  p_status     text
) returns void
```

`p_status` is `ACTIVE` or `INACTIVE`, and this client cannot express a third value:
`VendorProductStatusChange` has exactly two members, and the response enum's
forward-compatibility `unknown` is a different type.

### The seven parameter names, and no eighth

`p_product_code` · `p_product_name` · `p_barcode` · `p_brand` · `p_description` ·
`p_product_id` · `p_status`. A boundary test asserts that set exactly, and asserts
per-invoker that create sends no `p_product_id` or `p_status`, that edit sends no
`p_product_code` or `p_status`, and that status sends no product field.

---

## 3. Backend normalization authority

Every rule this client applies is applied again, independently, in PostgreSQL. The
functions re-normalize and re-validate from scratch, and the table's five `CHECK`
constraints plus its two per-Vendor unique indexes are the final authority.

`VendorProductInput` mirrors the deployed expressions so the two **agree**, which
matters more than the validation itself: if they disagreed about what `"sr-100"`
means, a form could report a code as available that the unique index then refuses
as a duplicate.

| Field | Rule |
| --- | --- |
| product code | collapse → trim → **upper-case** |
| product name | collapse → trim |
| brand | collapse → trim; empty becomes `null` |
| barcode | collapse → trim, then **remove spaces and hyphens**; empty becomes `null` |
| description | **trim only** — internal formatting is the author's |

### `String.trim()` is never used, and that is load-bearing

Dart's `trim()` strips the Unicode `White_Space` set, which includes **U+0085 NEXT
LINE**. JavaScript's `\s` does not, and the deployed migration's explicit character
class does not either. Using `trim()` would make Dart quietly stricter than both
other definitions, and the same keystrokes would store one value from the browser
and a different one from this client.

So `VendorProductInput.whitespacePattern` spells out exactly the 25 code points the
migration lists — U+0020, U+0009–U+000D, U+00A0, U+1680, U+2000–U+200A, U+2028,
U+2029, U+202F, U+205F, U+3000, U+FEFF — with `\u` escapes rather than literal
characters, so the source contains no invisible bytes. A test walks every one of
those 25, and asserts that U+0085 is **not** treated as whitespace here while
Dart's own `trim()` does remove it.

`normalize_product_line` (collapse then trim) and `normalize_product_block` (trim
only) are the deployed helper pair; `normalizeLine` and `normalizeBlock` are their
Dart counterparts, and no other normalization exists in this feature.

### Normalization happens once, on submit

Not per keystroke. Raw text is never rewritten under the cursor; a submission
normalizes all five values, validates them, and — if anything is wrong — adopts the
normalized values so a length or shape message describes the string it was computed
from. That is what the web's action does with its submitted `FormData`, for the same
reason.

### And it is never trusted afterwards

The values a screen shows after a write come from `get_vendor_product_detail` and
from nowhere else. Nothing echoes a submitted value as though it were the record.

---

## 4. Mutable and immutable fields

| Field | Required | Max | Unique | Mutable | Clearable |
| --- | --- | --- | --- | --- | --- |
| `product_code` | on create | 64 chars | **per Vendor** | **no** | no |
| `product_name` | yes | 200 chars | no | yes | no |
| `barcode` | no | 8–14 digits | **per Vendor**, where non-null | yes | **yes** |
| `brand` | no | 120 chars | no | yes | **yes** |
| `description` | no | 2000 chars | no | yes | **yes** |

Lengths are counted in **characters**, not bytes: a 200-character name of
multi-byte characters is accepted and 201 is not, matching the backend's `length()`.

### The product code

Administrator-supplied, normalized and upper-cased server-side, and **immutable
after creation** — it is not a parameter of the edit RPC, and a trigger refuses a
direct change. It is the canonical key assignments are made against and a future
receipt-matching step will resolve, so re-keying in place would silently change
what every downstream reference means. A miscoded product is replaced, not renamed.

The shape rule is `^[A-Z0-9][A-Z0-9 ._/-]*$` with no run of two spaces, mirrored
character for character from `vendor_products_code_shape`.

**On the edit screen the code is read-only context**, rendered as a labelled fact
with a lock glyph and a sentence explaining why — not as a disabled input, which
invites a person to try typing and then says nothing when they cannot. It is spoken
as "Product code, read only" so a screen-reader user learns it without discovering
it by failing to edit. `VendorProductEdit` has no field for it, so it cannot be
submitted whatever a caller intends.

### The barcode

**Text throughout, never a number.** `int` would drop a leading zero and a 14-digit
GTIN exceeds what a `double` holds exactly, so either would silently change what a
barcode means. A boundary test asserts no source declares or parses it numerically.

Spaces and hyphens are accepted as typed — a barcode is a number people transcribe
with separators — and stripped on submit, exactly as the deployed function does.
Nothing else is stripped, so a stray letter stays and the shape check refuses it
rather than the field quietly accepting a value the backend would reject. The
keyboard type is `text`, deliberately not a numeric type.

There is **no barcode scanner and no generator**. Nothing in the deployed contract
produces a barcode or a product code — both are typed by an administrator — and a
scan affordance would be a camera integration invented to decorate a form.

### The description

Multi-line, and the newlines survive. The backend trims only its ends and preserves
internal formatting verbatim, because a paragraph break belongs to whoever wrote it,
so Dart collapses nothing. The control grows from 4 to 10 lines with the text.

### Optional means null, never `''`

`null`, `''` and whitespace-only are one thing to the backend — all three store SQL
`NULL` — so all three leave this client as `null`. "Not recorded" is how a null is
*rendered* on the detail screen and is never a value that is stored, and never a
value that seeds a form.

---

## 5. Create flow

Route: **`/vendor/products/new`**, declared **before** the `:productId` route.
go_router matches in declaration order, so with those two reversed this path would
bind `productId = 'new'` and open the detail screen for an id that is not a uuid.
`new` is safe as a literal segment precisely because it can never be 8-4-4-4-12
hexadecimal, so no real product id can be shadowed by it.

There is no web counterpart — the web creates from an inline form on its catalogue
page — so the route is named after what it does. A route rather than an inline form
because a phone cannot show a five-field form and a catalogue at once without one
crowding the other, and because a route is addressable, cancellable and reachable
by browser back.

1. **Add product** on the catalogue header, and again inside the empty state, opens
   the form. `go` rather than `push`, so the catalogue stacks beneath and Cancel or
   browser back return to a list that is still loaded, with no second read.
2. Five fields: code, name, barcode, brand, description. **No status selector, no
   Vendor selector, no Retailer or assignment control, no price, stock, image,
   reward, incentive or campaign field.**
3. Submit normalizes and validates once. Anything wrong stops there and nothing
   leaves the client; focus moves to the first offending control in reading order.
4. `create_vendor_product(...)` → `uuid`.
5. On the returned id, in this order: the detail cubit starts the **canonical read**
   for the new product, the catalogue is invalidated, and the router moves to
   `/vendor/products/<id>`.
6. That screen renders what the backend stored, and acknowledges the create there —
   "Product created", above values that were read back rather than echoed.

The canonical read is started *before* the router moves, so the product screen's own
idempotent `open` recognises it and issues no second call. One write, one read.

**Duplicate submission is impossible.** The control is disabled and shows progress
while the call is in flight, the cubit refuses a second call regardless, and both
terminal phases keep it disabled — there is no server-side idempotency here beyond
the unique index, so a second call with a different code would create a second
product.

---

## 6. Edit flow

Route: **`/vendor/products/:productId/edit`**, nested under the detail route so the
Products destination stays selected and the back gesture pops to the product.

1. **Edit** in the product's page header opens the form.
2. The form is seeded from the **canonical product row**
   `get_vendor_product_detail` returned, and from nothing else. The route
   contributes an **id and no content**, so a link cannot pre-fill a name, a
   barcode, a brand or a description and have it saved back as though a person had
   typed it. Entering from the product screen finds the row already loaded and
   issues no second read; a deep link straight to `/edit` loads it for itself.
3. Four editable fields plus the read-only code. **No status control** — the edit
   RPC never writes `status`.
4. `update_vendor_product(...)` → `void`.
5. On success: the catalogue is invalidated, the canonical detail is re-read, and
   the router returns to the product, which acknowledges the save.

**A no-op save is a success.** A submission in which none of the four values differs
from what is stored writes nothing, moves no `updated_at` and records no audit row —
and returns exactly what a real change returns. The contract makes the two
deliberately indistinguishable so no client has to tell "nothing changed" apart from
"the write failed", so nothing here tries to. In particular **Save is never disabled
on the strength of a local comparison**: that is the one place a client-side
normalization difference could cost somebody their change. The acknowledgement is
worded to be true either way — "Changes saved. This product's details below are the
ones now on record."

**The assigned-Retailer section is not re-read**, and every row stays on screen
unchanged. An edit touches no assignment row.

---

## 7. Status flow

A **section of its own** on the product screen, with its own heading, its own
explanation and its own confirmation — visually separate from Edit. That is not a
layout preference: `update_vendor_product` never writes `status` and
`set_vendor_product_status` never writes the display fields, so a merged control
would suggest that correcting a name and withdrawing a product are one decision,
which is exactly what the contract refuses to let them be.

- An `ACTIVE` product offers **Deactivate**.
- An `INACTIVE` product offers **Activate**.
- A status token this build does not recognise offers **neither**, and the section
  says why. The opposite of an unfamiliar status is not knowable, and guessing
  either way would invent a transition.

Which action is offered is presentation. Whether this caller may take it is decided
in SQL on the call.

### The confirmation

Required in both directions, and every sentence in the deactivation dialog is a
claim the backend proves:

> The product stays in your catalogue and nothing is deleted. Its history and its
> existing Retailer assignments are kept exactly as they are.
>
> While it is inactive it cannot be assigned to a Retailer, and Retailers do not see
> it among their assigned products. You can activate it again at any time.

Nothing is claimed about receipts. The backend audit is explicit that no
receipt-matching step exists yet, so the only two effects stated are the two it does
prove: a new assignment is blocked (`55000`), and the product leaves
`list_retailer_assigned_products()`.

Cancelling — including dismissing by tapping outside or by the back gesture — calls
nothing at all: no RPC, no state change, no optimistic flip.

### While it runs, and after

The action is disabled and shows progress; **the whole product stays legible beside
it**. On success the canonical detail is re-read and the catalogue refreshed, and the
visible status changes then and only then.

**Nothing is optimistic.** The status is never flipped ahead of the backend, which is
why a failure leaves the previous status untouched rather than having to undo a
guess — and why the failure notice can truthfully say "so it is unchanged". A
same-status request is an idempotent no-op in SQL, so even a request that got through
twice could not record two decisions.

Deactivation changes **no assignment row**, not even its `updated_at`. Nothing here
writes, removes, re-reads or recounts one.

---

## 8. Canonical detail refresh

The three writes return `uuid`, `void` and `void` — never a product row,
deliberately: a returned row would be a third product shape on top of the list row
and the detail row, and including the assignment counts would couple every product
mutation to the assignment table for no gain.

So `VendorProductDetailCubit` owns the read-after-write, which keeps three write
cubits from each growing their own copy of it:

| After | Call | Then |
| --- | --- | --- |
| create | `openCreated(id)` | a fresh full load, plus a "created" notice |
| edit | `refreshDetail(notice: updated)` | the product row alone, in place |
| status | `refreshDetail(notice: statusChanged)` | the product row alone, in place |

Two properties of `refreshDetail` are load-bearing:

* **The loaded product stays on screen throughout.** A refresh is not a reload:
  blanking a product to re-read one field would make a saved change look like a page
  reset.
* **The assignment rows are not re-read.** A product create, edit or status change
  touches no assignment row — not even its `updated_at`, which the backend's own
  suite asserts — so a second companion call would spend a round trip to learn
  nothing and would replace a good answer for unrelated reasons.

Both assignment counts still come from the **freshly-read product row**. Nothing is
recomputed from the loaded list, and nothing is fabricated after a write.

The catalogue is invalidated by a `refresh()`, which re-reads
`list_vendor_products()`. No row is patched in place.

### The acknowledgement is keyed to its product

A notice carries the product id it is about, and is rendered only while that id is
the one on screen. So "Product created" is a permanently true sentence rather than
one that starts describing whatever the reader opened next. It is dropped when a
different product is opened, on a full retry, and on a session change.

---

## 9. Partial success: a write that landed and a read that did not

This is the case the write result type exists for.

```
sealed VendorProductWriteResult<T>
  VendorProductWriteSuccess<T>(T value)   the write completed, and was understood
  VendorProductWriteUnconfirmed<T>()      the write completed; the answer was not
  VendorProductWriteFailure<T>(Failure)   the write did NOT happen
```

`ReadResult<T>` has two cases because a read either answered or did not, and one
that did not changed nothing. A write is different: it can leave the database
changed while leaving this client unable to describe the change — and the safe
response to those two is **opposite**. One may be retried. The other must never be
retried automatically, or a second product appears.

### The follow-up read failing

Every refusal these functions raise rolls the whole transaction back, so a 2xx means
the row and its audit row are committed. If the canonical re-read then fails:

* the write is still reported as a **success**, with its acknowledgement;
* the product already on screen is **kept** — it is the last thing the backend
  actually said;
* the screen adds "Saved, but this may be out of date" and offers **Reload**;
* the catalogue refresh is attempted regardless.

It never says the save failed, because it did not — and a re-read is not a re-write,
so repeating it cannot double anything.

### A create whose id could not be read

`create_vendor_product` returning success without a value shaped like a uuid means
the product **exists** and this client cannot address it. That is
`VendorProductWriteUnconfirmed`, and the create screen:

* presents it as a **success**, not a failure;
* **removes the Create control**, so no duplicate is invited;
* says plainly *"The product was created, but we could not open it just now. Find it
  in your catalogue — do not create it again, or you may end up with two."*;
* refreshes the catalogue, which is the only authority on what exists, and offers it
  as the way forward.

Nothing retries a succeeded create, automatically or through a re-armed button. A
second call would either duplicate the product or be refused by the unique index as
a duplicate code, and neither is a useful thing to do to somebody who has already
succeeded.

### An unexpected body from a `void` write

`null` is the established shape — PostgREST answers `returns void` with an empty
body and the SDK maps that to `null`. A body is a response this build cannot read,
but it is **not** a failure: the transaction is committed. It becomes
`VendorProductWriteUnconfirmed`, the canonical detail is re-read, and the screen says
"This may have been applied" beside the values that were read back — rather than
claiming a save it cannot vouch for, or reporting a failure that would invite a
second write.

---

## 10. RPC response parsing

### Create — a scalar uuid

PostgREST answers a `returns uuid` function with the bare scalar as JSON, so
`client.rpc<Object?>(...)` resolves to a Dart `String`. `parseCreatedProductId`
accepts only an 8-4-4-4-12 hexadecimal string and refuses `null`, `''`, a malformed
uuid, a `List`, a `Map`, an `int`, a `double`, a `bool` and a `Set` — never
unwrapping a list or searching a map for a likely key, because either would be
guessing.

**The offending value never appears in the exception.** A parser reason names only
what was expected, which is what makes those reasons safe to log; a test feeds it a
secret-looking string and asserts the reason and `toString()` carry no part of it.

### Update and status — void

`isVoidWriteResponse` accepts `null` and nothing else. It returns a `bool` rather
than throwing, which is the most important safety decision in that file: see § 9.

Neither write is ever parsed into a product. Nothing constructs a `VendorProductDetail`
from form input anywhere in this feature.

---

## 11. Validation and error mapping

### Client-side, for early feedback only

Required product code (create) and product name; maximum lengths; the code shape
rule; the 8–14-digit barcode shape after separators are removed; whitespace-only
required fields rejected; optional fields freely cleared. Messages are this
application's own words and name no table, column, constraint, function or
SQLSTATE — a test feeds every field an offending value and asserts that.

Appropriate input behaviour: `TextCapitalization.characters` on the code,
`.words` on the name and brand, `.sentences` on the description, a `text` keyboard
on the barcode, `TextInputAction.next` between single-line fields and `.newline` on
the description, and **no autofill hints anywhere** — product catalogue data has no
correspondence to anything a browser or keyboard has stored about the person typing
it, and offering one would invite an address into a field with a strict shape.

### Backend classification, by SQLSTATE

`mapVendorProductWriteError` delegates the whole SQLSTATE decision to the shared
`mapSupabaseError` and adds exactly one thing: for `23505` only, which field the
duplicate belongs to.

| SQLSTATE / error | `Failure` | Screen |
| --- | --- | --- |
| `42501` | `DeniedFailure` | one generic "That is not available" |
| `23514` | `InvalidFailure` (no field) | generic "Check these details" |
| `23505` + code literal | `DuplicateFailure(field: productCode)` | under the code field |
| `23505` + barcode literal | `DuplicateFailure(field: barcode)` | under the barcode field |
| `23505`, unrecognised | `DuplicateFailure()` | form-level, deliberately unspecific |
| `AuthException` | `UnauthenticatedFailure` | "Your session has ended" |
| anything else, incl. transport | `UnavailableFailure` | retryable "That did not go through" |
| `22P02` (malformed uuid) | never reaches the wire — refused locally | — |

`42501` is **one** wording for an unauthorized caller, a product that does not
exist, and a product belonging to another Vendor. The backend refuses all three
byte-identically, precisely so an id sweep reveals neither the existence nor the size
of another Vendor's catalogue, and a client that told them apart would hand that
oracle back. It names no permission.

`23514` is generic and carries **no field**. The backend's five validation messages
are English prose this client does not parse, and anything a person can act on has
already been reported by this app's own checks against the same rules.

`55000` cannot arise from these three writes — it belongs to the assignment
functions — but it is classified honestly as `NotReadyFailure` rather than folded
into a wording it does not have.

**No backend text is ever rendered.** A boundary test asserts no presentation source
reaches for `.message`, `error.toString`, `PostgrestException` or `AuthException`.

---

## 12. Duplicate handling

The deployed contract discriminates a duplicate product code from a duplicate
barcode by **one of two fixed message literals and by nothing else**: both raise
`23505`, and there is no separate code, no error field and no column name in the
response. The backend's own static suite pins both strings, and the web's
`classifyWriteError` matches the same two.

So this client matches them too, and confines the dependency to a few lines in
`vendor_product_write_parsers.dart`:

* the match is a `contains` against a literal defined in that file, never a parse of
  the backend's wording;
* an **unrecognised** duplicate degrades to a duplicate with no field hint, exactly
  as the web's does, rather than being echoed or guessed at;
* **the message never travels onward.** What leaves is
  `DuplicateFailure(field: …)` — a client-side *form-field key*, `productCode`
  rather than `product_code` — and the screen's own sentence is chosen from it.

The two sentences:

- "A product with this code already exists."
- "A product with this barcode already exists."

Both are safe precisely because the two unique indexes are scoped **per Vendor**:
each describes the reader's own catalogue, and neither can reveal that somebody else
uses the same value. The same code and the same barcode are legitimately available
to every other Vendor, and nothing here hints otherwise — a test asserts neither
sentence contains "Vendor", "another", "organization" or "tenant".

A boundary test asserts the literals appear in exactly one file, and that the only
other files mentioning "already exists" are the two holding this application's own
sentences.

---

## 13. Authorization and tenant isolation

All three RPCs derive the trusted Vendor from `auth.uid()` through
`get_vendor_super_admin_context()` — with the shipped lowest-organization-id
tie-break — and then require the specific product-management permission through
`has_organization_permission`. That permission is a **different** one from the read
permission, a split enforced entirely in SQL.

Flutter never inspects, sends, displays or infers that permission code. It appears
nowhere in `lib/`, and a boundary test asserts it. Authority is never derived from
local product data, from an organization name, from an email, from token metadata or
from a status.

Every product id is an **address, never an authorization**. The row is matched on
both its own id and the derived Vendor, so an unknown id, another Vendor's id and a
null one are refused byte-identically and arrive as one generic denial.

**A malformed uuid never reaches the wire.** It would come back as `22P02` from the
type system — raised before the function body runs, and therefore before any
authorization check — which is neither an authorization answer nor an outage, and
would surface as a database fault offering a retry that could never succeed. So the
repository refuses it locally and answers `DeniedFailure`: exactly what the backend
answers for an id naming no product, saying nothing about whether any product
exists. In the shipped flow that branch is unreachable — a form is only rendered
after a canonical read returned a row — so it is defence in depth at the boundary
that talks to PostgREST.

The Vendor route guards remain **presentation guards only**. Supabase is the final
authority, and a refusal arrives as one safe wording whatever the guard did.

---

## 14. Assignment boundary

Product-to-Retailer assignment writes are **out of scope**, and the code says so
structurally rather than by comment:

* `assign_vendor_product_to_retailer` and
  `unassign_vendor_product_from_retailer` are named nowhere in `lib/`;
* the repository declares exactly three write methods, and a boundary test asserts
  that set plus the absence of `deleteProduct`, `assignRetailer`,
  `unassignRetailer`, `withdrawFromRetailer`, `setAssignmentStatus` and
  `uploadProductImage` under any spelling;
* there is no Assign, Remove, Activate-assignment, Deactivate-assignment or bulk
  control, no assignment checkbox, and no disabled one;
* no route beneath a product addresses an assignment.

They are gated on a **separate permission** and are a separate milestone. Product
create, edit and status neither create, read nor mutate an assignment row — the
backend's suite proves a full create → edit → deactivate → activate lifecycle
produces zero of them — so the existing assigned-Retailer list stays read-only and
is not even re-read after a write.

No assignment count is ever fabricated after a write: both figures come from the
canonical product row.

---

## 15. Audit behaviour

Each successful write inserts its own audit row — `PRODUCT_CREATED`,
`PRODUCT_UPDATED`, `PRODUCT_ACTIVATED`, `PRODUCT_DEACTIVATED` — inside the same
transaction as the mutation.

Flutter writes **no** audit row, calls no audit function, reads no `audit_logs`
table for this purpose, and sends no actor, organization or metadata. A boundary
test asserts `'audit_logs'` and `.insert(` appear nowhere in the feature.

**No Audit Logs change was needed.** The shipped Vendor Audit Logs screen already
maps all four action codes under `VENDOR_PRODUCT` in
`vendor_audit_log_labels.dart` — "Product created", "Product updated", "Product
activated", "Product deactivated" — and resolves the display name from
`metadata->>'product_name'`. Nothing was added, relabelled or reordered there, and
its existing tests continue to pin those four.

A no-op edit and a no-op status change write **no** audit row, which is what stops a
double tap recording two decisions for one.

---

## 16. Session isolation

The Vendor shell now owns and clears **fourteen** cubits, three of them new. On
logout, a direct `Vendor A → Vendor B` switch, an organization change, a move to
another portal role, and a denied, unavailable or invalidated session, the write
cubits are cleared alongside the read cubits — through the same identity-comparing
`BlocListener` on the existing `SessionBloc`. **No second auth-state listener was
added.**

What goes:

- the create form's five values, its validation, its progress, its refusals, its
  success and the created product's id;
- the edit form's seeded values, its read-only code, its validation, its progress
  and its refusals;
- any pending status decision, its progress and its error;
- the detail cubit's write acknowledgement, its refresh progress and its stale-data
  warning.

**In-flight writes are invalidated, not merely ignored.** Each cubit holds a request
token that `clear()` advances first, so a create, edit, status change or follow-up
detail read already on its way for the previous identity is dropped on arrival. That
is stronger than the read cubits need: a stale *read* is a disclosure problem, while
a stale *write answer* could report a duplicate against Vendor A's catalogue into
Vendor B's session, acknowledge a save B never made, or navigate B to A's product.
Tests assert each of those three cases directly.

An **identical** effective identity — the shape a same-user token refresh takes —
compares equal and is ignored, so it costs no clear and never resets an active form.

---

## 17. Responsive UI and accessibility

Both forms use `SrPageBody` with `SrSpacing.formMaxWidth`, so a single column of
controls is capped rather than stretched across a desktop browser. Fields stack on
every width; the action row stacks with full-width buttons below `sm` and sits
right-aligned above it, with the primary action first on narrow screens and last on
wide ones. The confirmation dialog's content scrolls, so its several sentences stay
readable on a small phone and under large text scaling.

Verified with no overflow at 360×640, 390×844, 900×1000 and 1280×900, in light and
dark, and at 2× text scale for the dialog.

Accessibility:

- **Add product**, **Edit**, **Save changes**, **Create product**, **Cancel**,
  **Activate**, **Deactivate**, **Reload** and both Back actions each carry an
  explicit spoken label; the destructive-sounding ones say that confirmation follows.
- Page headings are marked as headers.
- Every field carries its own visible label; requirement is a **visible asterisk**
  and optional fields a **visible "(optional)"** — never colour or placement alone.
- A validation message is text, replacing the field's hint **below** the control, so
  it never displaces what is being typed and grows only downward.
- Focus moves to the first offending control after a refused submission, in reading
  order, and only when that field has changed — so it cannot steal focus back from
  somebody who has already moved on.
- The immutable code is spoken as "Product code, read only", with the reason.
- Every alert is a live region: `role="alert"` for errors and `role="status"`
  otherwise, through the shared `SrAlert`.
- Progress is a label beside a spinner, never a colour change, and never an invented
  percentage.

There are **no snackbars or toasts** anywhere, matching the product: all feedback is
inline and in place.

---

## 18. Manual hosted verification

Against the hosted project, with the deployed migrations through
`20260807090000`. Use a disposable product code, and **do not modify production
assignment rows** — this milestone changes none, and no step below asks you to.

```
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

1. Start Flutter web with the command above.
2. Sign in as a Vendor Super Admin.
3. Open **Products** from the drawer. Confirm the catalogue loads and that
   **Add product** is offered.
4. Create a product: type a code in lower case with surrounding spaces, a name with
   doubled internal spaces, a barcode written with spaces and hyphens, a brand, and
   a multi-paragraph description. Press **Create product**.
5. Confirm the screen moves to the product's own detail page and that the values
   shown are the **normalized** ones — code upper-cased, name collapsed, barcode
   digits only — and that the description's paragraph break survived.
6. Confirm the new product's status reads **Active**.
7. Confirm the assigned-Retailer section reads "Not assigned to any Retailer" and
   that the counts read "No Retailer assignments".
8. Press **Edit**. Change the name, the barcode, the brand and the description.
   Confirm the values shown after saving are the ones read back.
9. Edit again and **clear** the barcode, brand and description. Confirm all three
   read "Not recorded" afterwards.
10. Confirm the **product code** is read-only on the edit screen and explains why.
11. Press **Deactivate**, read the confirmation, and confirm it.
12. Confirm the product is still listed, its status reads **Inactive**, and the
    assigned-Retailer section and both counts are unchanged.
13. Press **Activate** and confirm the status returns to **Active**.
14. Return to **Products** and confirm the catalogue reflects the new product, the
    edited values and the status changes.
15. Open **Audit Logs** and confirm "Product created", "Product updated", "Product
    activated" and "Product deactivated" appear for it, named by the product.
16. Create a second product reusing the first one's **code**. Confirm the message
    appears under the *code* field and reads "A product with this code already
    exists."
17. Create a third product reusing the first one's **barcode**. Confirm the message
    appears under the *barcode* field instead.
18. Create a product whose code and name are typed with leading and trailing spaces
    and a tab. Confirm it is accepted and stored trimmed — **no** database error
    text appears.
19. Sign out. Sign back in and confirm the create form is empty, no edit form is
    seeded, and no write acknowledgement is on screen.
20. Sign in as a Retailer Owner, a Retailer Manager and Sales Staff in turn and type
    `/vendor/products/new` and `/vendor/products/<id>/edit`. Confirm each is sent to
    their own home and that neither form renders.

No credential, token, UUID or private screenshot belongs in this document or in any
record of the run.

---

## 19. Security boundary

Asserted by `test/security/vendor_product_boundary_test.dart`, which reads the
source rather than exercising it:

- no service-role or secret key, no `String.fromEnvironment`, no
  `Platform.environment`, no hardcoded credential;
- `dart_defines.json` is git-ignored and **not tracked**;
- no `.from(`, `.select(`, `.insert(`, `.update(`, `.upsert(`, `.delete(` anywhere in
  the feature — `vendor_products` and `vendor_product_retailer_assignments` are
  default-deny with zero RLS policies, so a direct write would not merely be poor
  layering, it would not work;
- no `'audit_logs'` write, and no `auth.users` read under any spelling;
- exactly three write RPC names, exactly seven parameter names, and no eighth;
- no caller-identity, organization, tenant, actor, audit-metadata, role or
  permission argument on any call;
- `p_product_code` absent from the edit payload and from `VendorProductEdit`;
  `p_status` absent from both the create and the edit payload; no status, tenant,
  price, stock, image or reward field on `VendorProductDraft`;
- no product deletion, no assignment write, and no assignment RPC named;
- a barcode is never declared or parsed as a number;
- the two pinned duplicate literals live in exactly one file;
- no presentation source reads an error's message;
- no permission or role code, no backend function name, no SQLSTATE, no hardcoded
  uuid, and no status literal outside the domain enums;
- presentation never touches Supabase or HTTP, the domain layer imports no SDK, and
  no cubit state holds a raw map or a `dynamic`.

Stale-session leakage is covered behaviourally rather than statically: three cubit
tests and one widget test assert that a write answer landing after `clear()` cannot
populate, acknowledge or navigate the new session.

---

## 20. Known limitations

1. **Product assignments remain read-only.** Assign and withdraw are gated on a
   separate permission and are a separate milestone. The two address spaces —
   `relationship_id` on the read, `retailer_organization_id` on the write — should be
   reconciled when that milestone is planned.
2. **Product deletion is unavailable.** No control, action, RPC or `DELETE`
   statement exists anywhere in the product, by design.
3. **Product images are unavailable.** No image column, bucket or storage path
   exists.
4. **No price, inventory or stock**, in the schema or here.
5. **No reward or incentive values**, no campaigns, no coins, no payouts.
6. **Create returns only a uuid.** There is no returned product row.
7. **Edit and status return `void`**, so a real change and a no-op are
   indistinguishable — deliberately, and this client treats both as success.
8. **The product detail must be re-fetched after every write.** One extra indexed
   primary-key read per mutation.
9. **The duplicate code-versus-barcode distinction still depends on the existing
   pinned backend message contract.** Two English literals, matched in one file. A
   backend that reworded either would degrade this client to an unattributed
   duplicate rather than mis-attribute one, and the backend's own static tests pin
   both strings.
10. **No optimistic locking.** The backend uses last-write-wins; `updated_at` is a
    trigger-maintained timestamp rather than a version, and no
    `expected_updated_at` exists to send. Two administrators editing the same
    product in the same seconds is not detected.
11. **Multi-Vendor callers retain the lowest-organization-id tie-break.** A caller
    who is a Super Admin of two Vendors writes to the lowest-id one,
    deterministically — the shipped behaviour of every other Vendor RPC and of the
    web.
12. **The product code cannot be corrected.** A miscoded product is replaced.
13. **A status token this build does not recognise offers no status action**, and
    says so, rather than guessing a transition.
14. **All assignment writes remain a separate future milestone.**

---

## 21. Tests

Added, all passing:

| File | Tests |
| --- | --- |
| `test/features/products/vendor_product_input_test.dart` | 66 |
| `test/features/products/vendor_product_write_parsers_test.dart` | 24 |
| `test/features/products/vendor_product_write_repository_test.dart` | 39 |
| `test/features/products/vendor_product_create_cubit_test.dart` | 39 |
| `test/features/products/vendor_product_edit_cubit_test.dart` | 36 |
| `test/features/products/vendor_product_status_cubit_test.dart` | 21 |
| `test/features/products/vendor_product_write_flow_test.dart` | 117 |

Extended:

- `vendor_product_detail_cubit_test.dart` — a new group of 18 covering
  `openCreated`, `refreshDetail`, notice lifetime, the assignment rows *not* being
  re-read, the partial-success path and stale-session drops.
- `test/security/vendor_product_boundary_test.dart` — the "this milestone writes
  nothing" group replaced by a 15-test write-boundary group, and every basename
  match anchored with a leading `/` (a latent bug: `supabase_vendor_product_
  repository.dart` also `endsWith` `vendor_product_repository.dart`).
- `vendor_product_flow_test.dart` — the two "no write affordance" tests rewritten to
  pin the exact allowed controls.
- `test/support/vendor_product_fakes.dart` — write recording, scriptable write
  results, manual completion for each write, a created-product fixture, and an
  `unusedVendorProductWrites()` helper that fails a read path which writes.

Focused regressions, all passing, run per area after the change:

| Area | Tests |
| --- | --- |
| Products (reads **and** writes) | 661 |
| Users | 299 |
| Roles | 238 |
| Retailers | 195 |
| Receipts | 181 |
| Audit Logs | 151 |
| Company / profile | 143 |
| Dashboard | 138 |
| Vendor routing, shells and session isolation (`test/app`) | 131 |
| Security boundaries (`test/security`) | 327 |
| Design system (`test/core`) | 57 |

Every existing product **read** test — list, search, filter, detail, assignments,
malformed route, session isolation and logout clearing — continues to pass
unchanged, except the two "no write affordance" tests, which were rewritten to pin
the exact set of controls that now exists.

**Repository totals: 2,213 → 2,585 tests, all passing.**
