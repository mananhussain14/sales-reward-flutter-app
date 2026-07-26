# Flutter Vendor Product-to-Retailer assignment management

**Milestone:** assign a Product to a connected Retailer, reactivate a withdrawn
assignment, and withdraw an active one — from the Vendor Product detail screen.
**Branch:** `feat/flutter-vendor-product-assignment-writes`
**Backend:** deployed, and **unchanged by this milestone**. Both write RPCs
shipped with the web catalogue in
`supabase/migrations/20260727210000_vendor_product_catalog_operations.sql` and
were reused verbatim — no migration, no new function, no modified function — by
the backend milestone that specified them for this client.
**Backend audit:** `docs/mobile-vendor-product-assignment-writes-audit.md` in
`salesreward-admin`; contract entries V-16a, V-17 and V-18 in
`docs/mobile-backend-contract.md`.

This milestone adds **no assignment deletion**, no bulk assignment, no assignment
notes, no assignment-level pricing, no effective-date scheduling and no disabled
affordance for any of them. It changes no Product record, no Retailer
organization and no Vendor–Retailer relationship.

---

## 1. Architecture

An extension of the existing product slice rather than a parallel assignment
feature. New files are marked; everything else was already there and was
widened.

```
lib/features/products/
├── domain/
│   ├── entities/
│   │   ├── vendor_product_assignment_action.dart     NEW  assign | reactivate | withdraw
│   │   ├── vendor_product_assignment_request.dart    NEW  the two-address payload
│   │   ├── vendor_product_assignment_candidate.dart  NEW  the choice + its composition
│   │   └── vendor_product_assigned_retailer.dart          `assignedAt` doc corrected
│   └── repositories/
│       └── vendor_product_repository.dart                 + assignRetailer / withdrawRetailer
├── data/
│   ├── datasources/
│   │   └── vendor_product_assignment_rpc_data_source.dart NEW  the two RPCs, named once
│   └── repositories/
│       └── supabase_vendor_product_repository.dart        + the two writes
└── presentation/vendor/
    ├── cubit/
    │   ├── vendor_product_assignment_cubit.dart      NEW  + vendor_product_assignment_state.dart
    │   ├── vendor_product_write_notice.dart               + four members
    │   ├── vendor_product_detail_cubit.dart               + refreshAfterAssignment / reloadCanonical
    │   └── vendor_product_detail_state.dart               + refreshIncludesAssignments
    ├── pages/
    │   └── vendor_product_detail_page.dart                + the assignment section's controls
    └── widgets/
        ├── vendor_product_assign_retailer_dialog.dart     NEW  the Retailer picker
        ├── vendor_product_assignment_action.dart          NEW  the per-row control + its rule
        ├── vendor_product_assignment_confirmations.dart   NEW  the three confirmations
        ├── vendor_product_assignment_tile.dart            + an action slot
        ├── vendor_product_write_notices.dart              + the assignment failure alert
        └── vendor_product_copy.dart                       + every assignment sentence

lib/app/
├── di/injector.dart                    + the assignment data source
└── shells/vendor/vendor_shell.dart     + the assignment cubit, provided and cleared
```

**Why a third data source.** The two assignment functions are gated on
`PRODUCT_RETAILER_ASSIGN` and take two `uuid` addresses; the three
Product-record functions are gated on `PRODUCTS_MANAGE` and take Product fields.
Two entitlements, two payload vocabularies, two files — so each one's boundary
test can assert its parameter set exactly, and a parameter cannot cross between
them by accident.

**Why one repository.** All eight operations share a Vendor derivation, an
id-shape guard and a failure contract, and every write is immediately followed by
one of the reads — so a caller would have needed both halves anyway.

**Why a separate cubit.** Folding assignment into the status cubit would model
two independent entitlements as one, and a screen that inferred "may edit this
Product, therefore may assign it" would assert something the database
contradicts.

---

## 2. Deployed RPC signatures

Both are reused unchanged. Neither is new.

```sql
public.assign_vendor_product_to_retailer(
  p_product_id               uuid,
  p_retailer_organization_id uuid
) returns void

public.unassign_vendor_product_from_retailer(
  p_product_id               uuid,
  p_retailer_organization_id uuid
) returns void
```

