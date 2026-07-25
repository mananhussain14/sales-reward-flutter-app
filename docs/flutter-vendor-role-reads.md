# Vendor Role list and detail

**Milestone.** Replace the Vendor **Roles** placeholder with a real, read-only,
responsive experience: the shared role catalogue, one role opened by id, and the
permissions mapped to it.

**Branch.** `feat/flutter-vendor-role-reads`

**Backend.** `20260802090000_mobile_vendor_role_reads.sql` (backend `182fe25`),
audited in `docs/mobile-vendor-role-reads-audit.md`. Nothing in the backend or
web repository was touched by this milestone.

**Scope.** Read-only. No role is created, edited, deleted, activated,
deactivated or duplicated; no permission is assigned or removed; no role is
assigned to or removed from a member. None of those has a backend at all — on
web or mobile — so this is not "not yet wired up": the whole Roles surface is
read-only in the shipped product, and `authenticated` holds `SELECT` and nothing
more on all four RBAC tables.

---

## 1. What a Vendor Super Admin can now do

1. Open **Roles** and read the shared catalogue, loaded once.
2. See each role's name, status, description (when present), permission count,
   assigned-member count for their own Vendor, and creation date.
3. Search the loaded roles by name.
4. Filter by the statuses actually present in the result.
5. Refresh — by pull on a phone, by button on web and tablet.
6. Open one role at `/vendor/roles/:roleId`.
7. Read its definition and the permissions mapped to it.
8. Tell an `ACTIVE` role from an `INACTIVE` one at a glance, and read plainly
   that an inactive role's mapped permissions are **not currently effective**.
9. Land on one safe state for an unknown or malformed role id, with no retry and
   no hint about existence.
10. Come back to a catalogue that is still loaded.

Everything private to the Vendor — the member counts, the open role, its
permissions, the search term and the filter — is cleared on logout, on a direct
Vendor A → Vendor B change, on an organization change, and on any session
invalidation.

---

## 2. Architecture

Clean architecture and Cubit/BLoC, matching Vendor Retailers and Vendor Users.

```
lib/features/roles/
  domain/
    entities/vendor_role_status.dart         ACTIVE | INACTIVE | unknown
    entities/vendor_role_summary.dart        one catalogue row
    entities/vendor_role_detail.dart         a typedef — see § 2.1
    entities/vendor_role_permission.dart     name + nullable description
    repositories/vendor_role_repository.dart three reads, no writes
  data/
    models/vendor_role_parsers.dart          strict parsers, id-shape guard
    datasources/vendor_role_rpc_data_source.dart  the only file naming an RPC
    repositories/supabase_vendor_role_repository.dart  call → parse → classify
  presentation/vendor/
    cubit/vendor_role_list_cubit.dart   + _state.dart
    cubit/vendor_role_detail_cubit.dart + _state.dart
    pages/vendor_roles_page.dart
    pages/vendor_role_detail_page.dart
    widgets/vendor_role_badges.dart               status pill, count line
    widgets/vendor_role_card.dart                 card + responsive grid
    widgets/vendor_role_copy.dart                 every user-facing sentence
    widgets/vendor_role_effectiveness_notice.dart the inactive-role notice
    widgets/vendor_role_filter_bar.dart           search + status chips
    widgets/vendor_role_formatting.dart           dates and count phrases
    widgets/vendor_role_permission_tile.dart      one mapped permission
```

Wiring: `lib/app/di/injector.dart` (production graph),
`lib/app/app.dart` (injectable repository for tests),
`lib/app/shells/vendor/vendor_shell.dart` (cubit ownership and session
isolation), `lib/app/shells/vendor/vendor_navigation.dart` (paths),
`lib/app/router/app_router.dart` (nested routes replacing the placeholder).

Presentation never touches `Supabase.instance.client`. RPC names, RPC arguments,
Supabase maps, PostgREST exceptions and response parsing all stay in the data
layer, and no cubit state holds a raw map. Asserted in
`test/security/vendor_role_boundary_test.dart`.

### 2.1 Why `VendorRoleDetail` is a typedef, not a second class

