# Flutter Vendor Audit Log reads

**Milestone:** a real, read-only Vendor activity feed with secure cursor
pagination, replacing the `/vendor/audit-logs` placeholder.
**Branch:** `feat/flutter-vendor-audit-log-reads`
**Backend:** deployed, unchanged by this milestone —
`supabase/migrations/20260804090000_mobile_vendor_audit_log_reads.sql`.
**Backend audit:** `docs/mobile-vendor-audit-log-reads-audit.md` in
`salesreward-admin`.

This milestone is **list-only and read-only**. It adds no audit detail view, no
raw metadata, no entity navigation, no actor navigation, no export, no filter,
no search, no deletion, no retention change, no dashboard metric and no alerting
— and no disabled affordance for any of them.

---

## 1. Architecture

The fifth vertical slice in `lib/features/`, following Retailers, Users, Roles
and Products, and built to the same clean-architecture shape.

```
lib/features/audit/
├── domain/
│   ├── entities/
│   │   ├── vendor_audit_actor_type.dart   USER | SYSTEM | UNKNOWN | unrecognized
│   │   └── vendor_audit_log_entry.dart    the 7 contract columns + the cursor type
│   └── repositories/
│       └── vendor_audit_log_repository.dart   one read, nothing else
├── data/
│   ├── models/vendor_audit_log_parsers.dart   strict parser
│   ├── datasources/vendor_audit_log_rpc_data_source.dart
│   └── repositories/supabase_vendor_audit_log_repository.dart
└── presentation/vendor/
    ├── cubit/   vendor_audit_log_cubit.dart + state
    ├── pages/   vendor_audit_logs_page.dart
    └── widgets/ copy, labels, formatting, actor badge, event tile
```

**One cubit, not a pair.** Every other Vendor slice owns a list cubit and a
detail cubit. There is no audit detail read to hold — see § 11 — so there is no
second cubit and no second route.

**Shared, not duplicated.** `ReadResult<T>` (`lib/core/result/`), `Failure` +
`mapSupabaseError` (`lib/core/errors/`), `SrCard`, `SrBadge`, `SrButton`,
`SrAlert`, `SrEmptyState`, `SrFailureView`, `SrLoadingView`, `SrPageHeader`,
`SrPageBody` and the rest of the design system are reused unchanged.

**No `Supabase.instance.client` in presentation.** The repository is resolved
from `getIt` in `lib/app/di/injector.dart`, provided to the tree by
`SaleRewardApp`, and read by `VendorShell` when it constructs the cubit — the
same seam every other slice uses, and what lets a widget test drive the whole
screen over a fake with no Supabase client.

**No second auth listener.** Session isolation reacts to the existing
`SessionBloc` through the shell's `_SessionIsolation` listener. Subscribing to
Supabase's auth stream again would create a second opinion about who is signed
in, and two opinions is one too many.

---

## 2. The exact RPC

```
public.list_vendor_audit_logs(
  p_limit               integer     default 50,
  p_before_occurred_at  timestamptz default null,
  p_before_audit_log_id uuid        default null
)
```

`STABLE`, `SECURITY DEFINER`, `SET search_path = ''`, executable by
`authenticated` only. `anon` and `service_role` are granted nothing.

**Two calls, and only two shapes:**

| Call | `p_limit` | `p_before_occurred_at` | `p_before_audit_log_id` |
| --- | --- | --- | --- |
| First page / refresh | `50` | `null` | `null` |
| Older page | `50` | last row's `occurred_at` | **that same row's** `audit_log_id` |

Both cursor keys are always sent, explicitly, even when null. Naming both every
time makes "the cursor is one value in two columns" visible at the call site
instead of implied by an absence.

**Never sent:** user id, auth user id, profile id, membership id, organization
id, Vendor id, tenant id, role code, permission code, actor selector, entity
selector, entity owner, action, date range, search term, offset, page number.
The parameter set is asserted in
`test/features/audit/vendor_audit_log_repository_test.dart` and again
structurally in `test/security/vendor_audit_log_boundary_test.dart`.