### The exact parameter maps this client sends

| Operation | RPC | Parameters |
| --- | --- | --- |
| Assign **and** reactivate | `assign_vendor_product_to_retailer` | `{p_product_id, p_retailer_organization_id}` |
| Withdraw | `unassign_vendor_product_from_retailer` | `{p_product_id, p_retailer_organization_id}` |

Two keys each, and there is no third. **Not sent, and not expressible:** Vendor
organization id, tenant id, auth user id, profile id, membership id,
**relationship id**, assignment id, role code, permission code, actor id, audit
metadata, assignment status, note, effective date, price, quantity, idempotency
key. `VendorProductAssignmentRequest` has exactly two fields, so a request object
cannot carry any of them; `test/security/vendor_product_boundary_test.dart`
asserts the field set, the parameter set and the colon count of each invoker
body.

The Vendor is derived server-side from `auth.uid()` through
`get_vendor_super_admin_context()`, and both ids are then matched against **that**
derived Vendor. Holding either id grants nothing.

---

## 3. The permission split

| | `PRODUCTS_MANAGE` | `PRODUCT_RETAILER_ASSIGN` |
| --- | --- | --- |
| `create_vendor_product` | required | — |
| `update_vendor_product` | required | — |
| `set_vendor_product_status` | required | — |
| `assign_vendor_product_to_retailer` | — | **required** |
| `unassign_vendor_product_from_retailer` | — | **required** |

The backend verified this by removing each seeded mapping in turn inside a pgTAP
transaction: `PRODUCTS_MANAGE` alone does **not** grant assignment, and
`PRODUCT_RETAILER_ASSIGN` alone **is** sufficient for both writes. `PRODUCTS_READ`
gates neither.

**Flutter never names, sends, inspects or displays either code.** It calls the
function and handles the refusal. Nothing on the Product screen infers assignment
authority from the presence of the Edit or Activate controls, and the route
guards remain presentation guards only — Supabase decides again on every call.

---

## 4. Eligibility

### Product

| Operation | Product must be `ACTIVE` |
| --- | --- |
| Assign (new row) | **yes** — otherwise `55000` |
| Reactivate (existing `INACTIVE` row) | **yes** — same gate, same call |
| Withdraw | **no** |

The Product's status is one fact about the whole screen, so it is checked once
and explained once, above the list, rather than repeated against every Retailer.
An `INACTIVE` Product hides the **Assign Retailer** control and every
**Reactivate**, replacing them with
`VendorProductCopy.assignUnavailableInactive`; **Withdraw stays available**,
because the withdrawal function deliberately requires no status to be active. A
status token this build does not recognise offers nothing and says so.

### Retailer and relationship

| Operation | Retailer organization `ACTIVE` | `vendor_retailers` row `ACTIVE` |
| --- | --- | --- |
| Assign / reactivate | **yes** | **yes** |
| Withdraw | no | the row must **exist**, but need not be active |

That asymmetry is deliberate: a Vendor must be able to withdraw a Product from a
Retailer it has since suspended, which is exactly when withdrawal matters most,
and a status gate on withdrawal would strand historical assignments as
permanently un-endable.

The full deployed matrix (audit § 5) is mirrored, not extended:

| Product | Retailer org | Relationship | create | activate | deactivate |
|---|---|---|---|---|---|
| ACTIVE | ACTIVE | ACTIVE | allowed | allowed | allowed |
| ACTIVE | ACTIVE | SUSPENDED / DEACTIVATED | `42501` | `42501` | allowed |
| ACTIVE | SUSPENDED / DEACTIVATED | ACTIVE | `42501` | `42501` | allowed |
| INACTIVE | any | any | `55000` | `55000` | allowed |
| any | not this Vendor's | — | `42501` | `42501` | `42501` |

Every eligibility test in this client is a **positive** test against `active`, so
a status token a future backend adds can never reach "eligible" by failing to
match something else.

---

## 5. Assign, reactivate and withdraw semantics

### Assign and reactivate are one call

