# Vendor Retailer list and detail

**Branch:** `feat/flutter-vendor-retailer-reads`
**Scope:** an authenticated Vendor Super Admin lists the Retailers connected to
their Vendor organization, opens one, and sees its details and shops.
**Backend repository:** not modified. Nothing was deployed.

The backend contract this implements is
`salesreward-admin/docs/mobile-vendor-retailer-reads-audit.md` and the migration
`20260731090000_mobile_vendor_retailer_reads.sql`. Where this document and those
differ, those are right — they describe what is deployed.

> **This milestone is read-only.** There is no add, invite, suspend, edit or
> shop-creation path anywhere in it, and the repository interface has no method
> that could become one without changing the interface.

---

## 1. What a Vendor Super Admin can now do

| # | Step | Backend operation |
| --- | --- | --- |
| 1 | See every connected Retailer | `public.list_vendor_retailers()` |
| 2 | See names, both statuses, owner state and shop counts | — (columns of the above) |
| 3 | Search the loaded Retailers by name | — (local) |
| 4 | Filter by relationship status | — (local) |
| 5 | Refresh the directory | `list_vendor_retailers()` again |
| 6 | Open one Retailer | `public.get_vendor_retailer_detail(uuid)` |
| 7 | See its country and default currency | — (columns of the above) |
| 8 | See its shops | `public.list_vendor_retailer_shops(uuid)` |
| 9 | Retry a failed detail or shop read | the same call |
| 10 | Return to the directory without reloading it | — |

Nothing else. No onboarding, no owner invitation, no owner personal details, no
shop creation or editing, no Vendor Users, Roles, Products or dashboard metrics,
and no receipt data.

---

## 2. Architecture

```text
presentation/vendor/
  pages/     vendor_retailers_page.dart            the directory
             vendor_retailer_detail_page.dart      one Retailer
  cubit/     vendor_retailer_list_cubit.dart       one list read + local narrowing
             vendor_retailer_detail_cubit.dart     detail → shops, in that order
  widgets/   vendor_retailer_card.dart             one directory row
             vendor_retailer_shop_tile.dart        one shop
             vendor_retailer_badges.dart           status and owner-state pills
             vendor_retailer_filter_bar.dart       search + status chips
             vendor_retailer_grid.dart             1 / 2 / 3 columns by width
             vendor_retailer_copy.dart             every user-facing sentence
             vendor_retailer_formatting.dart       dates and count phrases
        │
        ▼  domain types only — never a Supabase or transport type
domain/
  entities/      VendorRetailerSummary · VendorRetailerDetail
                 VendorRetailerShop · VendorRetailerStatus · RetailerOwnerState
  repositories/  VendorRetailerRepository (interface) · VendorRetailerResult<T>
        │
        ▼
data/
  datasources/   vendor_retailer_rpc_data_source.dart   the three RPCs
  models/        vendor_retailer_parsers.dart           strict parsing
  repositories/  supabase_vendor_retailer_repository.dart
```

Wiring: `lib/app/di/injector.dart` registers `VendorRetailerRepository`;
`lib/app/app.dart` provides it to the tree; `lib/app/shells/vendor/vendor_shell.dart`
constructs both cubits from it.

**Rules the layering enforces**, each covered by a test in
`test/security/vendor_retailer_boundary_test.dart`:

- The presentation layer never imports `supabase_flutter` or `package:http`, and
  never touches `Supabase.instance`.
- The domain layer imports no SDK, no transport package, and not even
  `package:flutter`.
- No BLoC state holds a raw SDK map — or any `dynamic` at all.
- Only the data layer names an RPC.
- Supabase details stop at `data/`.

### Why `VendorRetailerResult<T>` is local

It is structurally identical to `ReceiptResult<T>`. Promoting a shared
`Result<T>` into `core/` is a refactor of a shipped feature, not part of this
milestone — when a third feature needs one, that is the evidence to promote it,
and doing it then costs one mechanical change where doing it now would mean
editing receipt code this branch has no reason to touch. The same reasoning
applies to the local UUID-shape helper.

---