`get_vendor_role_detail(uuid)` returns the **identical column set** to
`list_vendor_roles()`. `public.roles` has seven columns; five are already in the
list, the sixth is `code` (refused — see § 4), and the seventh is `updated_at`
(the seed's upsert rewrites it on every run, so it records when the seed last
ran). The backend states the consequence directly: *"One Flutter model therefore
deserializes both reads, and a future column has to be added to both or to
neither."*

So `VendorRoleDetail` is `typedef VendorRoleDetail = VendorRoleSummary`. A second
class with the same seven fields would be a second place to add that future
column, and only one of the two could be right.

> Contrast `VendorUserDetail`, which **is** its own class: that read returns the
> list columns *plus* `deactivated_at`, so the two shapes genuinely differ.

### 2.2 Shared abstractions reused, not re-invented

`ReadResult<T>`, `Failure` / `mapSupabaseError`, `SrResponsiveGrid`, and the
whole `Sr*` design system are used as-is. No new result type, no new failure
type, no second auth or session listener.

---

## 3. Exact backend operations

### `public.list_vendor_roles()`

**Zero arguments.** Returns, ordered by `role_name` then `role_id`:

| Column | Type | Rule |
| --- | --- | --- |
| `role_id` | `uuid` | non-null; the widget key and the detail selector |
| `role_name` | `text` | non-null; the display name, never the code |
| `role_description` | `text` | **nullable**, never fabricated |
| `role_status` | `text` | non-null; `ACTIVE` or `INACTIVE` |
| `role_created_at` | `timestamptz` | non-null |
| `permission_count` | `integer` | non-null; `0` for a role with no mappings |
| `assigned_member_count` | `integer` | non-null; **the caller's Vendor only** |

### `public.get_vendor_role_detail(p_role_id uuid)`

One argument. Identical column set. One row, or zero.

| Situation | Result |
| --- | --- |
| Authorized, real role | exactly one row |
| Unknown uuid | zero rows |
| Id belonging to another table | zero rows — indistinguishable |
| `null` | zero rows — indistinguishable |
| `INACTIVE` role | one row, `role_status = 'INACTIVE'` |
| Unauthorized | `42501`, one generic message |

### `public.list_vendor_role_permissions(p_role_id uuid)`

One argument. Returns `permission_name` (non-null) and
`permission_description` (**nullable**), ordered by permission name then
permission id — the id is ordered *on* and never returned.

An empty list means "this role grants nothing" **and** "this id names no role",
indistinguishably. The detail read is what tells them apart (§ 6).

Requires only `RBAC_READ`, where the two counting reads also require
`ORGANIZATION_MEMBERS_READ`. The client neither knows nor could enforce that
split; it is stated here because it is why a permission read can succeed while a
detail read is refused.

---

## 4. The global catalogue, and what follows from it

`public.roles`, `public.permissions` and `public.role_permissions` carry **no
`organization_id`**. They are one catalogue of role and permission *definitions*
shared by every organization on the platform. What is per-organization is the
*assignment*, which lives in `member_roles`.

Three consequences, each deliberate:

1. **"The roles available in the trusted Vendor organization" is the whole
   catalogue.** There is no Vendor-scoped subset to return, and the web `/roles`
   page already shows a Vendor Super Admin all six seeded roles today.
2. **Retailer Owner, Retailer Manager and Sales Staff appear in a Vendor's Roles
   screen.** They are shown, unlabelled and unfiltered. This is not a tenant
   leak: it is the shipped behaviour of a wholesale-gated catalogue.
3. **There is no "another Vendor's role" to leak.** The non-leaking result is the
   one for an id that names *no* role at all.

The Flutter screen therefore:

* **shows every returned role**, in the backend's order;
* **explains the sharing, twice** — in the page description and in a note beside
  the rows, so a reader who finds *Retailer Owner* in their own catalogue can
  read why;
* **invents nothing.** No Vendor/Retailer label, no system/custom badge, no scope
  or kind, no grouping by guessed product area. There is no such column, so any
  such label could only have come from the role **name** — which would be
  inventing a taxonomy and would immediately disagree with the web.

