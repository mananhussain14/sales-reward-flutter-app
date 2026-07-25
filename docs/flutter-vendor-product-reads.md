# Flutter Vendor Product reads

**Milestone:** a real, read-only Vendor Product catalogue, product detail and
assigned-Retailer list, replacing the `/vendor/products` placeholder.
**Branch:** `feat/flutter-vendor-product-reads`
**Backend:** deployed, unchanged by this milestone —
`supabase/migrations/20260803090000_mobile_vendor_product_reads.sql` and the
already-shipped `list_vendor_products()` from `20260727210000`.
**Backend audit:** `docs/mobile-vendor-product-reads-audit.md` in
`salesreward-admin`.

This milestone is **read-only**. It adds no product write, no assignment write,
no image, no pricing and no reward configuration — and no disabled affordance
for any of them.

---

## 1. Architecture

The fourth vertical slice in `lib/features/`, following Retailers, Users and
Roles, and built to the same clean-architecture shape.

```
lib/features/products/
├── domain/
│   ├── entities/
│   │   ├── vendor_product_status.dart              ACTIVE | INACTIVE | unknown
│   │   ├── vendor_product_assignment_status.dart   ACTIVE | INACTIVE | unknown
│   │   ├── vendor_product_summary.dart             the 10 list columns
│   │   ├── vendor_product_detail.dart              those 10 + assignment_count
│   │   └── vendor_product_assigned_retailer.dart   one existing assignment row
│   └── repositories/
│       └── vendor_product_repository.dart          three reads, nothing else
├── data/
│   ├── models/vendor_product_parsers.dart          strict parsers
│   ├── datasources/vendor_product_rpc_data_source.dart
│   └── repositories/supabase_vendor_product_repository.dart
└── presentation/vendor/
    ├── cubit/   list + detail cubits and states
    ├── pages/   vendor_products_page.dart, vendor_product_detail_page.dart
    └── widgets/ copy, formatting, badges, card, filter bar, assignment tile
```

**Shared, not duplicated.** `ReadResult<T>` (`lib/core/result/`),
`Failure` + `mapSupabaseError` (`lib/core/errors/`), `SrResponsiveGrid`,
`SrCard`, `SrBadge`, `SrStatCard`, `SrEmptyState`, `SrFailureView`, `SrAlert`
and the rest of the design system are reused unchanged.

**`VendorRetailerStatus` is reused rather than redeclared.** `retailer_status`
is `organizations.status` and `relationship_status` is `vendor_retailers.status`
— the *same two columns* the Vendor Retailer screens already read, under the
same `ACTIVE / SUSPENDED / DEACTIVATED` constraints. A second enum with
identical members would be a second place to add a future value.

**`VendorProductAssignmentStatus` is *not* folded into it.** Its constraint
permits two values, not three, and it describes a different row. One shared type
would make `SUSPENDED` expressible where it cannot occur, and would let a
product status be passed where an assignment status belongs.

**No `Supabase.instance.client` in presentation.** The repository is resolved
from `GetIt` in `lib/app/di/injector.dart`, provided to the tree by
`SaleRewardApp`, and read by `VendorShell` when it builds the two cubits. No raw
`Map` reaches a cubit state or a widget.

---

## 2. The exact three RPCs

| # | Call | Arguments | Returns |
| --- | --- | --- | --- |
| 1 | `public.list_vendor_products()` | **none** | `setof` 10 columns |
| 2 | `public.get_vendor_product_detail(p_product_id uuid)` | one product id | 0 or 1 row, 11 columns |
| 3 | `public.list_vendor_product_assigned_retailers(p_product_id uuid)` | one product id | `setof` 8 columns |

`p_product_id` is the **only** parameter name anywhere in the feature, asserted
by `test/security/vendor_product_boundary_test.dart`.

**Nothing else is sent.** No auth user id, profile id, membership id, Vendor
organization id, tenant id, Retailer organization id, product code, product
status, assignment status, role code, permission code, search term or page
cursor — not as an optional, not as a named argument with a default. The
catalogue invoker is typed `Future<Object?> Function()`, so at that boundary
there is no argument to get wrong.

### 2.1 The list read is reused verbatim

`list_vendor_products()` shipped with the web catalogue in `20260727210000` and
is **not** re-added, wrapped or replaced. The backend audit found nothing to fix
in it: zero arguments, the Vendor derived from `auth.uid()`, the assignment count
aggregated in SQL as a correlated `count(*)`, no identity or tenant internals,
`authenticated` only. A second list read would be a second definition of "this
Vendor's products", free to drift from the one the web already renders.