## 3. Exact backend operations

| Method | RPC | Arguments |
| --- | --- | --- |
| `retailers()` | `list_vendor_retailers()` | **none** |
| `retailerDetail(id)` | `get_vendor_retailer_detail(p_relationship_id)` | the relationship id only |
| `retailerShops(id)` | `list_vendor_retailer_shops(p_relationship_id)` | the relationship id only |

`list_vendor_retailers()` takes **zero arguments**, and the data source models it
as a nullary Dart function — so a Vendor organization id, user id, profile id,
membership id, role code, permission code, tenant id or Retailer organization id
is not merely absent, it is *inexpressible* at that boundary. The other two pass
one key, `p_relationship_id`, and a test greps the source to prove no other `p_*`
literal exists in the file.

### 3.1 Returned shapes, parsed strictly

**`list_vendor_retailers()`** — `relationship_id` (uuid), `retailer_organization_id`
(uuid), `retailer_name`, `retailer_status`, `relationship_status`,
`relationship_created_at` (timestamptz), `shop_count` (integer),
`active_shop_count` (integer), `owner_state`.

**`get_vendor_retailer_detail(uuid)`** — the same columns **plus** `country_code`
(nullable) and `default_currency` (nullable). One row, or **zero**.

**`list_vendor_retailer_shops(uuid)`** — `shop_id` (uuid), `shop_name`,
`shop_code` (nullable), `city` (nullable), `country_code` (nullable),
`shop_status`.

Nullability follows the deployed schema exactly: `organizations.country_code` and
`organizations.default_currency` are `null`-able, and so are `retailer_shops.code`,
`.city` and `.country_code`. Everything else is `NOT NULL` and a missing value is
a parse failure.

### 3.2 Status vocabularies

`retailer_status`, `relationship_status` and `shop_status` all draw from
`ACTIVE` / `SUSPENDED` / `DEACTIVATED` — the same `check` constraint on three
tables — so one `VendorRetailerStatus` enum serves all three. They remain three
separate facts and are rendered as separate badges.

`owner_state` is one of `ACTIVE`, `PENDING`, `DELIVERY_FAILED`, `EXPIRED`,
`NONE`, in that precedence.

### 3.3 What is deliberately not sent, and not received

**Not sent:** any user id, profile id, Vendor organization id, membership id,
role, permission code, tenant id, status, owner state, page or filter.
`retailer_organization_id` is *received* so a future screen can cross-link to the
product-assignment API — it is never accepted as an input, because
`vendor_retailers.id` is the narrower selector.

**Not received, and therefore not modelled:** owner name, email or timestamps;
invitation id, token, `token_hash`, `failure_code` or `invitation_kind`;
`vendor_organization_id`; membership, role or permission internals; shop
addresses; `updated_at`. The internal `vendor_retailer_owner_state(uuid)` is
granted to nobody and is never called; `get_vendor_retailer_owner_status(uuid)`
is out of scope for this milestone and is never called either — which is why no
owner personal data can appear on these screens.

---

## 4. The loading sequence

```
directory  →  list_vendor_retailers()                     ONE call, on shell entry
                 · rows keyed by relationship_id
                 · counts come from the SQL lateral aggregate — no shop read

tap a row  →  get_vendor_retailer_detail(relationship_id)  ONE call
                 · zero rows  ⇒ "not available", stop. No shop read.
                 · one row    ⇒ render, then:
              list_vendor_retailer_shops(relationship_id)  ONE call
```

**The order is load-bearing.** The shop read answers an empty list both for a
shop-less Retailer of the caller's own *and* for a relationship that is not
addressable by them. The detail read is what tells those apart: zero rows
**there** is the authoritative "not addressable". Loading shops first, or in
parallel, would leave the screen unable to distinguish the two — and the safe
reading of the second is not "no shops".

**Duplicate calls are structurally impossible, not merely unlikely:**

- The directory cubit is created and loaded **once**, by the Vendor shell. A
  router refresh, a rebuild or a return from a detail screen renders rows already
  held.