`test/security/vendor_role_boundary_test.dart` asserts that no source models a
scope, kind, `is_system`, `is_custom` or `is_editable`, that nothing branches on
a role name, and that nothing filters the catalogue by role identity.

### `assigned_member_count` — the one tenant-scoped value

It counts memberships of the **calling** Vendor Super Admin's own Vendor that
hold this role. `m.organization_id` is compared against a Vendor derived from
`auth.uid()` in SQL, never against a parameter.

* A Retailer role reads **0** for a Vendor — the true answer, not a hidden row.
* Membership status, profile status and role status are **not** filtered, so it
  is an *assignment* count and not a headcount of active staff. A retired
  definition still held by four people reports 4.
* Wording carries the scope: **"3 members in your Vendor"**, **"No members in
  your Vendor"** — never a bare "3 members", which beside a global row would read
  as a platform-wide figure.

Because it is private, the whole catalogue is cleared on a session change (§ 10).

---

## 5. Role status, and mapped versus effective permissions

`public.roles.status` is constrained to `ACTIVE` and `INACTIVE`. **Permissions
have no status at all**: `public.permissions` has seven columns and
`public.role_permissions` has three, and neither carries one. An inactive
assigned permission is not merely unseeded — it is *unrepresentable*.

What *can* make a mapped permission ineffective is the **role's** status.
`public.has_organization_permission()` carries no permission-status predicate
(there is no column) but does filter on `r.status = 'ACTIVE'`. An `INACTIVE` role
therefore grants **nothing**, however many permissions remain mapped to it.

The screens follow that exactly:

* Role status is **prominent on both list and detail**, as a pill with its own
  word and glyph — never colour alone.
* On an `INACTIVE` role detail, an alert sits directly above the permission
  section: *"This role is inactive. Its mapped permissions are not currently
  effective. They are still listed below so you can see what the definition
  holds."* It has a glyph, a bold title and a semantics label.
* **All mapped permissions are still displayed**, and `permission_count` is
  unchanged. Filtering them out would make a retired role look permission-less
  and hide the state the screen exists to explain.
* **No permission carries an active/inactive badge** — there is no such column.
* Nothing implies an inactive role currently grants access, and no copy describes
  the list as "your permissions" or "effective permissions". The section is
  titled *Permissions* and described as *"the permissions mapped to this role
  definition"*.
* **Nothing computes authorization locally.** The list is configuration
  information; the backend decides the real question again on every call.

An **unrecognised** status (a backend newer than the app) gets its own neutral
notice — *"whether its mapped permissions are effective cannot be shown here"* —
never an affirmative one. Effectiveness is a positive test against `ACTIVE`
(`grantsMappedPermissions => this == active`), so no future token can reach
"effective" by failing to match `INACTIVE`.

---

## 6. Loading

**Catalogue.** `list_vendor_roles()` is called **once**, when the Roles cubit is
first read — which happens when the Roles directory is first opened, not when the
Vendor shell mounts. `BlocProvider` builds each cubit lazily, so opening
Retailers never fetches Roles.

**Detail.** Strictly sequential:

1. `get_vendor_role_detail(p_role_id)` — once.
2. **Only after a row comes back**, `list_vendor_role_permissions(p_role_id)` —
   once.

The ordering is load-bearing. The companion answers an empty list for a
genuinely permission-less role *and* for an id that names no role. Zero rows from
the detail read is the authoritative "this id is not a role", so when the detail
is inaccessible the permission read is **not issued at all**.

Not done, anywhere:

* no detail call per row in the list;
* no permission call per role;
* no separate member-count, permission-count or assignment query — both counts
  are scalar aggregates on the row;
* no fetch on rebuild — `open` is idempotent for the id already showing, and the
  page starts it from `initState`;
* no simultaneous refreshes — a second refresh while one is in flight is a no-op;
* no pagination, invented or otherwise. The RPC is unpaginated by design.

**State survives navigation.** The cubits belong to the Vendor shell, so opening
a role and coming back renders rows already held. A background refresh keeps the
rows on screen rather than blanking them.

---

## 7. The route selector

```
/vendor/roles
/vendor/roles/:roleId
```

