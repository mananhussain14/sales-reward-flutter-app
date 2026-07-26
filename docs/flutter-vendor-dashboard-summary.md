# Flutter Vendor Dashboard summary

The Vendor Super Admin landing screen, backed by
`public.get_vendor_admin_dashboard_summary()`.

**Milestone:** replace the Vendor Dashboard placeholder with a real, read-only summary.
**Branch:** `feat/flutter-vendor-dashboard-summary`
**Backend base:** `92ce138`, aligned through
`20260805090000_mobile_vendor_dashboard_summary.sql`.
**Scope:** read-only. No write, no backend change, no web change.

The backend contract, its audit and its pgTAP suite live in the admin repository:

- `docs/mobile-vendor-dashboard-summary-audit.md`
- `supabase/migrations/20260805090000_mobile_vendor_dashboard_summary.sql`
- `supabase/tests/database/vendor_dashboard_summary_test.sql` (80 assertions)
- `lib/dashboard/vendor-dashboard-summary-contract.test.ts` (32 assertions)

---

## 1. Architecture

The same clean slice the five Vendor read features use, with one difference worth
naming: this screen has **two sources**, and neither is ever asked for the other's
fact.

```
lib/features/dashboard/
  domain/
    entities/vendor_dashboard_summary.dart        the four counts as ONE snapshot
    repositories/vendor_dashboard_repository.dart the zero-argument read
  data/
    datasources/vendor_dashboard_rpc_data_source.dart   the only file naming the RPC
    models/vendor_dashboard_summary_parser.dart         the strict parser
    repositories/supabase_vendor_dashboard_repository.dart  call → parse → classify
  presentation/vendor/
    cubit/vendor_dashboard_cubit.dart + _state.dart
    pages/vendor_dashboard_page.dart
    widgets/vendor_dashboard_copy.dart
    widgets/vendor_dashboard_metric_card.dart
    widgets/vendor_dashboard_quick_links.dart
```

| Layer | Responsibility | What it must not do |
| --- | --- | --- |
| Data source | Name the RPC once; invoke it | Read a table; send anything |
| Parser | Turn one row into one entity, or throw | Substitute a default, clamp, or round |
| Repository | Classify thrown vs unreadable | Restate authorization or derive a figure |
| Cubit | Hold one snapshot; drop stale answers | Merge fields; convert a failure to zeros |
| Page/widgets | Render four counts and their scope | Reach Supabase; invent a metric or a label |

`VendorDashboardCubit` is created and loaded once by `VendorShell`, alongside the
five existing Vendor cubits, so re-entering the route renders what is already held.
Presentation never touches `Supabase.instance.client`; the repository interface is
resolved from `getIt` and provided to the tree by `SaleRewardApp`, which is what
lets the widget tests stand the whole application up over a fake.

`ReadResult<T>` and the shared `Failure` discriminants are reused unchanged. No new
result type, no new failure discriminant, no second Supabase auth listener.

---

## 2. The exact RPC

```dart
client.rpc<Object?>('get_vendor_admin_dashboard_summary');
```

**Zero arguments.** Not an empty `params` map — no `params` argument at all. The
invoker type enforces it:

```dart
typedef VendorDashboardSummaryInvoker = Future<Object?> Function();
```

Nothing is sent. Not a user id, auth user id, profile id, membership id, Vendor
organization id, tenant id, organization name, role code, permission code, status,
date range, period or current-Vendor selector. There is nothing for the client to
supply, and therefore nothing for it to forge.

The Vendor is derived server-side from `auth.uid()` through
`get_vendor_super_admin_context()`, ordered by organization id and limited to one —
the same resolver, with the same tie-break, that every other Vendor RPC uses.

**One round trip replaces five.** The web issues one authorization RPC plus four
parallel `head: true, count: "exact"` table reads, each of which re-walks the
profile → membership → organization → role → permission chain through its own RLS
policy. This is one call and one statement.

---

## 3. The exact result contract

`returns table (...)`, so PostgREST renders it as a JSON **array**. An authorized
caller always receives **exactly one row**.