- `VendorRetailerDetailCubit.open(id)` is idempotent for the id it is already
  showing, so a rebuild issues nothing. It is started from `initState`, which
  runs once per mounted route.
- Both cubits refuse a second read while one is in flight, so repeated refresh
  taps produce one request, not several.
- Every read captures a request token and compares it before emitting, so an
  answer that lands after a newer read — or after a session change — is dropped
  rather than overwriting fresher state.

A background refresh **keeps the loaded rows on screen** and shows that it is
running (button spinner, pull-to-refresh indicator); it never blanks the list.

---

## 5. Routing

| Route | Page |
| --- | --- |
| `/vendor/retailers` | `VendorRetailersPage` |
| `/vendor/retailers/:relationshipId` | `VendorRetailerDetailPage` |

The detail route is **nested** under the directory route, so a `go` into it
stacks the directory beneath: the back gesture and the *Back to Retailers* button
return to a list that is still loaded, and the shell keeps the Retailers
destination highlighted (`indexForLocation` takes the longest matching prefix).

Route isolation is unchanged: both paths sit under the `/vendor` prefix, so
`redirectFor` sends a Retailer Owner, Retailer Manager or Sales Staff caller back
to their own landing — and the Vendor shell that owns the cubits is never built
for them, so no Retailer read is issued on their behalf.

**The guard is presentation, not security.** Deleting it would let another role
reach a screen whose every RPC returns `42501`.

---

## 6. Parser behaviour

Every field reader throws rather than substituting a default; the repository maps
a throw to `UnavailableFailure`. There is no branch anywhere that produces a
value the backend did not send.

| Input | Result |
| --- | --- |
| Malformed UUID (any id column) | parse failure → outage |
| Missing or blank required field | parse failure → outage |
| Count as text, or fractional | parse failure → outage |
| **Negative** count | parse failure → outage (never clamped to 0) |
| `active_shop_count > shop_count` | parse failure → outage |
| Malformed or non-string timestamp | parse failure → outage |
| Several rows from the single-row read | parse failure → outage |
| Unrecognised status token | `VendorRetailerStatus.unknown` — neutral badge, **never active** |
| Unrecognised owner state | `RetailerOwnerState.unknown` — **never** a completed or accepted owner |
| Null `country_code` / `default_currency` | `null`, rendered "Not recorded" |
| Null shop `code` / `city` / `country_code` | `null`, rendered "Not recorded" |
| Blank optional string | normalized to `null` (the schema forbids storing one) |
| **Zero rows** from the detail read | `null` inside a **success** |

Unknown tokens degrade rather than failing the read because a newer backend is an
additive change. They can never grant anything: `isActive` and `hasActiveOwner`
test their member positively, so nothing arrives at "active" by elimination. The
raw token never reaches a screen.

A missing shop status is a **parse failure**, not an inferred `ACTIVE` —
`retailer_shops.status` is `NOT NULL`, and that inference is the one this parser
exists to refuse.

---

## 7. Error semantics

| Situation | State | Copy | Retry |
| --- | --- | --- | --- |
| Vendor manages no Retailers | ready + empty | "No Retailers yet" | no |
| `42501` | `DeniedFailure` | "Not available to this account" | no |
| Expired session | `UnauthenticatedFailure` | "Your session has ended" | no |
| Timeout / unreachable backend | `UnavailableFailure` | "Could not load this" | **yes** |
| Malformed response | `UnavailableFailure` | same as above | **yes** |
| Refresh failed over loaded rows | rows kept + warning alert | "This list may be out of date" | yes |
| Unknown / foreign / malformed relationship id | `notFound` | "Retailer not available" | **no** |
| Detail loaded, shops failed | shop section only | "Shops could not be loaded" | **yes**, shops only |
| Authorized Retailer with no shops | ready + empty shops | "No shops yet" | n/a |

Three rules hold throughout, inherited from the shared `SrFailureView`:

1. **No raw backend text.** `mapSupabaseError` discriminates on SQLSTATE and
   returns a discriminant; no Postgres message, SQLSTATE, stack trace, table,
   column, function or policy name reaches a screen.