### 2.2 The web's editor matrix is deliberately never called

`list_vendor_product_retailer_assignments(uuid)` is the assign/withdraw matrix
the web product page uses. It is not called here, and the boundary test asserts
its name appears nowhere in executable source. Three reasons:

- it requires `PRODUCT_RETAILER_ASSIGN` — the permission to *change*
  assignments — so a read-only screen would have to demand a write permission;
- it returns **every** Retailer the Vendor manages, including never-assigned ones
  with `assignment_status = NULL`, so a client would have to filter nulls itself;
- it returns no `relationship_id`, so it cannot cross-link to the shipped Vendor
  Retailer detail screen.

---

## 3. Two entities, not one

```
list_vendor_products()        →  10 columns, NO assignment_count
get_vendor_product_detail()   →  11 columns, WITH assignment_count
```

`VendorProductSummary` and `VendorProductDetail` are **siblings**, sharing ten
field names and no inheritance.

A single entity would need a **nullable** `assignmentCount`, and a nullable count
is ambiguous: `null` would mean both "this product has zero assignments"
*(impossible — the detail returns `0`, never `null`)* and "this row came from the
list, where the total was never computed".

Inheritance would be the same mistake wearing a type. If the detail widened the
summary, a summary variable could hold a detail and a caller could not tell
whether the total was available; and a future column added to only one read would
have a place to hide.

**What is shared is the parsing**, in a private `_common()` helper in
`vendor_product_parsers.dart`. That is safe for exactly one reason: the backend
pins the ten shared columns byte-identical in name, type and meaning — including
`active_assignment_count`, which is `bigint` on both sides — and asserts that
relationship structurally rather than by restating two literals.

> Contrast `VendorRoleDetail`, which **is** a typedef of its summary: the role
> detail contract is the role list contract exactly. The distinction is whether
> the shapes genuinely differ. Here they do.

---

## 4. Product fields and nullability

| Field | Type | Null? | Notes |
| --- | --- | --- | --- |
| `product_id` | uuid | **no** | the selector; the tenant boundary |
| `product_code` | text | **no** | normalized upper-case; unique **per Vendor** |
| `barcode` | text | **yes** | the single GTIN-family field |
| `product_name` | text | **no** | **not unique**, even within one Vendor |
| `brand` | text | **yes** | |
| `description` | text | **yes** | |
| `status` | text | **no** | `ACTIVE` \| `INACTIVE` |
| `assignment_count` | bigint | **no** | **detail only** |
| `active_assignment_count` | bigint | **no** | both reads |
| `created_at` | timestamptz | **no** | primary sort key |
| `updated_at` | timestamptz | **no** | the *product* row's, not an assignment's |

**There is no product image, anywhere.** Not "not returned yet" — no column, no
storage bucket, no rendering, no storage call. So there is no `imageUrl` field,
no thumbnail, and deliberately **no grey placeholder frame** either: a fallback
glyph in an image-shaped box would advertise an image system that would then have
to be built to explain itself. The boundary test forbids `Image(`,
`NetworkImage`, `DecorationImage` and every image/storage field spelling.

**There is no category either**, and no price, incentive, campaign, reward, coin
or payout column. None is modelled and none is rendered.

`product_code` is unique per Vendor, not globally
(`vendor_products_code_unique_idx (vendor_organization_id, product_code)`), so
two Vendors may each own `A-100`. Nothing treats it as a global identifier, and
it is **never** a route selector.

---

## 5. Status constraints

| Status | Values | Modelled by |
| --- | --- | --- |
| Product | `ACTIVE`, `INACTIVE` | `VendorProductStatus` |
| Assignment | `ACTIVE`, `INACTIVE` | `VendorProductAssignmentStatus` |
| Vendor–Retailer relationship | `ACTIVE`, `SUSPENDED`, `DEACTIVATED` | `VendorRetailerStatus` (reused) |
| Retailer organization | `ACTIVE`, `SUSPENDED`, `DEACTIVATED` | `VendorRetailerStatus` (reused) |

There is **no** draft, archived, discontinued, review or approval product state
in this schema, and none is invented.

**An unknown future token degrades to `unknown`** — visible, neutrally styled,
never `active`, never carrying the raw backend token to the screen, and never
enabling navigation or an action by itself. Both enums test `active` *positively*
(`isActive => this == active`), so no future token can arrive at "active" by
failing to match something else. The boundary test asserts both.