The selector is `roles.id` and **never** the role code, role name, index position
or a permission code. `roles.code` is `UNIQUE` and would address a role just as
precisely — which is exactly why the backend refuses it: the codes are the
literals the RLS policies and the authorization helpers match on, and accepting
one would put authorization vocabulary in a client's hands.

The detail route is **nested** under the list, so the Roles destination stays
selected while a role is open (longest matching prefix wins) and browser/back
pops to a catalogue that is still loaded.

Holding a role id grants nothing: the reads derive the Vendor from `auth.uid()`
and use the id only to select which already-authorized catalogue row is read.

---

## 8. Parser rules

Every reader throws `VendorRoleFormatException` rather than substituting a
default. The repository converts that to `UnavailableFailure` — never a denial,
never an empty catalogue, never a fabricated row.

| Input | Result |
| --- | --- |
| valid role row | parsed |
| valid detail row | parsed (same reader) |
| valid permission row | parsed |
| `role_description` null / absent / blank | **null**, never fabricated |
| `permission_description` null / absent / blank | **null**, never the name |
| `role_status` = `ACTIVE` / `INACTIVE` | mapped |
| unrecognised `role_status` | `unknown` — never `active`, never effective, raw token never displayed, role still listed |
| malformed `role_id` | format error |
| missing / empty `role_id` | format error |
| missing / blank / wrong-typed `role_name` | format error |
| missing / blank `role_status` | format error |
| missing / malformed `role_created_at` | format error |
| missing / non-integer / negative `permission_count` | format error |
| missing / non-integer / negative `assigned_member_count` | format error |
| `role_description` of the wrong type | format error |
| missing / blank `permission_name` | format error |
| `permission_description` of the wrong type | format error |
| one malformed row among many | **the whole read fails** |
| detail returning zero rows | `null` — a success |
| detail returning several rows | format error |

A negative count is **refused rather than clamped**: `count(*)` cannot be
negative, so clamping would report "no permissions mapped" on the strength of a
number the backend never produced. Integral doubles (`3.0`) are accepted, because
JSON has one number type; strings are not.

Ordering is preserved exactly — nothing is sorted, de-duplicated or filtered. A
`Set` over permissions would hide a genuine backend duplication bug rather than
prevent one.

**The count invariant.** `permission_count` is by construction the number of rows
the companion returns, and the backend's pgTAP suite asserts it for every role. A
mismatch is handled **defensively but honestly**: a note appears, every returned
row is still rendered, and the count is still reported unchanged. Nothing is
dropped to match the number and the number is not adjusted to match the rows.

---

## 9. Error semantics

### Catalogue

| Situation | Screen |
| --- | --- |
| success | the catalogue |
| empty response | defensive empty state — no retry offered |
| `42501` | "Not available to this account", no retry |
| expired session | the existing `SessionBloc` handling |
| network failure | retryable failure view |
| malformed response | retryable failure view |
| database outage | retryable failure view |
| refresh failure with rows loaded | rows retained + a non-destructive warning |

### Detail

| Situation | Screen |
| --- | --- |
| one row | the detail |
| zero rows | "Role not available", **no retry** |
| unknown or malformed id | the same state, byte for byte |
| operational failure | retryable failure view |
| permission failure after a successful detail | detail retained + a section-level retry that re-reads **only** the companion |

Nothing on screen says "This role belongs to another Vendor" (there is no such
thing — the catalogue is global), "This is a Retailer role" (that would be
inferred from a name), or "You do not own this global role". No raw PostgreSQL
message, SQLSTATE, PostgREST text, function name, table name, policy name or
stack trace can reach a screen: `mapSupabaseError` returns a discriminant and the
backend's own text stops at the repository.

### Malformed route — `/vendor/roles/not-a-uuid`

Validated locally, before any request:

* **zero** detail RPC calls;
* **zero** permission RPC calls;
* the same "Role not available" presentation a valid unknown id produces;
* no raw `22P02` cast error, and no retry action.

A **valid but unknown** uuid is a legitimate question, so it is asked: exactly one
detail call, zero permission calls.

---

## 10. Session and private-data isolation