2. **An outage is never a denial**, and a denial never reads as "not found".
3. **An inaccessible relationship is never described as somebody else's.**
   "Retailer not available" is the single wording for an unknown id, another
   Vendor's id and a malformed id alike — and it offers no retry, because the
   backend already answered and will answer the same way. Wording them
   differently would confirm that a relationship the caller may not read
   nevertheless exists.

A malformed id in the URL never leaves the client: the repository refuses the id
shape and answers `null`, which is the *same* answer the backend gives for an id
that names no row — so a mistyped URL cannot surface as a database outage, and
cannot be told apart from a foreign one.

---

## 8. Security boundary

The client never decides which Vendor it is. Asserted by
`test/security/vendor_retailer_boundary_test.dart`:

- No service-role key, secret key or hardcoded credential.
- No environment read outside `AppConfig`.
- No hardcoded organization identifier — a UUID literal anywhere in the feature
  fails the scan.
- No direct table query: no `.from(`, `.select(`, `.eq(`, `.maybeSingle(`, and no
  quoted `vendor_retailers`, `organizations`, `retailer_shops`,
  `organization_members`, `member_roles` or `retailer_invitations`.
- No identity, tenant, role, permission, limit or offset argument on any RPC.
- No permission code, and no reference to `has_organization_permission` or
  `get_vendor_super_admin_context` — the Vendor Super Admin resolver is **not**
  duplicated.
- No role inferred from an email, JWT claim or user metadata.
- A `PortalKind` is read for its display label and nothing else — never compared
  to decide whether a read is permitted.
- No invitation token, hash, failure code, kind or timestamp field, and no owner
  name or email field.
- No write operation name (`onboard_vendor_retailer`, `invite_retailer_owner`, …).
- No fabricated Retailer, shop, count or status literal outside the domain enums.

Supabase remains the authority. Every read is decided again in SQL on every call,
by `SECURITY DEFINER` functions that derive the Vendor from `auth.uid()` and
match each relationship on **both** its own id and that derived Vendor.

### Session isolation

`VendorShell` wraps its cubits in a `BlocListener<SessionBloc>` that fires
whenever the session stops — or starts — being a Vendor session. It clears both
cubits in **both** directions, then reloads the directory for a new Vendor.

This is not a second authentication listener: `SessionBloc` is the application's
existing session lifecycle, and subscribing to Supabase's auth stream again would
create a second opinion about who is signed in.

The widget lifetime is **not** relied on. A user switch emits `SessionInitial`
and the next person's `SessionActive` within one microtask drain, so no frame
renders in between — and a Vendor→Vendor switch keeps the location inside the
same role group, so the guard has no reason to redirect and the element is
certain to survive.

Cleared on a session change: Retailer summaries, the open Retailer, its shops,
**and the search term and status filter** — a search term is usually a fragment
of a Retailer's name, so leaving it behind would leave one Vendor's business
relationships legible to the next person on the device.

---

## 9. Responsive UI

Built from the existing design system (`SrPageBody`, `SrPageHeader`, `SrCard`,
`SrSectionCard`, `SrBadge`, `SrButton`, `SrTextField`, `SrStatCard`,
`SrEmptyState`, `SrFailureView`, `SrLoadingView`, `SrAlert`). One additive change
was made to it: `SrPageBody` gained an optional `physics`, so a page wrapped in a
`RefreshIndicator` can pull-to-refresh even when its content is shorter than the
viewport.

- **Directory:** one column on a phone, two from 760px, three from 1100px —
  wider thresholds than `SrCardGrid`'s because a Retailer card carries three
  status pills on one line. Deliberately **not** a desktop table: cards read
  identically at every width, so there is no wide-only layout to keep in step
  with a phone fallback.
- **Detail:** label/value pairs stack below 420px and sit side by side above it.
- **Pull-to-refresh** on every platform, plus a header **Refresh** button — the
  button is what a browser, keyboard or screen-reader user can actually operate.
- **Light and dark** are both covered by widget tests, on four surfaces from a
  360×640 phone to a 1280×900 desktop, each asserting no overflow.