| Field | Type | Nullable | Zero possible | Scope |
| --- | --- | --- | --- | --- |
| `active_member_count` | `bigint` | **No** | Yes (not in practice) | **Vendor** |
| `catalog_active_role_count` | `bigint` | **No** | Yes | **Global** |
| `catalog_permission_count` | `bigint` | **No** | Yes | **Global** |
| `audit_event_count` | `bigint` | **No** | **Yes** | **Vendor** |

No id, name, status, timestamp, JSON, array or nested collection is returned. The
contract is counts and nothing else.

The one-row guarantee is **structural**, not a guard a later edit could drop: the
function body is a `select` with no from-clause and four scalar aggregate
subqueries. A select without a from-clause emits exactly one row, and an aggregate
over an empty set is `0` — not `NULL`, and not "no row". So a brand-new Vendor with
no members and no history receives one row of zeros, and zero rows is unreachable.

### Parser rules

`VendorDashboardSummaryParser.parse` throws `VendorDashboardFormatException`, which
the repository turns into `UnavailableFailure`. It never repairs, and each repair it
declines would be a specific lie.

| Input | Result |
| --- | --- |
| A list of one object with four valid counts | The entity |
| Any count `0` | Accepted — `0` is a real answer |
| A count up to `2^53 - 1` | Accepted, exactly |
| Unknown extra keys | Ignored (forward compatible) |
| Body is not a list | **Rejected** |
| Zero rows | **Rejected** — not an empty summary |
| More than one row | **Rejected** — the first is not taken |
| A row that is not an object | **Rejected** |
| A missing count | **Rejected** — not `0` |
| A null count | **Rejected** — `NOT NULL` in the contract |
| A negative count | **Rejected** — not clamped |
| A count as text, a bool, or fractional | **Rejected** |
| A count above `2^53 - 1` | **Rejected** — see below |

**All four fields are read before anything is constructed**, so a malformed fourth
count fails the whole summary. The four figures are one snapshot; there is no
partial summary to emit and no code path that could build one.

**`bigint` and Flutter web.** A Dart `int` compiles to a JavaScript number on the
web, which represents integers exactly only up to `2^53 - 1`. A larger `bigint` has
already lost precision inside `JSON.parse` before any Dart code runs. This build
therefore **rejects** a count above `maxSafeVendorDashboardCount` on *every*
platform, including the VM where it would fit — because two clients quietly
disagreeing about the same figure is worse than one honest "could not load this".

**No count passes through floating point.** The Role and Product parsers accept a
`num` whose value is integral, which is sound for the small `integer` columns they
read. It is not sound here: normalising a `double` is floating-point arithmetic, and
a `double` large enough to matter has already been rounded — the conversion would
launder a wrong number into a confident one. This reader takes an `int` and nothing
else. On Flutter web every whole JavaScript number *is* an `int`, so a well-formed
response parses there exactly as it does on the VM. A security test asserts that
`roundToDouble`, `toDouble`, `double.parse`, `num.parse`, `.ceil()` and `.floor()`
appear nowhere in the slice.

---

## 4. Where the organization name comes from

**The summary returns counts only, deliberately.** The name is read from the trusted
Session / PortalContext the application already holds, resolved by
`public.get_my_portal_context()`:

```dart
final SessionState session = context.watch<SessionBloc>().state;
final String? organizationName = session is SessionActive
    ? session.portalContext.vendor?.organizationName
    : null;
```

The rules, and each one is asserted:

1. **Counts come only from** `get_vendor_admin_dashboard_summary()`.
2. **The name comes only from the existing trusted session context.** No other file
   in the feature mentions `organizationName`.
3. **Neither the organization id nor the name is ever sent to the summary RPC.** It
   could not accept one — it takes zero arguments — but the rule stands so no future
   parameter is added to "make it explicit".
4. **`organizations` is never queried directly**, and neither is `profiles`,
   `organization_members`, `roles`, `permissions`, `audit_logs` or `auth.users`.
5. **Metric ownership is never inferred from the displayed name.** It is read
   through `portalContext.vendor`, so it is null unless the backend resolved a
   Vendor — there is no branch that could caption this page with a Retailer's name —
   and it is rendered as a *caption* rather than as the page title.

Because both contracts derive their organization from the same resolver with the
same lowest-organization-id tie-break, the name shown and the Vendor-scoped counts
shown describe the same organization by construction rather than by coincidence.