Role *definitions* are global. `assigned_member_count` is not, and it rides on the
same rows — so the catalogue is cleared like any other private Vendor data.

`VendorShell`'s existing `_SessionIsolation` listener was **extended**, not
duplicated. There is no second auth or session listener anywhere. It compares an
identity — `(authUserId, organizationId)` — rather than a boolean, so a **direct**
Vendor A → Vendor B transition with no intermediate state is detectable.

On any identity change it clears, before anything is requested for the new
identity:

* role summaries and their assigned-member counts;
* the selected role detail;
* its permission rows;
* the search term and the status filter;
* every refresh and error flag.

`clear()` advances a request token first, so a response already in flight for the
previous identity is dropped on arrival rather than repopulating state that has
just been emptied. This holds for the catalogue read, the detail read and the
permission read independently.

A **same-user token refresh with an unchanged effective identity** compares equal
and is ignored: no clear, no reload, and a half-typed search term survives.
An organization change does clear and reload, because the counts describe a
different tenant.

---

## 11. Responsive UI and accessibility

**Layout.** One column on a phone; two from 800px; three from 1150px, via the
shared `SrResponsiveGrid`. The thresholds are wider than the Retailer grid's
because a role card carries a wrapping description and two full-sentence count
lines, and narrower than the User grid's, which carries two prefixed pills and a
row of chips. Content is capped at `SrSpacing.contentMaxWidth`, so nothing
stretches across a desktop browser. Deliberately cards, not a table: a table on a
phone is either horizontally scrolled or squeezed unreadable.

**Phones.** Stacked cards; the status pill wraps to its own line under pressure;
long names truncate at two lines and long descriptions at three; count sentences
wrap rather than compress; permissions are simple vertical rows with no maxLines
at all, because there is no code beside a permission to disambiguate a truncated
name.

**Refresh.** Pull-to-refresh on mobile, a header button everywhere — the button
is what a keyboard or screen-reader user can actually operate.

**Themes.** Light and dark, through the `Sr*` design system. Covered by tests in
both modes for the catalogue and for an inactive role detail.

**Accessibility.** Semantics are attached to:

* each role card — one spoken sentence carrying name, status, description and
  both counts, with a `button` flag and an "View details" hint, and never an id;
* the status pill — "Role status: Active";
* the permission count — "6 permissions mapped";
* the member count — "2 members in your Vendor" / "No members in your Vendor";
* the search field, each status chip (with its subject and a `selected` flag),
  the refresh button, every retry and the back button;
* each mapped permission — "Permission: Read roles. …" as one node;
* the inactive-role notice — "Inactive role. Mapped permissions are not currently
  effective."

Nothing is carried by colour alone: every status has a word and a glyph, the
notice has a title and a full sentence, and selection is carried by a check glyph
and a semantics flag as well as by fill. Large text scaling (1.6×) is covered.

---

## 12. Tests

| Suite | File |
| --- | --- |
| Parsers and domain | `test/features/roles/vendor_role_parsers_test.dart` |
| Data source and repository | `test/features/roles/vendor_role_repository_test.dart` |
| Catalogue cubit | `test/features/roles/vendor_role_list_cubit_test.dart` |
| Detail cubit | `test/features/roles/vendor_role_detail_cubit_test.dart` |
| Widgets, routing, end to end | `test/features/roles/vendor_role_flow_test.dart` |
| Source safety | `test/security/vendor_role_boundary_test.dart` |
| Session isolation | `test/features/users/vendor_session_isolation_test.dart` (extended) |
| Fakes and fixtures | `test/support/vendor_role_fakes.dart` |

The flow suite drives the **real** router, shell and cubits over a fake
repository, and the two malformed/unknown-route tests drive the **real**
repository over a counting data source, so the id-shape guard is genuinely in the
path rather than stubbed out.

---

## 13. Manual verification (hosted)

Not performed as part of this milestone. Run against hosted Supabase with an
existing Vendor Super Admin account. **Record no credentials, tokens, private
UUIDs, service keys, user names or screenshots** in any follow-up note.