**No table is ever read.** Not `audit_logs`, `profiles`,
`organization_members`, `organizations` or `auth.users`. Unlike the product
tables — which are default-deny with zero policies — `authenticated` genuinely
holds `SELECT` on `audit_logs`, so a direct read *would work*. It is not done
because `select *` there would carry `metadata`, `entity_id`, `ip_address`,
`user_agent` and `actor_profile_id` (**the auth user id**) to a phone, would make
column choice a client responsibility on the most sensitive table in the schema,
and would move both the actor join and the keyset tie-break into Dart.

---

## 3. The exact result contract

Seven columns, in this order.

| Column | Type | Nullable | Dart |
| --- | --- | --- | --- |
| `audit_log_id` | `uuid` | **No** | `String auditLogId` |
| `occurred_at` | `timestamptz` | **No** | `DateTime occurredAt` (UTC) |
| `action_code` | `text` | **No** | `String actionCode` (**raw**) |
| `entity_type` | `text` | **No** | `String entityType` (**raw**) |
| `entity_display_name` | `text` | **Yes** | `String? entityDisplayName` |
| `actor_type` | `text` | **No** | `VendorAuditActorType actorType` |
| `actor_display_name` | `text` | **Yes** | `String? actorDisplayName` |

Ordering: `occurred_at desc, audit_log_id desc`. Total, because `id` is the
primary key. **Never re-sorted client-side** — a second sort would be a second
definition of the history order, would disagree with the web page showing the
same rows, and would take the next cursor from the wrong row.

### Parser rules

Rejected (the whole page fails, and the repository reports an operational
failure):

* missing, blank, non-text or malformed `audit_log_id`;
* missing, non-text or unparseable `occurred_at`;
* missing, blank or non-text `action_code`;
* missing, blank or non-text `entity_type`;
* missing, blank or non-text `actor_type`;
* non-text `entity_display_name`;
* non-text `actor_display_name`;
* `USER` with a null `actor_display_name`;
* `SYSTEM`, `UNKNOWN` or an unrecognised type with a **non-null**
  `actor_display_name`.

Accepted:

* `entity_display_name` null, absent, or blank (blank reads as null);
* `actor_display_name` null for `SYSTEM` and `UNKNOWN`;
* unknown future action codes, entity types and actor types.

**One malformed row fails the whole page rather than being dropped.** Dropping
would silently shorten a history — and because the cursor comes from the *last*
row, a dropped tail row would move the next page's boundary and skip real
events.

Timestamps are normalised to UTC on the way in, so the cursor is sent in one
representation whatever the device's zone.

---

## 4. Keyset pagination

**Both halves of the cursor, always, and both from the same row.**
`VendorAuditLogCursor` is `({DateTime occurredAt, String auditLogId})` — two
non-nullable fields — so a half cursor is *unrepresentable*, and the backend's
`22023` refusal for one is unreachable from this client.

**Why the tie-break is load-bearing.** `created_at` defaults to `now()`, which in
PostgreSQL is the **transaction** timestamp, so two audit rows written inside one
transaction carry byte-identical timestamps. A timestamp-only cursor over a tied
pair either re-emits both rows on the next page or skips both; there is no third
outcome.

**Cursor construction.** `cursorFrom(state.events.last)` at the moment of the
request. Never remembered across a refresh — a replaced list has a different
final row — never adjusted, never rounded, never invented. The boundary test
forbids `DateTime.now()`, `subtract(`, `add(const Duration` and the epoch
accessors anywhere in the feature.

**The cursor is ordering data, never authority.** It is applied *after* the
tenant predicate in SQL. A cursor copied from another Vendor's page — or invented
outright — moves the window within the caller's **own** history and can never
reach across the tenant boundary.