The name is **omitted** when the session carries none, never replaced with a
placeholder: a fabricated organization name on an administration screen is a claim
about whose data is on it.

---

## 5. The four metrics, exactly

Two of them are **not** this Vendor's. That is the single most misreadable thing on
the screen, so it is stated in the section heading, in a chip on every card, in each
card's hint, and in the spoken semantics — four channels, none of them colour alone.

### `active_member_count` — "Active members" — **Vendor-scoped**

Counts `public.organization_members` rows where `organization_id` is the trusted
Vendor **and** `status = 'ACTIVE'`.

Supporting wording: *"Active memberships in this Vendor organization."*

It **does not join `profiles`**, exactly as the web query does not. It includes an
ACTIVE membership whose profile is suspended; an ACTIVE membership with no role, one
role or several — one membership counts once, because the table is
`UNIQUE (organization_id, user_id)`.

It excludes INVITED, SUSPENDED and DEACTIVATED memberships, Retailer organization
memberships, Sales Staff memberships elsewhere, and any other Vendor's memberships.

Never called: *active profiles*, *active users with roles*, *invited users*,
*all users*.

### `catalog_active_role_count` — "Active role definitions" — **GLOBAL**

Counts every row in `public.roles` whose `status` is exactly `ACTIVE`. The status
column permits exactly `ACTIVE` and `INACTIVE`.

Supporting wording: *"Available across the shared role catalogue."*

`public.roles` has **no `organization_id`**. The figure is identical for every
authorized Vendor, is unaffected by role assignments and by member count, and is not
owned by the displayed organization. It includes active Retailer-oriented role
definitions.

Never called: *Your active roles*, *Vendor roles*, *Roles assigned in this
organization*.

### `catalog_permission_count` — "Permission definitions" — **GLOBAL**

Counts every row in `public.permissions`. There is no permission status column and
no inactive-permission concept, which is why the field is not named
`catalog_active_permission_count`.

Supporting wording: *"Available across the shared permission catalogue."*

Identical for every authorized Vendor; unaffected by role-permission mappings and by
assigned roles; not owned by the displayed organization; not the caller's own
permission set.

Never called: *Your permissions*, *Vendor permissions*, *Assigned permissions*,
*Active permissions*.

### `audit_event_count` — "Audit events" — **Vendor-scoped**

Counts every `public.audit_logs` row whose `organization_id` is the trusted Vendor.

Supporting wording: *"All recorded Vendor events."* A note beneath the section adds:
*"This is the all-time total for this organization. There is no time window and no
filter."*

No date or time window. Every action and entity type. Rows with a null actor are
included, and an erased actor does not remove the row. Another Vendor's rows and
null-organization rows are excluded.

Never called: *Recent events*, *Events today*, *This week*, *Last 30 days*.

**Why these two figures leak nothing.** The catalogue counts are counts of
*definitions written by migrations*, not of any tenant's data, usage, membership or
activity. Two Vendors seeing the same number is evidence of correctness, not of
disclosure — and the backend's pgTAP suite asserts exactly that by proving the two
tenant counts differ between two Vendors while the two catalogue counts are equal.

---

## 6. Authorization

The backend requires **all** of:

- Vendor Super Admin authority (via `get_vendor_super_admin_context()`);
- `ORGANIZATION_MEMBERS_READ`;
- `RBAC_READ`;
- `AUDIT_LOGS_READ`.

Flutter **does not inspect, send or display any of these codes**, and a security
test asserts that none of them appears anywhere in the feature.

Missing any one denies the **whole** summary. The RPC never returns partial metrics,
and the contract is deliberately non-partial: a nullable count is a trap, because
`null` and `0` are one typo apart in every client.

A denial arrives as `42501` and is mapped to `DeniedFailure` by `mapSupabaseError` —
the same generic answer for "not signed in", "not a Vendor Super Admin", "your
membership is suspended" and "your role no longer holds one of the three
permissions". The screen renders `SrFailureView`'s denial copy, which:

- offers **no retry** (the same call would return the same answer);
- says nothing about whether anything exists;
- **renders no card at all** — never a zero-filled grid.

Route guards are unchanged and continue to deny Retailer Owner, Retailer Manager and
Sales Staff. The route is **never** authorized from a count value.