`assign_vendor_product_to_retailer` inserts when no row exists for the pairing
and flips an existing `INACTIVE` row back to `ACTIVE`.
`vendor_product_retailer_assign_unique_idx` is UNIQUE and **unpartial**, so there
is one row per (Product, Retailer) pairing **for all time** and a
withdraw-then-assign cycle reuses it rather than accumulating a second history
row. Duplicates are structurally impossible.

Assigning a pairing that is already `ACTIVE` is a **silent backend no-op** — no
row version written, no audit row — and returns normally. This client treats it
as an ordinary success, indistinguishably, because the contract deliberately
makes it so.

The two are separate members of `VendorProductAssignmentAction` only because they
are different **sentences to a reader**; `isWithdrawal` is the only thing the
data layer asks of the type, and it is `false` for both.

### Withdraw is not deletion

`unassign_vendor_product_from_retailer` sets `status = 'INACTIVE'`. The row
survives, stays returned by `list_vendor_product_assigned_retailers`, and stays
counted by `assignment_count`. Neither deployed function contains a `DELETE` or a
`TRUNCATE`, no delete RPC exists in the schema, and neither browser role holds
`DELETE` on the table.

Withdrawing an already-`INACTIVE` pairing — or one that never existed — is a
silent no-op that **creates no row**, so "no row" and "`INACTIVE` row" stay
distinct.

### `assigned_at`

| Operation | `assigned_at` | `updated_at` |
| --- | --- | --- |
| Assign (new row) | set to now | set to now |
| **Reactivate** | **overwritten with now** | moves |
| **Withdraw** | **preserved** | moves |
| No-op (either direction) | unchanged | unchanged |

**`assigned_at` is when the CURRENT assignment began — never when the pairing was
first created.** The pairing's full history is not recoverable from the
assignment row; it lives in the audit log, which retains one entry per real
transition. Nothing in this client labels or speaks the value as a
first-assignment date, and
`VendorProductCopy.reactivateConfirmBody` states the consequence **before** it
happens rather than leaving a reader to notice a date that moved.

### `assignment_updated_at`

The row's own `updated_at`, maintained by the `set_updated_at` trigger. It moves
only on a **real** transition, so a no-op leaves it alone. There is no
`withdrawn_at` column anywhere in the schema, so none is invented: the value is
labelled *Assignment last updated* and is never read as a status, not even on an
`INACTIVE` row where it happens to be the moment of withdrawal.

---

## 6. Canonical refresh after every successful write

Both RPCs return `void`, so the client re-reads. `VendorProductAssignmentCubit`
does not perform that re-read itself — it reports through
`onAssignmentWritten`, which the Vendor shell wires to:

1. `VendorProductDetailCubit.refreshAfterAssignment(notice:)`, which issues
   * `get_vendor_product_detail(p_product_id)` — status, `assignment_count`,
     `active_assignment_count`, `updated_at`;
   * then, **only after a row comes back**,
     `list_vendor_product_assigned_retailers(p_product_id)`;
2. `VendorProductListCubit.refresh()` — the catalogue, whose
   `active_assignment_count` moved too.

The detail read goes first for the same reason it does on the initial load: the
assignment read answers an empty list for a genuinely unassigned Product **and**
for an id this caller cannot address, indistinguishably, and zero rows from the
detail read is what tells those apart.

**The two answers are applied in ONE emission**, so a count and the rows it
describes are never rendered a frame apart.

**Nothing is optimistic.** No assignment row is inserted, removed or re-statused
locally, no count is adjusted, and no date is computed from the moment a call
returned. The loaded Product stays on screen throughout — a refresh is not a
reload, and blanking a Product to re-read one field would make a saved change
look like a page reset.

The candidate list is dropped when a transition settles: it described eligibility
*before* the write, and a reopened picker asks again.

---

## 7. Partial success

The write can succeed while one or both canonical reads fail. That is modelled
explicitly, and it is never reported as a failed write.

| What failed | What is kept | What is said |
| --- | --- | --- |
| `get_vendor_product_detail` | the Product on screen **and** its assignment rows | *Saved, but this may be out of date* + **Reload** |
| `list_vendor_product_assigned_retailers` | the fresh Product row **and** the previous assignment rows | the same, worded for the list and the counts |
| the catalogue refresh | the loaded catalogue | the catalogue's own existing stale-list notice |