**Page size is a fixed 50.** The backend honours `1 … 100` and *raises* `22023`
for `0`, negatives and anything above 100 rather than clamping — precisely so a
client cannot ask for 500, silently receive 100, and infer from the short page
that the history has ended. Pinning 50 in the data source means this client can
never construct such a request, and it is what makes the end-of-history rule
below sound.

**The end of the history is a short or empty page, and nothing else.**
`page.length < 50`. A failed read is not an ending, and no total exists to
compare against: an exact `COUNT` over an append-only table that grows forever
costs a full scan per page and is stale the moment it is computed.

**Duplicates are removed defensively.** Merging filters by `audit_log_id`
against the ids already held, order preserved. The backend's strict `<` against a
unique composite key cannot produce a duplicate, so this should never remove
anything — but appending one would break the list keys and, because the cursor
comes from the final row, could stall paging on a repeating page. It is a guard,
not the authority.

**One read at a time.** `state.isBusy` gates all three operations, so a repeated
tap cannot produce simultaneous requests and a refresh cannot race an older page
whose cursor is about to be discarded.

---

## 5. Refresh semantics

Pull-to-refresh on mobile, an explicit **Refresh** button in the page header on
every platform. Both call `VendorAuditLogCubit.refresh()`.

1. Reads the newest page with **both cursor halves null**.
2. **Replaces** the loaded collection — never appends onto it. The two reads were
   taken at different instants, and splicing them would produce a list whose
   final row no longer describes its own cursor.
3. Recomputes `hasReachedEnd` from the returned page. A history that had reached
   its end can grow, and a refresh is when this client finds out.
4. Clears any pending older-page failure, whose retry is meaningless once the
   list is replaced.
5. **On failure, keeps the stale rows** and shows a non-blocking warning
   (*"This activity may be out of date"*). The rows are still the last thing the
   backend actually said.
6. Ignores a response that lands after the effective session changed.

An empty successful refresh means this Vendor currently has no visible audit
events — a real answer, worded as a fact and never as a denial.

New events cannot corrupt traversal: the SQL predicate is strictly-less-than
against a fixed position in a descending order, so every row a later page can
return is *older* than the cursor. Events arriving after the first page land
outside every subsequent page by construction, and appear the moment the reader
refreshes.

---

## 6. Actor semantics

| `actor_type` | Meaning | Name | Wording on screen |
| --- | --- | --- | --- |
| `USER` | resolved through a membership of **this** Vendor | non-null | the name, verbatim |
| `UNKNOWN` | actor id present, resolves to no membership here | null | *Unknown actor* |
| `SYSTEM` | **no actor identity remains** | null | *System or unavailable actor* |
| anything else | a token this build does not know | null | *Actor unavailable* |

`actor_display_name` is non-null **if and only if** `actor_type` is `USER`. The
backend asserts this across the whole page in pgTAP; the parser enforces it again
per row, so every screen may rely on it.

### `SYSTEM` is the one genuine ambiguity

`public.profiles.id REFERENCES auth.users ON DELETE CASCADE`, and
`audit_logs.actor_profile_id REFERENCES profiles ON DELETE SET NULL`. Two
different histories therefore produce a byte-identical row:

1. the event was written with no actor from the beginning;
2. the event's actor was a real person whose auth user was later deleted.

The function cannot tell them apart and neither can the schema — verified
directly against the database by the backend milestone. No application code path
deletes a profile, but the Supabase Admin API and the Studio user list both
expose auth-user deletion to an operator, so the state is reachable.

**So the UI says *"System or unavailable actor"*, and never:** a bare *System*,
*Automated system*, *System process*, *Deleted user*, or *Former user*. Each is a
claim about who acted that the evidence cannot support, and an audit surface is
the last place to state something stronger than the evidence. The wording is
pinned by `test/security/vendor_audit_log_boundary_test.dart`.

### `UNKNOWN` says nothing further