- **Colour is never the only signal.** Every status badge states its word and
  carries a distinct glyph; an inactive shop additionally sits on the recessed
  card surface with a slate disc, so the difference survives greyscale.
- **Accessibility.** Each Retailer card is one semantics node with `button: true`,
  a spoken summary of name, both statuses, owner state and shop counts, and the
  hint "View details". It names no identifier. Shop tiles carry an equivalent
  label including the "Not recorded" phrase for absent columns — a screen reader
  announcing "dash" tells nobody anything.
- **Openability** is signalled three ways per row: the interactive card
  treatment, a trailing chevron, and an explicit "View details" affordance. The
  whole card is the touch target, not the 16px glyph.

---

## 10. Manual verification (hosted)

Run against the hosted project with an existing Vendor Super Admin account. Use
whatever account your environment already provides; no credential or
organization name belongs in this document.

```
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

1. **Sign in** as a Vendor Super Admin. Expect the Vendor shell.
2. **Open Retailers** from the drawer. Expect a skeleton, then the directory.
3. **Compare with the web** `/retailers` page for the same account: the same
   Retailers, in the same alphabetical order, with the **same** shop counts —
   `shop_count` is deliberately every shop, matching what the web shows.
4. **Verify the counts** on a Retailer known to have inactive shops: the mobile
   summary line adds "(N active)", which the web has no column for.
5. **Open a Retailer.** Expect exactly two requests: the detail, then the shops.
6. **Verify the fields** — name, relationship status, Retailer status, owner
   state, country, default currency, shop counts, onboarded date. A Retailer with
   no country or currency recorded shows "Not recorded", not a blank.
7. **Verify the shops** — name, code, city, country, status; suspended and
   deactivated shops are listed, visibly distinct from active ones.
8. **A Retailer with no shops**, if one exists: expect "No shops yet", *not* an
   error and *not* "not available".
9. **A relationship id you do not own:** paste `/vendor/retailers/<any other
   uuid>`. Expect "Retailer not available", no retry, and no shop request.
10. **Refresh** with the header button and by pulling down. The rows stay on
    screen while it runs; repeated taps issue one request.
11. **Log out** from the account sheet. Sign back in: the directory, any open
    Retailer, its shops and the search box are all empty and re-read.

On a phone build (`flutter run -d <device>`) steps 2–11 are identical; the drawer
and pull-to-refresh are the only differences.

---

## 11. Known limitations

- **No pagination.** `list_vendor_retailers()` returns the Vendor's whole
  directory in one unpaginated response, so search and status filtering operate
  locally over the complete trusted answer. No page counter is invented here;
  when the backend grows cursor parameters, the cubit gains them.
- **No add, invite or edit actions.** Onboarding a Retailer, inviting an owner,
  suspending a relationship and editing a Retailer are all out of scope. The
  repository interface has no method that could become one.
- **No owner personal details.** The deployed reads return the owner *state* and
  nothing more. Name, email, `sent_at` / `expires_at` / `accepted_at`,
  `failure_code` and `invitation_kind` come only from
  `get_vendor_retailer_owner_status(uuid)`, which this milestone does not call.
- **No shop editing or creation**, and shop rows are not tappable — there is no
  shop detail screen to open.
- **Vendor multi-organization selection is unchanged.** A caller who is a Super
  Admin of two Vendors sees the **lowest-id** Vendor's Retailers, deterministically
  and on every request. That is the shipped behaviour of every existing Vendor
  RPC; changing it is a backend product decision, not a mobile one.
- **`list_vendor_retailer_shops` cannot distinguish "no shops" from "not yours"**
  on its own. The app works around it by loading the detail first — see § 4 — but
  the ambiguity is in the contract.
- **Users, Roles, Products, Audit Logs and dashboard metrics remain
  placeholders.** None of them has a mobile backend contract yet, and each needs
  its own audit before a screen is built against it.
- **`get_vendor_retailer_owner_status` remains an unfrozen contract** upstream
  (`mobile-backend-contract.md` § 6.1). Not calling it means this milestone is not
  exposed to that, but it does not fix it.