Rules, all asserted:

* the mutation acknowledgement **survives** the failed read;
* the existing rows are kept — replacing a real history with an empty one would
  make ending one assignment look like erasing every assignment;
* the assignment section is **not** degraded to its failure state; the whole
  screen is marked stale instead, because the rows on it are real;
* **Reload** repeats the scope that failed (`refreshIncludesAssignments` records
  it), and re-reads only — it never re-attempts the write;
* nothing retries the mutation automatically, so a repeated write cannot create a
  duplicate assignment.

### The unconfirmed case

A 2xx whose body is not the empty one PostgREST returns for `returns void`
becomes `VendorProductWriteUnconfirmed`. The transaction committed — both
functions raise rather than return on every refusal — so it is a success in a
quieter voice: *This may have been applied*, pointing at the re-read values, and
**never retried**. A repeated assign of a pairing that is now `ACTIVE` would be a
harmless no-op, but a repeated *withdraw* after somebody else reactivated the
pairing would undo their work.

---

## 8. Candidate-Retailer composition

### The source, and why it is the smallest safe one

Two already-deployed reads, and **no third call**:

* **`list_vendor_retailers()`** — the shipped Vendor Retailer directory, read
  through the existing `VendorRetailerRepository`. It is the only honest answer
  to "which Retailers may this Product be assigned to": it is the same
  `vendor_retailers` set the write reaches a Retailer through, scoped to the
  derived Vendor in SQL, and it carries both statuses the assign gate consults.
* **`list_vendor_product_assigned_retailers(p_product_id)`** — already loaded for
  the Product screen and **passed in**, not re-read, so the picker cannot
  disagree with the history underneath it. It is the only thing that can
  distinguish *never assigned* from *assigned and withdrawn*.

No table is read. No per-Retailer eligibility probe is issued — that would be an
N+1 over a question the backend answers inside the write anyway. The directory is
re-read **each time the picker opens**, because eligibility is exactly what goes
stale.

### The five states

| State | Condition | Offered |
| --- | --- | --- |
| `assignable` | no assignment row; Retailer org and relationship both `ACTIVE` | **Assign** |
| `reactivatable` | `INACTIVE` row; Retailer org and relationship both `ACTIVE` | **Reactivate** |
| `alreadyAssigned` | an `ACTIVE` row exists | nothing — a repeat is a backend no-op |
| `ineligible` | Retailer org or relationship not `ACTIVE`, or an unrecognised assignment status | nothing, with a neutral explanation |
| `relationshipUnavailable` | an assignment row whose Retailer is absent from the directory | nothing, with its own explanation |

An **active assignment outranks every other consideration**: a `SUSPENDED`
Retailer holding an active assignment reads as `alreadyAssigned`, because that is
a real, reachable state and a control there would spend a call on nothing.

### Completeness, de-duplication and ordering

* Every directory Retailer appears, **including ineligible ones** — a person
  looking for a Retailer that is simply absent learns nothing; one who finds it
  with a reason learns why.
* Every historical pairing appears, **including one the directory no longer
  contains** — dropping it would make the picker disagree with the history below.
* At most one candidate per `retailer_organization_id`, guarded on the id itself.
* Ordered by `retailer_name`, then `retailer_organization_id` — the same total
  order both backend reads use, so two Retailers sharing a name cannot swap
  places between requests. The composed list is unmodifiable.
* Search matches the **name** only, case-insensitively, over the complete trusted
  answer; nothing typed is sent anywhere. It never matches an identifier, so a
  Retailer cannot be selected by pasting an address.

**`VendorProductAssignmentCandidate` has no relationship-id field**, so a
selection made from one cannot send a relationship id even by mistake. No uuid is
displayed anywhere on the picker.

### It is a hint, never an authorization

The backend re-decides eligibility inside the write, under row locks, against
state that may have moved since these values were read — and it is entitled to
refuse a selection this client called `assignable`. That is the contract working:
the database is the authority and the client is a convenience.