> The guard is presentation, not security. Supabase remains the authority: if the
> guard were deleted, another role reaching `/vendor/dashboard` would see a screen
> whose one call returns `42501`.

---

## 7. Result semantics

| Situation | Behaviour |
| --- | --- |
| Authorized | One row, four non-null counts, **all four rendered atomically** |
| Authorized, no tenant data | `0` for members and audit events; catalogue counts stay non-zero |
| Denied (`42501`) | One generic access-denied state. **No zero-filled cards.** |
| Operational failure | Retryable failure. **Never converted to zeros.** |
| Malformed / zero-row / multi-row | Retryable unavailable failure. **No partial render.** |
| Refresh failure with figures held | Stale notice above the cards; the cards stay |

`0` means **none**. It is never how a denial or an outage is represented.

---

## 8. Refresh behaviour

Two affordances, one action: pull-to-refresh (what a phone user reaches for) and a
header button (what a browser user reaches for, and what a keyboard or screen-reader
user can operate). Both call `VendorDashboardCubit.refresh()`.

1. It calls the **same zero-argument RPC** again.
2. It **replaces the complete summary atomically**. `copyWith` takes a whole
   `VendorDashboardSummary` and there is deliberately no per-count setter — the four
   figures come from one statement and describe one instant, so a state that could
   update one of them would be a state that could show two moments at once.
3. It **preserves the previous summary while refreshing**. The cards do not blank;
   `isRefreshing` drives the button spinner and the pull indicator.
4. On failure it **preserves the stale summary** and surfaces a non-blocking warning
   (`isStale`). The figures are still the last thing the backend actually said, and
   discarding them would replace real counts with nothing — converting them to zeros
   would replace them with a lie.
5. The Refresh button is the retry, so there is one action rather than two.
6. **Duplicate requests are impossible**: `refresh()` returns immediately while
   `isRefreshing`, so a repeated tap and a pull landing together produce one call.
7. **Stale responses are ignored after a session change** — see § 9.

A refresh with nothing loaded (a pull after a failed first read) shows the loading
state instead, because there is nothing on screen to preserve.

---

## 9. Session and stale-data isolation

`VendorShell._SessionIsolation` is extended to the Dashboard. It listens to
`SessionBloc` — the application's existing session lifecycle — and **adds no second
Supabase auth listener**.

The trigger is an **identity**, not a boolean:

```dart
typedef _VendorIdentity = ({String? authUserId, String organizationId});
```

A boolean "is this still a Vendor session?" cannot tell one Vendor Super Admin from
another, so a direct A → B switch would read as no change at all.

On logout, a direct Vendor A → Vendor B switch, a trusted-organization change, a move
to another role, a denial, an unavailable session or an invalidation, the listener
calls `clear()` on all ten cubits **before** anything is requested for the new
identity. For the Dashboard that drops:

- the summary counts (both the Vendor half and the global half);
- the loading state and the refresh flag;
- the failure.

**The whole snapshot goes, not just the tenant half.** Keeping the two global
catalogue counts would leave a summary carrying only half of itself — a shape no
backend answer ever produces, and a screen the contract could not explain.

`clear()` advances a request token first, so an answer already in flight for the
previous identity is **dropped on arrival** rather than repopulating state that has
just been emptied. Both the initial read and a refresh are invalidated this way, and
a late failure cannot set an error on the new Vendor's screen either.

An **identical re-emitted session** — the shape a same-user token refresh takes —
compares equal, so it costs no clear and no duplicate load.

---

## 10. Routing

The existing Vendor Dashboard route, unchanged:

```
/vendor/dashboard
```

It is `VendorNavigation.dashboard` and `VendorNavigation.model.landingPath`, so it
remains where a Vendor Super Admin lands after sign-in.

- Vendor Super Admin enters; the Vendor shell chrome stays visible.
- `indexForLocation` keeps the **Dashboard** destination selected.
- Retailer Owner, Retailer Manager and Sales Staff are redirected to their own home.
- **No new detail route.** The contract returns four scalars and nothing
  addressable, so no figure holds an address for anything.
- Browser back/forward is unchanged. Quick links use `context.go` — these are the
  shell's own top-level destinations, so arriving at one leaves history exactly where
  the drawer would have left it, rather than stacking a dashboard beneath a
  directory.

---

## 11. Quick links