Two database states reach it: an actor belonging to **another Vendor**, and an
actor with no membership at all. Neither is distinguished and neither is
described — describing them is exactly the cross-tenant disclosure the
membership-scoped SQL join exists to prevent. The parser rejects a name arriving
with `UNKNOWN` for the same reason.

### Actor privacy

A `USER` name is rendered verbatim and nothing is appended: no id, no email, no
role, no organization. None of those is returned, and none exists to append. The
signed-in caller is never substituted for a missing actor — the boundary test
forbids the feature from reaching for the current session at all.

A **suspended** profile and a **deactivated** membership both still resolve to
`USER` with their name. That is deliberate on the backend's part: a suspended
person's past actions are precisely the history an operator reviews *after*
suspending them, and demanding `ACTIVE` would rewrite history as a side effect of
an unrelated administrative act.

---

## 7. Entity display semantics

`entity_display_name` is a **historical metadata snapshot**, extracted in SQL
through a closed per-entity-type key whitelist and guarded to
`jsonb_typeof = 'string'`:

| `entity_type` | metadata key | Label shown |
| --- | --- | --- |
| `VENDOR_PRODUCT` | `product_name` | Product |
| `RETAILER_ORGANIZATION` | `retailer_name` | Retailer |
| `RETAILER_SHOP` | `shop_name` | Retailer shop |
| `RETAILER_INVITATION` | `retailer_name` | Retailer owner invitation |
| `RETAILER_STAFF_INVITATION` | `retailer_name` | Retailer staff invitation |
| anything else | — | neutral humanization, name always null |

Because it is a snapshot and not a live join: a **deleted** entity still has a
name, a **renamed** entity keeps its historical one, and there is no existence
oracle for any id in any tenant.

Rendered as `Product · Espresso Beans`. When the name is null the row stays
visible and reads `Retailer shop · Affected item unavailable` — the absence is
*said*, never left blank and never filled in.

**Never done:** querying a live entity table, showing a raw uuid as the label,
showing raw metadata, reconstructing a name locally, exposing `entity_id`, or
offering navigation from a row.

---

## 8. Action-code presentation

The backend returns action codes **raw**, because no trusted mapping exists to
return: `action` and `entity_type` are plain `text` with only a non-empty check —
no enum, no lookup table, no reference data. The entity keeps the raw code and
the friendly wording is a presentation concern owned by
`vendor_audit_log_labels.dart`.

Seventeen codes are mapped, and every one was read from an
`insert into public.audit_logs` in the deployed backend:

| Code | Label |
| --- | --- |
| `RETAILER_ONBOARDED` | Retailer onboarded |
| `RETAILER_SHOP_ADDED` | Retailer shop added |
| `RETAILER_OWNER_INVITED` | Retailer owner invited |
| `RETAILER_OWNER_INVITATION_REVOKED` | Retailer owner invitation revoked |
| `RETAILER_OWNER_INVITATION_ACCEPTED` | Retailer owner invitation accepted |
| `STAFF_INVITATION_RESERVED` | Staff invitation reserved |
| `STAFF_INVITATION_SENT` | Staff invitation sent |
| `STAFF_INVITATION_RESENT` | Staff invitation resent |
| `STAFF_INVITATION_REVOKED` | Staff invitation revoked |
| `STAFF_INVITATION_DELIVERY_FAILED` | Staff invitation delivery failed |
| `STAFF_INVITATION_ACCEPTED` | Staff invitation accepted |
| `PRODUCT_CREATED` | Product created |
| `PRODUCT_UPDATED` | Product updated |
| `PRODUCT_ACTIVATED` | Product activated |
| `PRODUCT_DEACTIVATED` | Product deactivated |
| `PRODUCT_ASSIGNED_TO_RETAILER` | Product assigned to a Retailer |
| `PRODUCT_UNASSIGNED_FROM_RETAILER` | Product unassigned from a Retailer |