---

## 9. Error mapping

Classified by SQLSTATE alone, in `mapSupabaseError`. These two functions accept
**no text input at all**, so there is no duplicate to attribute to a form field
and no message literal is read anywhere on this path.

| Backend | `Failure` | Shown |
| --- | --- | --- |
| `55000` — ineligible Product | `NotReadyFailure` | *This Product cannot be assigned right now* / *Activate this product before assigning it to a Retailer.* |
| `42501` — unauthorized caller, unknown / foreign / null Product, unknown / foreign / suspended / deactivated / unrelated Retailer, missing relationship | `DeniedFailure` — **one wording for all of them** | *That is not available* / *You do not have access to manage this product's assignments, or this Retailer is not currently eligible.* |
| `23505` — the uniqueness race (unreachable in practice) | `DuplicateFailure` | *The assignment is no longer available* |
| `AuthException` | `UnauthenticatedFailure` | *Your session has ended* |
| transport fault, unrecognised SQLSTATE | `UnavailableFailure` | *That did not go through* |
| malformed Product **or** Retailer id | `DeniedFailure`, decided **locally** | as `42501` above |
| malformed `void` response after a 2xx | `VendorProductWriteUnconfirmed` | *This may have been applied* |
| a canonical read that failed after a successful write | `refreshFailure` | *Saved, but this may be out of date* + **Reload** |

A malformed uuid is refused before a request leaves the device: put into a `uuid`
parameter it would come back as a `22P02` cast error raised *before* the function
body runs and therefore before any authorization check, which is neither an
authorization answer nor an outage. Answering it as `DeniedFailure` adds it to
the set the backend already answers byte-identically, and says nothing about
whether anything exists.

**No raw backend text reaches a screen.** A `Failure` carries a discriminant and
at most a form-field key; no Postgres message, SQLSTATE, table, column, index,
constraint, function, policy, role code or permission code can travel inside one.
No refusal reveals whether a foreign Product or Retailer exists, and suspended,
deactivated, unrelated and nonexistent Retailers all produce the same single
message — so a caller cannot learn that a Retailer exists but is suspended.

---

## 10. Confirmations

All three transitions confirm. A surface where two of three actions ask and the
third does not teaches people not to read the ones that do.

**Withdraw** states, and each clause is provable from the deployed function:
the assignment becomes inactive; **nothing is deleted**; the record stays in the
Product's history, keeps the date it was assigned, and still counts towards the
total; the Product stays in the catalogue; the Retailer relationship is not
affected; and it can be reactivated later.

**Reactivate** states: the assignment becomes active again; the existing record
is **reused rather than duplicated**; and its **assigned date is reset to the
moment of reactivation**, so it shows when *this* assignment started rather than
when the Product was first assigned there.

**Assign** states: the Product becomes available at the Retailer; nothing about
the Product or the relationship changes; and withdrawing later keeps the record.

The Retailer is named in every dialog title, so a list of rows offering the same
verb cannot produce an ambiguous dialog. Dismissal — a tap outside, escape, or a
back gesture — is a refusal and sends nothing.

The vocabulary is *Assign*, *Reactivate assignment*, *Withdraw assignment*,
*Inactive assignment*, *Assignment history*. The words **delete**, **remove**,
**erase**, **permanently** and **unassign** appear nowhere in user-facing copy,
and a boundary test asserts their absence. Nothing claims a Retailer has sold,
stocked or received anything: an assignment records availability, and the schema
records nothing else about it.

---

## 11. Concurrency and duplicate submission

* `VendorProductAssignmentCubit.apply` refuses a second call while one is in
  flight — whichever pairing or action it names.
* The pairing being written shows progress and is disabled; every other row stays
  usable, and the picker disables all of its controls while any write settles.
* The **Assign Retailer** control is disabled while a write settles, so a picker
  cannot be composed from a history that is about to be re-read.
* The picker closes after a submission whatever the outcome: leaving it open over
  a list composed *before* the attempt would show a verdict that is no longer
  current.
* A request token is captured before every call and compared before every emit,
  so an answer that lands after a session change, after `clear()`, or after a
  newer request is **dropped**, not emitted.