A **missing or blank** status is a different thing entirely — a required value
the response did not supply — and the parser raises a format error for it.

---

## 6. Assignment-count semantics

An assignment is a **row** in `vendor_product_retailer_assignments`. At most one
row exists per (product, Retailer) **for all time**, so a Retailer assigned,
withdrawn and re-assigned is one row that flipped status twice. History cannot
inflate either count.

| | Counts |
| --- | --- |
| `assignment_count` | **every** row, `ACTIVE` and `INACTIVE` alike |
| `active_assignment_count` | rows whose status is exactly `ACTIVE` |

Neither count consults the **product's** own status, the **relationship** status
or the **Retailer organization's** status. An active assignment to a suspended
Retailer counts in both.

**The counts are the backend's, and the loaded list is one rendering of them.**
`assignment_count` is by construction the number of rows the companion returns,
and the client reports the count rather than the list length. When the two
disagree — `assignmentCountDisagrees` — the screen shows a note and changes
**neither**: every returned row is still rendered and both counts are still
reported unchanged. Dropping rows to match the number, or adjusting the number to
match the rows, would each fabricate agreement the backend did not send.

**An `INACTIVE` product keeps its assignments and its counts.**
`set_vendor_product_status` deliberately does not cascade, so the detail screen
renders identically whatever the product status, and nothing implies assignments
are disabled.

---

## 7. Assignment-list semantics

`list_vendor_product_assigned_retailers()` is driven **from the assignment
table**, so it returns one row per *existing* assignment and nothing else:

- a never-assigned Retailer is **absent**, not a null-status row;
- `assignment_status` is **never null**;
- withdrawn (`INACTIVE`) assignments **are** returned, and are marked.

Order: `retailer_name`, then `retailer_organization_id`. Preserved exactly —
never re-sorted, never grouped, never filtered. An inactive row keeps its place in
the sequence, which is what keeps the rendered rows equal in number to
`assignment_count`.