Roughly a third of these are filed against a **Retailer** organization by their
writers and so will not normally appear in a Vendor's own feed; they are mapped
anyway because *being written at all* is the standard for inclusion, and a code
that did appear should not fall to the fallback for want of one line.

**An unknown code is humanized neutrally** — the same underscores-to-spaces,
sentence-case shape the web uses, so both clients read the same:
`PRODUCT_STATUS_CHANGED` → *Product status changed*. It renders in exactly the
same style as a known code, **plus** its exact stored code beneath in subdued
tabular text (*"Recorded action code: …"*), because a reader meeting an
unfamiliar event is the reader who needs to know what was recorded. A code with
no printable characters — which the backend's non-empty check forbids and the
parser rejects — still produces a visible neutral label rather than a blank line.

**Never done:** mapping an unknown code to create / update / delete / success /
failure, inferring it from the entity type, hiding it, or making any decision
from a label. No tone anywhere in this feature encodes severity or outcome: there
is no such fact on an audit row to encode.

---

## 9. Loading more

An **explicit button** — *"Load older activity"* — not infinite scroll.
Deterministic (one press, one page), operable by a keyboard and a screen reader,
and it never walks an append-only table on a reader's behalf.

* Disabled while any read is in flight, and shows its own progress label.
* On failure: a warning alert, everything already loaded stays visible, and the
  button becomes *"Try again"* with the **same** cursor.
* When the history ends: the button is replaced by the end-of-history line, and
  further calls issue no request.
* A refresh resets pagination; the next older page anchors to the refreshed
  list's final row.

---

## 10. Session and stale-data isolation

`VendorShell`'s `_SessionIsolation` listener compares an identity —
`(authUserId, organizationId)` — rather than a boolean, so a **direct**
`Vendor A → Vendor B` transition with no intermediate state is detected on its
own terms. `VendorAuditLogCubit.clear()` joins the eight existing clears and runs
**before** anything is requested for the new identity.

Clearing drops, in one emit: the loaded events, the cursor position, the
end-of-history flag, both in-flight flags, both failures, and the de-duplication
set (which is derived from the events and so goes with them). `clear()` advances
the request token first, so an initial, refresh or older-page read already in
flight for the previous identity is dropped on arrival rather than repopulating
a feed that has just been emptied.

Triggers: sign-out, a direct Vendor A → Vendor B switch, a trusted organization
change, Vendor → another role, `SessionDenied`, `SessionUnavailable`, and a
Vendor context with no vendor block. An **identical** re-emitted session — the
shape a same-user token refresh takes — compares equal and costs no clear and no
reload.

Covered end to end in `test/features/users/vendor_session_isolation_test.dart`,
including that B's reload sends **no cursor at all**, so B cannot continue paging
from where A stopped.

---

## 11. Routing

One route, `/vendor/audit-logs`, inside the Vendor `ShellRoute`. It is **not**
nested and has no child, unlike the other four Vendor sections — there is nothing
to nest, because no audit detail read exists. `indexForLocation` keeps the Audit
Logs destination selected on the path, and browser back behaves exactly as it
does for the other Vendor destinations.

Retailer Owner, Retailer Manager and Sales Staff are redirected to their own
landing by `redirectFor`, and the shell builder refuses to construct a Vendor
shell for a non-Vendor session even if the guard were removed. That guard is
presentation, not security: Supabase decides again in SQL on every call.

**Why there is no detail route.** The backend audit searched the whole web
application for an audit-detail surface — a drawer, a modal, a `[auditLogId]`
route, an expandable row — and found none, so there is no shipped notion of what
audit "detail" would mean here. The only thing a detail read could add over the
list is precisely what the contract withholds: `metadata` as a whole,
`entity_id`, `ip_address`, `user_agent`. Adding one would not share an existing
capability; it would invent a new and more sensitive one.

---

## 12. Error handling