* No optimistic locking is attempted: neither RPC supports one, and inventing a
  version check the backend does not honour would be worse than none.

Backend-side, `assign` locks the Product row `FOR UPDATE` before it decides and
both writes lock the assignment row, so all four races serialize with zero
errors, zero duplicate rows, and an audit-row count equal to the number of
**real** transitions. Even a request that got through twice could not record two
decisions: both same-state requests are silent no-ops, and the unique index makes
a second history row structurally impossible.

---

## 12. Routing

**No route was added.** Assignment management lives inside the existing Product
detail route, `/vendor/products/:productId`, because every one of its actions is
about one Retailer of one Product and a dedicated route would be a second place
for the surface to exist. The picker is a `Dialog`, so it does not touch the
location at all.

Consequences, all asserted:

* the **Products** destination stays selected while assigning or withdrawing
  (`indexForLocation` takes the longest matching prefix);
* the Vendor shell stays visible;
* browser back / forward behave exactly as they did — assignment changes the
  location not at all;
* a malformed `:productId` reaches the same non-leaking "Product not available"
  state it already did, and issues no request;
* Retailer Owner, Retailer Manager and Sales Staff are redirected out of the
  Vendor group and never see an assignment control;
* there is **no** bulk-assignment route and **no** assignment-delete route, and
  navigating to `/vendor/products/:id/assignments` renders no assignment surface.

---

## 13. Session isolation

`VendorProductAssignmentCubit` is provided by `VendorShell` — above the session
listener, which is the subtree that must be emptied when the signed-in person
changes — and is cleared by `_SessionIsolation` alongside the other thirteen
cubits.

The trigger is an **identity** (`authUserId`, `organizationId`), not a boolean,
so a direct `Vendor A → Vendor B` transition with no intermediate state is
detectable on its own terms — and an identical re-emitted session compares equal
and costs no clear, so an open picker and a half-typed search survive a same-user
token refresh.

`clear()` empties: the candidate Retailers, the search term, the selected
Retailer, the pending action, the write phase, write errors, success notices and
the recorded Product id. It advances the request token **first**, so in-flight
assign requests, withdraw requests and candidate-list loads are invalidated: a
stale Vendor A answer is dropped on arrival rather than leaving an "Assignment
withdrawn" notice over Vendor B's Product, or a stale candidate list inviting a
write against a Retailer this session does not manage. The Product detail and
catalogue cubits invalidate their own in-flight reloads the same way.

Cleared on: sign-out, direct Vendor A → Vendor B, an organization change, Vendor
→ another role, session denied, session unavailable, and session invalidation.

The assignment cubit is deliberately **not** reloaded for the new Vendor: it has
nothing to load until a Product is open and a picker is asked for, so eagerly
re-reading the directory into it would be a request nobody made.

---

## 14. Audit behaviour

Successful transitions create exactly one audit row each, **inside the same
transaction as the mutation** — an audit failure rolls the mutation back, proved
rather than asserted on the backend:

| | action | entity | metadata |
| --- | --- | --- | --- |
| assign / reactivate | `PRODUCT_ASSIGNED_TO_RETAILER` | `VENDOR_PRODUCT`, the Product id | five display-only keys |
| withdraw | `PRODUCT_UNASSIGNED_FROM_RETAILER` | same | same |

A **no-op writes none**, which is what stops a double tap recording two entries.
Failed authorization attempts are recorded nowhere.

**Flutter writes no audit row and never calls `audit_logs`.** It could not attest
to an event it did not perform, and the RPCs already do it correctly.

**No Audit Logs change was needed.** Both action codes were already in
`VendorAuditLogLabels` — *"Product assigned to a Retailer"* and *"Product
unassigned from a Retailer"* — and the existing test that asserts every shipped
code has a label already covers them. No metadata is returned to this client
anyway: both writes return `void`.

---

## 15. Accessibility

* The assignment section keeps its section heading; the picker's title is marked
  `header: true`.
* Each assignment row is spoken as **one** sentence — Retailer name, assignment
  status, Retailer status, relationship status (or the unavailable explanation),
  both dates — with every status named by its subject, so a listener is never
  left to guess which "Suspended" they just heard. No uuid is spoken.