1. `flutter run -d chrome --dart-define-from-file=dart_defines.json`.
2. Sign in as a Vendor Super Admin.
3. Open **Roles** from the drawer.
4. Confirm the shared catalogue appears, and that the page states it is shared.
5. Compare role names, statuses and descriptions against the web `/roles` page —
   they should match exactly, in the same order.
6. Confirm Retailer Owner, Retailer Manager and Sales Staff also appear, unhidden
   and unlabelled.
7. Confirm the assigned-member counts describe your Vendor: cross-check one
   against the **Users** directory, which lists role names per member.
8. Search by role name; confirm the result narrows locally and instantly.
9. Filter by status; confirm only statuses actually present are offered, and that
   clearing restores the original order.
10. Refresh; confirm the rows do not blank and the figures re-read.
11. Open one `ACTIVE` role.
12. Confirm the definition fields and the mapped permission list, in the same
    order as the web.
13. Open one `INACTIVE` role, if the environment has one.
14. Confirm the inactive notice is shown and legible without relying on colour.
15. Confirm the mapped permissions are still listed and the count is unchanged.
16. Open a role with no permissions (Claim Reviewer or Finance Admin in the
    seeded catalogue); confirm "No permissions assigned".
17. Use browser Back; confirm the catalogue is still loaded and does not re-fetch.
18. Visit `/vendor/roles/not-a-uuid`; confirm "Role not available", no retry, no
    raw error, and — in the network panel — **no RPC call at all**.
19. Log out; confirm the role list, counts and any open role are gone, and that
    signing in again re-reads from scratch.

---

## 14. Known limitations

1. **The role catalogue is global.** `roles`, `permissions` and
   `role_permissions` have no `organization_id`. Every authorized Vendor reads
   identical definitions. Making roles Vendor-scoped is a schema change and a
   product decision, not a mobile read.
2. **Retailer roles appear to Vendors.** A consequence of (1), and the shipped
   web behaviour. They are shown rather than filtered.
3. **There is no role scope or kind column** — no `role_kind`, `is_system`,
   `is_custom` or `is_editable` — so no such badge is displayed. Nothing in the
   product can create a custom role.
4. **Permissions have no status.** An inactive assigned permission is
   unrepresentable, so there is no per-permission badge and no
   `active_permission_count`.
5. **Role status controls permission effectiveness.** An `INACTIVE` role grants
   nothing, however many permissions remain mapped. The list still shows them and
   the notice explains why.
6. **Permission codes are not returned** and are never displayed. They are the
   literals the RLS policies match on.
7. **Permission modules are not returned**, so there is no grouping. When a
   design actually groups permissions, `module` is added deliberately with a
   display mapping — not inferred now.
8. **No pagination.** The RPC is unpaginated by design; the catalogue is six rows
   today and grows only when a migration seeds a role.
9. **Search and status filtering are local**, over the complete trusted answer.
   Nothing typed is sent anywhere, and no server-side filter parameter is
   invented.
10. **No role writes** — create, edit, delete, activate, deactivate, duplicate.
11. **No permission writes** — assign or remove a role→permission mapping.
12. **No role assignment** — assigning a role to, or removing it from, a member.
13. **No member list per role.** Only the count crosses the boundary; not one
    personal field does. The member directory is **Users**, which is where a
    Vendor goes to learn *who* holds a role.
14. **No catalogue-wide permission browser.** The companion answers only "what
    does *this* role grant". The web page's second section — every permission on
    record — has no mobile operation.
15. **Multi-Vendor Super Admins** have `assigned_member_count` computed against
    the **lowest organization id**, deterministically, via the existing
    `get_vendor_super_admin_context()` tie-break that every Vendor RPC and the
    web already follow. The role *rows* are unaffected, since the catalogue is
    global. There is no Vendor switcher in the shipped product.
16. **For an `INACTIVE` role, this count and `list_vendor_users().role_names`
    disagree by design** — the count reports the holders, while the user
    directory hides an inactive *definition* from a member's role names. Both are
    correct for their own question, and the backend's pgTAP suite asserts both
    sides.
17. **Vendor Products, Audit Logs and the Vendor dashboard remain placeholders.**
    The dashboard summary and audit feed have no mobile contract yet.