Five shortcuts, to the five Vendor areas that are built: **Retailers, Users, Roles,
Products, Audit Logs**.

There is **no** shortcut to Campaigns, Claims, Coins, Payouts, Reports or Settings.
Those are "Soon" entries in the navigation model with no route at all, and an
affordance that cannot act is a promise about a feature that has not been built. No
disabled tile stands in for one.

**No quick link carries a figure.** The summary returns no Retailer, Product, shop,
assignment or invitation count, so a number on any shortcut would be one this screen
invented. A widget test walks every shortcut card and fails on any digit; a security
test asserts every link path is a `VendorNavigation` constant rather than a literal
that could drift from the router.

---

## 12. Error handling

Everything goes through `mapSupabaseError` and `SrFailureView`, unchanged.

| Cause | State | Retry |
| --- | --- | --- |
| `42501` | "Not available to this account" | No |
| Expired session | "Your session has ended" | No |
| Network timeout / transport | "Could not load this" | Yes |
| Backend unavailable / unknown SQLSTATE | "Could not load this" | Yes |
| Malformed, zero-row or multi-row body | "Could not load this" | Yes |
| Refresh failure with figures held | Inline stale warning | Yes, via Refresh |

Nothing user-facing ever carries PostgreSQL text, a SQLSTATE, PostgREST text, the
RPC name, a table name, a permission code or a stack trace. The `Failure`
discriminants carry no fields at all, so no message can ride along, and the parser's
own developer-facing reason names a *field* rather than echoing a value from the
response.

---

## 13. Responsive UI and accessibility

The page reuses the SalesReward design tokens and shared widgets throughout:
`SrPageBody`, `SrPageHeader`, `SrSectionHeader`, `SrCardGrid`, `SrCard`, `SrBadge`,
`SrButton`, `SrAlert`, `SrShortcutCard`, `SrLoadingView`, `SrFailureView`.

- **Phones** stack the metric cards in one column; `SrCardGrid` pairs them once the
  width reaches 520 logical pixels. Below that a second column would be too narrow
  for the 30px `tabular-nums` figure beside the 40px disc.
- **Tablets and Flutter web** get the two-up grid inside `max-w-6xl`, so a card never
  stretches across a desktop browser.
- The two metric groups are **separate headed sections**, so the Vendor/catalogue
  split is visible at every width. No desktop table is compressed onto a phone.
- Light and dark themes are both covered; every colour comes from `context.sr`.
- Nothing overflows horizontally at 360×640, 390×844, 900×1000 or 1280×900, and at a
  1.8× text scale on the smallest surface.

Semantics:

- The page heading and the eyebrow come from `SrPageHeader`.
- The organization name is one node: *"Signed in to &lt;name&gt;"*.
- Each metric card is **one** node reading *"label: value. scope. hint."* — one
  sentence rather than four fragments — with the visual tree excluded beneath it, so
  the figure is not announced twice.
- The scope is **spoken**, so the distinction survives for a reader who never sees
  the section heading it sits under.
- Refresh is a labelled button; the retry inside `SrFailureView` is too.
- Each quick link announces *"Open &lt;area&gt;"* rather than leaving a screen reader
  to infer a destination from an arrow glyph.
- The stale notice is an `SrAlert`, which is a live region.
- **Colour is never the only channel.** The scope chip carries a label *and* a glyph,
  and the hint states the scope in words.

---

## 14. Tests

| Suite | File | Covers |
| --- | --- | --- |
| Parser | `test/features/dashboard/vendor_dashboard_summary_parser_test.dart` | Valid, all-zero, large, malformed, missing, wrong type, negative, out-of-range, zero rows, multiple rows, no name/id/status field |
| Repository | `test/features/dashboard/vendor_dashboard_repository_test.dart` | Zero arguments, no params map, one RPC name, no table read, success, all-zero, malformed, zero-row, multi-row, `42501`, transport, auth, no derivation |
| Cubit | `test/features/dashboard/vendor_dashboard_cubit_test.dart` | Loading, success, all-zero, first-load failure, retry, atomic refresh, stale preservation, duplicate suppression, stale initial/refresh responses, clearing |
| Widget & routing | `test/features/dashboard/vendor_dashboard_flow_test.dart` | Role guards, placeholder removal, organization name, four cards, truthful labels, denial without zeros, refresh, stale state, quick links, responsive, themes, semantics |
| Session isolation | `test/features/users/vendor_session_isolation_test.dart` | Direct A → B, stale initial/refresh, clear-before-B, single reload, no-op re-emit, organization change, sign-out, role change, denial, invalidation |
| Security boundary | `test/security/vendor_dashboard_boundary_test.dart` | Keys, arguments, table reads, derivation, floating point, fabricated zeros, permission codes, name source, wording, writes, layering |