| Case | What the reader sees |
| --- | --- |
| Permission denied (`42501`) | *Not available to this account*, **no retry**, no permission code |
| Expired session | *Your session has ended* |
| Network timeout / backend unavailable | *Could not load this*, with a retry |
| Malformed response | the same outage state — never a denial, never an empty history |
| `22023` (unreachable from this client) | the same outage state |
| First page empty | *No activity recorded yet* — a fact, not a denial |
| Refresh failed with rows loaded | *This activity may be out of date*, rows kept |
| Older page failed | *Could not load older activity*, rows kept, retry offered |
| End of history | *You have reached the earliest recorded activity* |

Never exposed: PostgreSQL message text, SQLSTATE, PostgREST text, RPC names,
table or column names, policy names, permission codes, stack traces.

The three answers stay three answers: a denial is never converted to an empty
page, an empty page never raises, and an outage never reads as a denial.

---

## 13. Responsive UI and accessibility

**Layout.** A single-column reading surface capped at `SrSpacing.formMaxWidth`
(672) and centred — narrower than the catalogue pages on purpose, because a line
of prose stretched across a desktop browser is harder to scan, not easier.

* **Phones:** each event stacks — action, actor pill, affected item, timestamp.
  The actor pill sits in a `Wrap`, so at large text scale it runs onto its own
  line instead of overflowing.
* **Tablets, desktop and web:** above 520 logical pixels of card width the
  timestamp moves into its own right-hand column and the events align down the
  page.
* Events are grouped under a heading per **local** calendar day, computed with
  the same conversion the timestamps use, so a heading can never disagree with
  the lines beneath it.
* Verified with no overflow on 360×640, 390×844, 900×1000 and 1280×900, at
  normal and 1.6× text scale, in light and dark themes.

**Accessibility.** Each event is one spoken sentence — action, *"Recorded actor:
…"*, *"Affected item: …"*, *"Recorded at: …"* — so a screen-reader user is not
made to walk a pill and three lines to learn the same thing. Day headings are
marked as headers. The page heading, Refresh, Try again, Load older activity,
the load-more retry, the end-of-history line and the empty state all carry
labels. No meaning is carried by colour alone: every state has words, and the
one tinted element (the attributed-actor pill) says "a person is named here"
rather than "this is good".

Timestamps render in the device's own zone, `26 Jul 2026, 1:25 AM`. This is the
one date in the app that shows a time: every other date answers a day-grained
question, while the whole point of a history is *when*.

---

## 14. Tests

| File | Covers |
| --- | --- |
| `test/features/audit/vendor_audit_log_parsers_test.dart` | every field, both directions of the actor biconditional, forward compatibility, malformed input, and that no withheld column can reach the entity |
| `test/features/audit/vendor_audit_log_repository_test.dart` | the exact parameter set, the fixed page size, cursor rendering in UTC, success, empty page, `42501`, `22023`, transport, auth, malformed body |
| `test/features/audit/vendor_audit_log_cubit_test.dart` | first page, refresh replace/reset, older pages, cursor construction, tied timestamps, de-duplication, duplicate-request suppression, three separate failure surfaces, stale-response rejection, clearing |
| `test/features/audit/vendor_audit_log_flow_test.dart` | routing and role denial, the placeholder's removal, rendering of all four actor states, known and unknown codes, entity names present and absent, refresh, empty, first-load failure, load-more and its retry, end state, responsiveness, both themes, semantics |
| `test/security/vendor_audit_log_boundary_test.dart` | the source-level boundary: no key, no table read, no metadata, no ids, no IP or user agent, no email, no permission code, no write, no detail route, no navigation, no filter, no fabricated name, layering |
| `test/features/users/vendor_session_isolation_test.dart` | extended with the audit feed: clearing, cursor loss, three stale-response races, single reload, no-op on an identical identity, and that the Retailer / User / Role / Product clears still run |

---

## 15. Manual hosted verification

Not performed as part of this milestone. Steps, for an operator with a real
Vendor Super Admin account:

1. `flutter run -d chrome --dart-define-from-file=dart_defines.json`.
2. Sign in as a Vendor Super Admin.
3. Open **Audit Logs** from the Vendor drawer.
4. Compare the newest events against the web `/audit-logs` page — the same
   organization's rows, newest first.
5. Verify the ordering is strictly newest-first, and that two events recorded in
   one action (for example an onboarding that also adds a shop) keep a stable
   relative order across a refresh.
6. Verify the actor wording: a named colleague reads as their name; any row the
   backend could not attribute reads *"Unknown actor"* or *"System or unavailable
   actor"*, never a bare *"System"*.
7. Verify affected-item names match the product, Retailer or shop each event
   refers to, and that any row without a name still appears.
8. Press **Refresh**, and pull down on a narrow window. The list should update in
   place without flashing empty.
9. In the **web** application, make one safe administrative change — for example
   edit a product's description, or deactivate and immediately reactivate a
   product you own.
10. Refresh Flutter and confirm the new event appears at the head with the right
    action label, actor and affected item.
11. On an organization with more than 50 recorded events, press **Load older
    activity** and confirm older rows append beneath.
12. Confirm no event appears twice after a load-more followed by a refresh.
13. On an account with no recorded activity, confirm the empty state reads *"No
    activity recorded yet"* and not an access message.
14. Sign out and back in; confirm the feed is empty before the new read lands.
15. Where two Vendor Super Admin accounts are available, switch directly between
    them and confirm the first account's activity never appears under the second.

Do not delete a user to observe the actor ambiguity, and do not create
destructive production test data. No credentials, tokens, uuids or private
screenshots belong in this document.

---

## 16. Known limitations

* **List only.** No detail view, no drawer, no modal, no expandable row.
* **No raw metadata.** Only the five whitelisted name snapshots, extracted in
  SQL.
* **No entity navigation.** `entity_id` is not returned, so no row holds an
  address for the thing it refers to.
* **No actor navigation.** `actor_profile_id` is not returned either — it *is*
  the auth user id.
* **No filters** by action, entity, actor or date range, and **no search.** The
  web offers none, so there is no shipped filter semantics to share.
* **No exact total.** Keyset paging returns none, and an exact `COUNT` over an
  append-only table would be a full scan per page that is stale when computed.
  The count on screen is labelled *"events loaded"*.
* **Page size is fixed at 50** and is not configurable from any screen.
* **Action labels are maintained client-side.** There is no database label map to
  read, so a new action code needs a line in
  `vendor_audit_log_labels.dart` to gain friendly wording.
* **Unknown action and entity codes use neutral fallback text** and show the raw
  code; they are never guessed at.
* **`SYSTEM` cannot distinguish genuine system activity from a deleted actor.**
  The correct fix is an actor-name snapshot column on `audit_logs`, which is a
  schema change a read-only milestone must not make.
* **Entity display names exist only for the backend whitelist**, and only when
  the stored value is a JSON string.
* **Historical rows may lose actor attribution** after an auth user is deleted,
  because `actor_profile_id` is `ON DELETE SET NULL`.
* **A Vendor sees only Vendor-filed rows.** `RETAILER_OWNER_INVITATION_ACCEPTED`
  and every `STAFF_INVITATION_*` event is filed against the **Retailer**
  organization by its writer, so a Vendor's history shows an invitation being
  sent and revoked but not accepted. That is the shipped tenant model, and the
  page description says so rather than implying completeness it does not have.
* **Multi-Vendor selection keeps the existing lowest-organization-id
  tie-break.** A Super Admin of two Vendors reads the lowest-id Vendor's history,
  deterministically — the same rule every other Vendor RPC and the web's own
  `getVendorSuperAdminAccess()` already use.
* **The Vendor dashboard remains a placeholder.**
  `get_vendor_admin_dashboard_summary()` is the one outstanding Vendor contract
  and is not started here.