**Four statuses travel, and they are four different facts.** An `ACTIVE`
assignment against a `SUSPENDED` relationship or a `SUSPENDED` Retailer is a
real, reachable state — a Vendor may suspend a relationship without withdrawing
its products. All four are rendered as independent, subject-prefixed badges
("Assignment: Active assignment", "Retailer: Suspended", "Relationship:
Suspended"), and nothing derives one from another in either direction.

**Wording.** An inactive assignment is never called "currently assigned", and
`assignment_count` is never called "Retailers currently assigned". The screen
says *"3 Retailer assignments · 2 currently active"*, *"Active assignment"*,
*"Inactive assignment"*, *"Assigned on"* and *"Assignment last updated"*.

**`assignment_updated_at` is not a `withdrawn_at`.** No such column exists, so
none is invented. For an `INACTIVE` row it happens to be the moment of
withdrawal, but it is labelled and spoken as what it is, and no status is ever
read out of it. The boundary test forbids `withdrawnAt` / `isWithdrawn`.

---

## 8. Missing relationship behaviour

The relationship join in SQL is a `LEFT JOIN`, deliberately. An `INNER` join
would make an assignment row *vanish* from the list if its `vendor_retailers` row
ever ceased to exist, while `assignment_count` — taken from the assignment table
alone — would keep counting it.

So a missing relationship surfaces as:

```
relationship_id          NULL
relationship_status      NULL
retailer_organization_id present
retailer_name            present
retailer_status          present
assignment_status        present
```

The row **still displays**, is **still counted**, and is simply **not
cross-linkable**. This client:

- **accepts** the nulls (`_optionalUuidField`, `_optionalStatus`) rather than
  treating them as a parsing failure;
- **never** fabricates a relationship id, substitutes
  `retailer_organization_id`, or invents a relationship status;
- keeps `relationship_status` **null**, never `unknown` — "there is no
  relationship row" and "the relationship has a status this build does not
  recognise" are different claims, and only one of them is true;
- **omits** the relationship badge entirely, since there is no row to describe;
- renders **"Retailer relationship unavailable"** in place of the action — not a
  disabled button, because a control a reader can see and cannot use asks them to
  work out why;
- explains the state **once**, above the rows, via
  `VendorProductCopy.relationshipUnavailableNote`.

---

## 9. The loading sequence

Mandatory, and not interchangeable:

1. `get_vendor_product_detail(p_product_id)` — **once**;
2. only after one valid row is confirmed,
   `list_vendor_product_assigned_retailers(p_product_id)` — **once**.

**The two are never issued in parallel.** Both return an empty result for a
product this caller cannot address, and the companion also returns an empty
result for a product that has genuinely never been assigned. Those two are
indistinguishable from the companion alone, and that ambiguity is deliberate:
closing it would mean telling a caller whether another Vendor's product exists.

Zero rows from the **detail** read is the authoritative "this product is not
addressable by you".

| Case | detail | then assignments | Screen |
| --- | --- | --- | --- |
| valid product, zero assignments | 1 row | `[]` | detail + "Not assigned to any Retailer" |
| unknown product | 0 rows | **not called** | "Product not available" |
| another Vendor's product | 0 rows | **not called** | **byte-identical** to unknown |
| malformed route id | **not called** | **not called** | **identical** again |
| unauthorized caller | `42501` | — | one generic denial |

---

## 10. Malformed route handling

A selector that is not a valid UUID **never reaches PostgREST**. PostgreSQL would
reject it while casting the argument — `22P02`, raised *before* the function body
runs and therefore before any authorization check — which is a fourth outcome the
contract does not define, and which would surface in the client as a database
outage complete with a retry that could never succeed.

`isProductIdShaped()` guards both companions in
`SupabaseVendorProductRepository`, answering `null` / `[]` locally without a
request leaving the device. That is the *same* answer the backend gives for an id
that names no product, so it substitutes nothing.

Asserted end-to-end in `vendor_product_flow_test.dart` and
`vendor_product_detail_cubit_test.dart` over a **counting data source**, so the
guard is genuinely in the path rather than stubbed out: `/vendor/products/not-a-uuid`
makes **zero** detail calls and **zero** assignment calls.

---

## 11. Product-to-Retailer cross-linking

An assignment row with a non-null `relationship_id` opens the already-shipped
route:

```
/vendor/retailers/:relationshipId
```

`relationship_id` is the same `vendor_retailers.id` that `list_vendor_retailers()`
and `get_vendor_retailer_detail()` already return and accept, which is exactly why
the assignment contract returns it — it closes the two-address-space gap the
backend contract records against the editor read.

**`retailer_organization_id` is never a route selector.** It names a tenant some
other Vendor may also manage, and the Retailer screens do not accept it. The
boundary test asserts no source calls `retailerDetailPath(...retailerOrganizationId)`.

**Linkability is decided by the id, and by nothing else.** A `SUSPENDED` or
`DEACTIVATED` relationship is still addressable and still opens — the Retailer
detail screen exists precisely to explain such a state. What makes a row
un-openable is the absence of the row to open:

```dart
bool get isCrossLinkable => relationshipId != null;
```

---

## 12. Error semantics

| Situation | State | Retry? | Wording |
| --- | --- | --- | --- |
| `42501` denial | `ReadFailure(DeniedFailure)` | **no** | "Not available to this account" |
| expired session | `UnauthenticatedFailure` | via `SrFailureView` | generic |
| network timeout / backend unavailable | `UnavailableFailure` | **yes** | "Could not load this" |
| malformed response | `UnavailableFailure` | **yes** | never an empty catalogue |
| detail zero rows | `notFound` | **no** | "Product not available" |
| assignment-section failure | section-scoped | **yes**, section only | detail stays on screen |
| refresh failure with stale data | rows kept + `SrAlert` | **yes** | "This list may be out of date" |

**Nothing raw escapes.** `mapSupabaseError` is the only place a backend error
object is inspected, and it discriminates on SQLSTATE — never on message text. No
PostgreSQL message, SQLSTATE, PostgREST text, table name, function name, policy
name, stack trace or permission code reaches a screen.

**The permission split is invisible.** The assignment read requires
`RETAILERS_READ` *in addition to* `PRODUCTS_READ`. A caller holding only the
latter reads the product and is refused its Retailers — which surfaces as an
ordinary section failure with the same generic denial every other refusal gets.
Neither code is ever inspected or sent.

**Unknown and foreign products display identically**, and neither is ever
described as belonging to somebody else.

**Unreadable is never empty.** A malformed catalogue body becomes an outage, not
"you have no products"; a malformed assignment body becomes an outage, not "this
product has never been assigned".

---

## 13. Session clearing

`VendorShell._SessionIsolation` — the existing listener, extended, **not** a
second auth listener. It compares an *identity* (`authUserId` + trusted
`organizationId`), so a direct `Vendor A → Vendor B` switch with no intermediate
state is detectable on its own terms.

On logout, a direct Vendor→Vendor switch, an organization-context change, a
Vendor→other-role move, a denial, a session invalidation or any other identity
change, `VendorProductListCubit.clear()` and `VendorProductDetailCubit.clear()`
drop:

- product summaries, and the open product;
- assigned Retailer rows, with the Retailer names and statuses riding on them;
- both assignment counts;
- the search text and the status filter (private — fragments of product names and
  codes the previous person typed);
- the refresh state and every product-specific failure.

Each `clear()` **advances a request token first**, so a list, detail or
assignment response already in flight for the previous identity is dropped on
arrival rather than repopulating state that has just been emptied.

An **identical re-emitted session** — the shape a same-user token refresh takes —
compares equal, so it costs no clear and no duplicate load.

Nothing about a product catalogue is global: `vendor_products.vendor_organization_id`
is `NOT NULL` and immutable, so there is no version of this pair that could be
kept as a harmless cache.

---

## 14. Responsive UI

**List.** `SrResponsiveGrid` with the pair of thresholds this content needs
(`twoUpThreshold: 800`, `threeUpThreshold: 1150`) — one stacked column on a
phone, two on a tablet, three on a desktop browser. Cards, never a table: a
desktop table on a phone is either horizontally scrolled or squeezed unreadable.

**Card.** Name (2 lines then ellipsis), status pill in a `Wrap` so it runs onto
its own line at large text scale, code / barcode / brand identifier lines with
`Expanded` soft wrap, the active-assignment sentence, and a chevron plus an
explicit "View details".

**Detail.** `_Fact` rows stack below 420px and sit side-by-side above it, so a
long value is never truncated to fit beside its label. Assignment tiles wrap
three status pills onto separate lines on a 360px phone.

**Refresh.** Pull-to-refresh (`RefreshIndicator`) *and* a header button — the
second is what a browser, keyboard or screen-reader user can actually operate.
Both call the same method, which ignores a second call while one read is in
flight.

Covered at 360×640, 390×844, 900×1000 and 1280×900, in light and dark, and at
1.6× text scale, with `tester.takeException()` asserted null throughout.

---

## 15. Accessibility

- **Product card** — one spoken sentence carrying name, status, code, barcode,
  brand and the assignment count, with `button: true` and a "View details" hint.
  Absent optional fields are spoken as *"Not recorded"* rather than skipped, so a
  listener can tell "this product has no barcode" from "the barcode was not read
  out". No uuid is ever spoken.
- **Assignment row** — one spoken sentence naming each status *by its subject*
  ("Assignment: Inactive assignment", "Retailer: Suspended"), both dates with
  their labels, and the relationship-unavailable state spoken as a full
  explanation rather than as the absence of a pill.
- **Every badge** carries a word **and** a glyph, never colour alone. `unknown`
  renders a question glyph in slate.
- **Detail facts** are spoken as label-and-value pairs — "Barcode: Not recorded".
- **Controls** — search, filter chips (with `selected` set as well as a check
  glyph and a filled variant), Refresh, Retry, Back to Products and View Retailer
  all carry explicit semantics; View Retailer names its Retailer.

---

## 16. Manual hosted verification

To be performed against the hosted environment **after** this branch is reviewed.
Not performed as part of this milestone.

1. `flutter run -d chrome --dart-define-from-file=dart_defines.json`.
2. Sign in as a Vendor Super Admin.
3. Open **Products** from the Vendor drawer.
4. Compare product names, codes and statuses against the web `/products` page —
   they read the same RPC and must agree, in the same newest-first order.
5. Search by name, by product code, by barcode and by brand; confirm each
   narrows, that the count line reads "Showing N of M", and that mixed case works.
6. Filter by **Active** and by **Inactive**; confirm only statuses actually
   present are offered.
7. Tap **Refresh**; confirm the rows do not blank and the spinner shows.
8. Open an **ACTIVE** product.
9. Verify code, barcode, brand, description, status, created and updated dates,
   and that the assignment line reads "N Retailer assignments · M currently
   active" — check both figures against the web.
10. Verify the assigned Retailers: one row per assignment, in
    Retailer-name order, each with its assignment, Retailer and relationship
    status.
11. Tap **View Retailer** on a linkable row; confirm it opens the Vendor Retailer
    detail screen for the right Retailer.
12. Use browser Back; confirm the product detail is still loaded.
13. Open an **INACTIVE** product if one exists; confirm the status badge shows and
    the assignments and counts are still visible.
14. Find an **INACTIVE** assignment if one exists; confirm it reads "Inactive
    assignment" and is not styled as current.
15. Open a product with **no assignments**; confirm "This product has not been
    assigned to any Retailer."
16. If an assignment with a missing relationship exists, confirm it shows
    "Retailer relationship unavailable", offers no View Retailer, and is still
    counted.
17. Browser Back from a product detail; confirm the catalogue is still loaded and
    no skeleton flashes.
18. Visit `/vendor/products/not-a-uuid`; confirm "Product not available" with no
    retry and no raw error text. Confirm the network tab shows **no** RPC call.
19. Log out; confirm no product name, code or Retailer name survives.

Record no credentials, tokens, real UUIDs, service keys or private screenshots.

---

## 17. Known limitations

1. **No product images.** No column, no bucket, no storage call, no rendering —
   nothing exists to show. Not deferred; absent.
2. **No categories.** No category column exists, so no label is derived.
3. **No pagination.** Both list reads return a full set. Bounded by the Vendor's
   catalogue size and Retailer count; a keyset parameter can be added later
   without changing the column contract.
4. **Search and filtering are local only.** The RPC has no search or filter
   parameter by design — a server-side *status* filter would put a status value in
   a caller's hands, which the contract deliberately refuses.
5. **No product writes.** Create, update, delete and activate/deactivate all
   exist as shipped RPCs and none is called. Their duplicate code-vs-barcode error
   is discriminated by an **English message substring**, which Flutter must not
   re-implement (backend contract fix #3), and `set_vendor_product_status` returns
   `void`, hiding "changed" from "already so" (fix #4).
6. **No assignment writes.** Assign and withdraw exist and are not called, for the
   same `void`-return reason.
7. **No pricing, reward or incentive configuration.** No such column exists
   anywhere in the schema.
8. **No per-shop assignment.** Assignment is Retailer-level; there is no
   shop-level product assignment table.
9. **`relationship_id` may be null**, and such a row is not cross-linkable. § 8.
10. **An inactive assignment remains as history.** Withdrawal sets `INACTIVE` and
    never deletes, so the row stays visible and stays in `assignment_count`.
11. **`assignment_updated_at` is not a `withdrawn_at` field.** It is the
    assignment row's real `updated_at`; no withdrawal column exists.
12. **Multi-Vendor callers see one Vendor.** A Super Admin of two Vendors reads
    the **lowest-id** Vendor's catalogue, deterministically — the shipped behaviour
    of every Vendor RPC and of the web itself, reproduced rather than "fixed".
13. **Vendor Audit Logs and Vendor dashboard metrics remain placeholders.**
    Neither is begun here.

---

## 18. Tests

| File | Tests | Covers |
| --- | --- | --- |
| `test/features/products/vendor_product_parsers_test.dart` | 91 | every required rejection; nullable fields; all four status vocabularies including unknown tokens; the null-relationship case; the ten-plus-one entity relationship; no image/category field |
| `test/features/products/vendor_product_repository_test.dart` | 36 | zero-argument list call; `p_product_id` only; SQLSTATE classification; unreadable-is-never-empty; the local id guard; no table read, no storage, no write, no service key |
| `test/features/products/vendor_product_list_cubit_test.dart` | 38 | load, refresh, duplicate suppression, stale rows, search across all four fields, status filtering, summary counts, clear + stale-response discard |
| `test/features/products/vendor_product_detail_cubit_test.dart` | 37 | the exact call order, never parallel, no companion for an unaddressable id, zero-assignment vs unknown, section-only retry, null-relationship rows, duplicate loads, out-of-order stale responses |
| `test/features/products/vendor_product_flow_test.dart` | 99 | routing and cross-role denial, card contents, search/filter, detail rendering, all three assignment cases, cross-linking, malformed route with zero RPCs, session isolation, four surfaces, both themes, 1.6× text scale, semantics |
| `test/security/vendor_product_boundary_test.dart` | 44 | source-level boundary: no secret, no table read, no storage/image, no write, no permission code, no status derivation, no org-id navigation, layering |
| `test/features/users/vendor_session_isolation_test.dart` | +13 | the Vendor Product pair under a direct A→B switch, stale list/detail/assignment responses, identity no-op, org change, sign-out, role change |

**Repository total after this milestone: 1601 tests, all passing** (1242 before).