**Total: 2008 Flutter tests, all passing.**

The five earlier Vendor features (Retailers, Users, Roles, Products, Audit Logs) are
unchanged and their suites pass unmodified.

---

## 15. Manual hosted verification

Not performed as part of this milestone. Run against the hosted project:

1. `flutter run -d chrome --dart-define-from-file=dart_defines.json`.
2. Sign in as a **Vendor Super Admin**.
3. The Dashboard is the landing route; confirm it opens at `/vendor/dashboard`.
4. Open the web admin dashboard at `/` side by side and compare **all four counts**.
   They must match exactly.
5. Confirm the **Vendor organization name** under "Signed in to" matches the web
   header's *"Managing &lt;name&gt;"*.
6. Confirm **Active members** equals the web's "Active Members" card, and equals the
   number of `ACTIVE` rows on the Users screen.
7. Confirm **Active role definitions** equals the web's "Active Roles" card.
8. Confirm **Permission definitions** equals the web's "Permissions" card.
9. Confirm **Audit events** equals the web's "Audit Events" card.
10. Confirm the two catalogue cards read *"Available across the shared … catalogue"*
    and sit under **Shared access catalogue**, and that neither says "your".
11. Press **Refresh**; the figures reload and no card blanks.
12. Make a **safe** administrative change on the web that records an audit event —
    for example renaming a test Retailer back and forth, or toggling a test product's
    status and restoring it. Do **not** modify production roles or permissions merely
    to move the global catalogue counts.
13. Refresh the mobile Dashboard and confirm **Audit events** has increased.
14. Follow each of the five quick links and confirm each opens its Vendor area and
    that browser back returns to the Dashboard.
15. Log out. Confirm the Dashboard clears, that signing back in re-reads it, and that
    no previous figure is visible at any point.

Record only outcomes. No credentials, tokens, UUIDs, organization names or private
screenshots belong in this document.

---

## 16. Known limitations

1. **Only the four web-backed summary metrics exist.** Nothing else is shown,
   because nothing else appears on the web dashboard, and inventing a metric here
   would freeze a product decision into a client.
2. **No Retailer count.**
3. **No Product count.**
4. **No shop count and no assignment count.**
5. **No invitation count** — and none could honestly exist. Both invitation tables in
   the schema are Retailer-scoped; nothing invites a user into a Vendor organization,
   and a Vendor user's invited state is `organization_members.status = 'INVITED'`,
   which is deliberately excluded from the active member count.
6. **No charts, trends, percentages, comparisons or time series.**
7. **No revenue, sales, receipt, claim, coin, payout or campaign analytics.**
8. **The role and permission metrics are GLOBAL catalogue figures**, identical for
   every authorized Vendor. The web still labels them "Active Roles" and
   "Permissions" on an organization overview; correcting the *web* labels is a
   visible web change and remains out of scope.
9. **Audit events is all-time.** There is no window, and the product defines none.
10. **The exact audit count may grow indefinitely**, and its cost is proportional to
    the Vendor's history. That is accepted rather than optimised away, because it is
    exactly what the web card already does — a planner estimate or a time window here
    would make the two clients disagree.
11. **Counts above `2^53 - 1` are rejected rather than rendered**, so both clients
    show the same figure or neither does. Unreachable in practice.
12. **Multi-Vendor callers see the lowest-organization-id Vendor**, deterministically,
    for both the name and the counts — the shipped behaviour of every Vendor RPC,
    preserved rather than redesigned.
13. **Vendor profile editing remains unimplemented**, and no affordance hints at it.
14. **Every remaining write milestone is separate**: Vendor profile, Product writes,
    Vendor user writes, invitation writes, campaigns, claims, coins, payouts and
    reports are untouched by this branch.