* **The controls sit outside that collapsed description.** The row's descriptive
  `Semantics` uses `excludeSemantics`, which would swallow any control inside it
  — leaving it invisible to a screen reader and unreachable by keyboard — so
  every interactive element keeps its own node. (This also fixed the existing
  *View Retailer* cross-link, which was inside the collapse before.)
* Assign, Reactivate and Withdraw each carry a button semantics label naming the
  Retailer and stating that confirmation follows.
* Picker rows are spoken as name → state → previous assignment date, with the
  control as its own button node.
* Progress uses the button's built-in loading label (*Withdrawing…*,
  *Reactivating…*, *Assigning…*) rather than a bare spinner.
* Success, stale-data, unavailable-eligibility and reload states are all rendered
  as text; **nothing is conveyed by colour alone** — an unavailable reactivation
  is a full sentence rather than a greyed control, and every status pill carries
  its own word.
* Focus order follows reading order, and no control is rendered disabled where a
  sentence would explain the situation better.

---

## 16. Responsive behaviour

* **Phones (360 / 390 px).** Assignment cards stack; status pills `Wrap` onto
  separate lines at large text scale; the cross-link and the assignment control
  `Wrap` rather than overflow; the picker is a full-width dialog with an inset
  margin, its list scrolling inside its own bounds so the header and the Close
  action stay reachable.
* **Tablet and web.** The dialog is capped at 560 px and at 85 % of viewport
  height, keeping a comfortable measure; the Product's fact rows switch to a
  label/value split above 420 px.
* **Light and dark** are both exercised for the section and for the picker.
* An `INACTIVE` assignment sits on the muted surface **and** carries an *Inactive
  assignment* pill, so the distinction survives without colour.
* No horizontal overflow at any of the four tested surfaces, with the picker open
  or closed.

Every control, surface, radius, spacing and type style comes from the SalesReward
design tokens and the shared `Sr*` components; nothing new was introduced.

---

## 17. Security boundary

Asserted in `test/security/vendor_product_boundary_test.dart`:

* no service-role key, secret key, bearer literal or environment read anywhere in
  the feature;
* `dart_defines.json` is git-ignored and untracked;
* the two assignment RPC names appear in **exactly one file**;
* exactly two parameter names, `p_product_id` and `p_retailer_organization_id`,
  and a colon count per invoker body that a third argument would break;
* no identity, tenant, Vendor, actor, audit-metadata, **relationship-id**,
  assignment-id, status, note, effective-date, price, quantity or idempotency
  argument;
* the request type has exactly two fields; the candidate type has no
  relationship-id field;
* no `.from(`, `.select(`, `.eq(`, `.insert(`, `.update(`, `.upsert(` or
  `.delete(` anywhere in the feature; no direct read or write of
  `vendor_product_retailer_assignments`, `vendor_products`, `vendor_retailers`,
  `organizations`, `profiles` or `audit_logs`; nothing touches `auth.users`;
* no client-side assignment insertion, removal or count adjustment;
* no bulk assignment in any spelling, and no multi-select;
* no permission or role code in executable source;
* no backend message text reaches presentation (`.message`, `error.toString`,
  `PostgrestException` and `AuthException` are absent from every presentation
  file);
* presentation never touches `Supabase.instance` or the SDK; the domain layer
  imports no SDK, HTTP, Flutter or `dart:io`;
* no cubit state holds a raw map or a `dynamic`;
* user-facing copy contains no *delete*, *remove*, *erase*, *permanently* or
  *unassign*, and the withdrawal confirmation contains the history-preservation
  clauses;
* stale responses cannot cross sessions (request tokens, asserted behaviourally).

---

## 18. Manual hosted verification

To be run against the hosted environment by a human. **No credential, UUID,
token, organization name or screenshot belongs in this document or in the
repository.** Do not modify unrelated production assignments to create fixtures —
use a Product and a Retailer that are already yours to change.

1. Start Flutter web:
   `flutter run -d chrome --dart-define-from-file=dart_defines.json`.
2. Sign in as a Vendor Super Admin.
3. Open **Products** and then one active Product.
4. Confirm the **Assigned Retailers** section shows the existing history and an
   **Assign Retailer** control.
5. Open **Assign Retailer**. Confirm the list shows your Retailers with a state
   line on each, that already-assigned Retailers carry no control, and that no
   identifier is displayed.
6. Assign an eligible Retailer and confirm the dialog.
7. Confirm the picker closes, *Product assigned* appears, and the Retailer now
   appears in the history as an **active** assignment.
8. Confirm `Retailer assignments` and `currently active` on this screen both
   increase, and that the Products catalogue card for this Product shows one more
   active assignment.
9. Confirm the Product's code, barcode, brand, description, status and dates are
   unchanged.
10. Withdraw that assignment and confirm the dialog.
11. Confirm the row **remains visible**, now marked *Inactive assignment*, and
    that the total assignment count is unchanged while the active count drops.
12. Confirm the row's *Assigned on* date is the **same** date it showed before
    the withdrawal.
13. Reactivate the assignment.
14. Confirm *Assigned on* has changed to today — the new activation time — and
    that *Assignment last updated* has moved.
15. Confirm there is still exactly **one** row for that Retailer; no duplicate
    was created.
16. Open **Audit Logs** and confirm *Product assigned to a Retailer* and *Product
    unassigned from a Retailer* entries appear for this Product.
17. Deactivate the Product. Confirm **Assign Retailer** and every **Reactivate**
    disappear with an explanation, that every assignment row is still listed, and
    that **Withdraw** is still offered on an active one. Reactivate the Product
    afterwards.
18. Attempt to assign a suspended or deactivated Retailer. Confirm it is listed
    with a neutral explanation and offers no control; if one is suspended between
    loading the picker and submitting, confirm the refusal is the generic safe
    message and names no permission or status.
19. Refresh the browser on the Product route, then navigate away to Retailers and
    back. Confirm the assignment state is re-read rather than restored from
    memory.
20. Sign out. Confirm no assignment data, search term or acknowledgement survives,
    and that signing in as a non-Vendor role exposes no assignment control.

---

## 19. Verification

| Check | Result |
| --- | --- |
| `dart format .` | clean |
| `dart format --set-exit-if-changed .` | **PASS** |
| `flutter analyze` | **No issues found** |
| `flutter test` | **PASS** — 2 794 tests (2 585 before this milestone) |
| `flutter build web --release --dart-define-from-file=dart_defines.json` | **PASS** |
| `git diff --check` | clean |

Tests added by this milestone: **209** across five new files and four extended
ones. Focused regressions across Dashboard, Retailers, Users, Roles, Products,
Audit Logs, Company/profile, the app shell and the security boundary: **2 492**,
all passing.

---

## 20. Known limitations

1. **No bulk assignment.** No backend function exists, and N calls would not be
   one transaction.
2. **No assignment deletion.** Withdrawal sets a status; nothing in the schema
   deletes an assignment row, and no client control implies otherwise.
3. **No assignment notes.** No column exists.
4. **No assignment-level pricing.** No column exists.
5. **No effective-date scheduling.** No column and no function exists.
6. **No optimistic locking.** Neither RPC supports one; the backend serializes
   with row locks and a unique index instead.
7. **Reactivation resets `assigned_at`.** The pairing's first-ever assignment
   date is not recoverable from the assignment row — it lives in the audit log.
8. **Both write RPCs return `void`.** A backend no-op is indistinguishable from a
   real change, by design.
9. **Canonical reads are required after every write**, and cost two round trips
   on the Product screen plus one for the catalogue.
10. **A multi-Vendor Super Admin acts as the lowest organization id**, with no way
    to choose. The shipped rule across every Vendor RPC.
11. **Eligibility may change between loading the candidate list and submitting.**
    The client's verdict is a hint; the backend may refuse a selection it called
    assignable, and that refusal is the generic safe message.
12. **The candidate list is composed client-side** from two reads. It is a
    convenience, not a security boundary.
13. **The backend remains the final authority** on identity, tenancy,
    eligibility, authorization, transactions and audit.
