# Flutter — Vendor Company & Administrator Profile

**Milestone:** a polished, read-only Vendor company and signed-in administrator
profile screen.
**Branch:** `feat/flutter-vendor-company-profile`
**Flutter base:** `main` @ `b88cf3b`
**Backend base:** `main` @ `2af1d20`
**Hosted Supabase aligned through:**
`20260806090000_mobile_vendor_company_profile_reads.sql`
**Backend audit:** `docs/mobile-vendor-company-profile-reads-audit.md` (in the
backend repository)

This milestone is **Flutter-only**. No backend file was created, edited or
deployed.

---

## 1. What this screen is

One route, `/vendor/settings`, showing two things and nothing else:

| Section | Value shown | Source |
| --- | --- | --- |
| **Company** | the Vendor organization **name** | `Session` / `PortalContext` |
| **Administrator** | the signed-in administrator's **display name** and their **active role names** | `public.get_my_vendor_profile()` |

That is the entire product surface. It is not a partial view of a richer screen —
it is the whole of what SalesReward stores and displays about a Vendor company and
about a Vendor administrator's own account. § 10 records why.

---

## 2. Architecture

A feature slice at `lib/features/profile/`, following the same clean-architecture
and Cubit conventions as Dashboard, Retailers, Users, Roles, Products and Audit
Logs.

```
lib/features/profile/
├── domain/
│   ├── entities/vendor_administrator_profile.dart      the two-field entity
│   └── repositories/vendor_profile_repository.dart     one read, no parameters
├── data/
│   ├── datasources/vendor_profile_rpc_data_source.dart zero-argument invoker
│   ├── models/vendor_profile_parser.dart               strict, all-or-nothing
│   └── repositories/supabase_vendor_profile_repository.dart  call→parse→classify
└── presentation/vendor/
    ├── cubit/vendor_profile_cubit.dart                 load / refresh / clear
    ├── cubit/vendor_profile_state.dart                 phase + profile + failure
    ├── pages/vendor_company_profile_page.dart          composes the two sources
    └── widgets/
        ├── vendor_profile_copy.dart                    every user-facing string
        ├── vendor_profile_company_card.dart            + the shared note widget
        ├── vendor_profile_administrator_card.dart
        ├── vendor_profile_role_chips.dart
        └── vendor_profile_initials.dart                initials + avatar disc
```

**Layering rules, all asserted by `test/security/vendor_profile_boundary_test.dart`:**

* Presentation never imports `package:supabase_flutter`, never touches
  `Supabase.instance.client`, and never performs its own HTTP.
* The domain layer imports no SDK, no transport package and no Flutter widget
  library.
* No cubit state and no widget holds a raw `Map` or a `dynamic`.
* The RPC name appears in the data layer and nowhere else.
* Registration is in `lib/app/di/injector.dart`; the app root
  (`lib/app/app.dart`) provides the interface to the tree so a widget test can
  drive the whole flow over a fake.

---

## 3. The exact RPC

```dart
const String vendorAdministratorProfileRpc = 'get_my_vendor_profile';

typedef VendorAdministratorProfileInvoker = Future<Object?> Function();

VendorAdministratorProfileInvoker supabaseVendorAdministratorProfileInvoker(
  SupabaseClient client,
) {
  return () => client.rpc<Object?>(vendorAdministratorProfileRpc);
}
```

**Zero arguments, and no `params` map at all** — not even an empty one. An empty
map would be harmless today and would be the obvious place for a future "just
one" selector to land. The typedef enforces the shape at compile time.

### 3.1 Output contract

| # | Field | Type | Nullable | Meaning |
| --- | --- | --- | --- | --- |
| 1 | `administrator_display_name` | `text` | **NOT NULL** | the caller's own name, already composed by the database |
| 2 | `administrator_role_names` | `text[]` | **NOT NULL** | the ACTIVE role **display names** on the caller's own Vendor membership |

Field **order** is part of the pinned contract. An authorized caller receives
**exactly one row**.

### 3.2 What is deliberately never sent

No auth user id, profile id, membership id, organization id, tenant id, role
selector, permission selector, profile selector, organization selector, another
user's id, status or date range. Two questions are answered server-side and
neither is answerable from the client:

* **Whose profile** — `m.user_id = auth.uid()`, compared against the verified
  request claims rather than against a parameter.
* **Which Vendor** — derived through `get_vendor_super_admin_context()` with the
  shipped lowest-organization-id tie-break.

---

## 4. Composition — two trusted sources, never one asking the other

### 4.1 Company identity

```dart
final SessionState session = context.watch<SessionBloc>().state;
final String? organizationName = session is SessionActive
    ? session.portalContext.vendor?.organizationName
    : null;
```

Read through `vendor` directly rather than through a portal-kind switch: the
block is null unless the backend resolved a Vendor for this caller, so there is
no branch that could caption this page with a Retailer's name.

**Never done:** `organizations` is not queried directly; no organization id or
name is sent to the RPC; no second organization-name source is created; the name
is not copied into the RPC model; no organization status or business detail is
inferred. The boundary test asserts that `portalContext` appears in the page and
in no other file of the slice, and that the entity, parser and cubit model no
organization identity at all.

### 4.2 Administrator identity

`get_my_vendor_profile()` and nothing else.

**Never done:** `profiles`, `organization_members`, `member_roles` and `roles`
are not queried directly; `list_vendor_users()` is not downloaded to find the
caller in it; the display name is not reconstructed from first and last names in
Dart; no role code or permission is inferred.

The directory anti-pattern is worth naming because it is the reason this contract
exists: `list_vendor_users()` returns every colleague's name, statuses and roles
but carries **no marker for which row is the caller**, so self-identification
would mean matching a locally composed name — which breaks for two colleagues who
share one, and puts every colleague's private status on the wire to render one
fact about oneself.

### 4.3 Why they cannot disagree

Both contracts derive their Vendor from `auth.uid()` through
`get_vendor_super_admin_context()` with the same `order by organization_id limit
1`. The organization named on this screen and the roles listed on it are
therefore about the **same** organization by construction, without either being
sent to the other.

---

## 5. Parser behaviour

`VendorProfileParser.parse` accepts only a **list containing exactly one object**.

| Response shape | Outcome |
| --- | --- |
| one row, non-blank name, list of non-blank strings | `VendorAdministratorProfile` |
| not a list | `VendorProfileFormatException` |
| zero rows | rejected — a denial is an exception in SQL, never an empty body, so an empty body must never become a blank profile |
| more than one row | rejected — and no row is taken |
| row is not an object | rejected |
| display name missing / null / non-string / empty / whitespace-only | rejected |
| role array missing / null / non-list | rejected — the SQL coalesces to `'{}'`, so a null array is a response this build was not written against, not "no roles" |
| any non-string, empty or whitespace-only role entry | rejected — and it fails the **whole** profile, not just that entry |
| `[]` role array | **accepted**, preserved as empty (§ 7) |

Both fields are read before anything is constructed, so there is no partial
identity to emit. The repository turns every format exception into
`UnavailableFailure` — never a denial, and never a fabricated profile.

### 5.1 Display name

Rendered **exactly as returned**. Never split, never trimmed and recombined,
never re-cased, never replaced by the organization name, and no initials are
derived from any other source. The blank check runs against a trimmed *copy*; the
original string is what is handed on and what is displayed.

### 5.2 Role array

Order is **preserved verbatim** (`order by r.name, r.id` in SQL). Nothing sorts,
filters or de-duplicates it, and it is deliberately not converted to a `Set` —
that would change the order.

**Duplicates are preserved rather than rejected.** The milestone brief allows
rejecting duplicate role names *"when the backend contract or tests establish
uniqueness"*. They do not: `public.roles` carries `roles_code_unique` on `code`
but **no unique constraint on `name`** (`20260716125559_vendor_admin_rbac.sql`).
Two distinct ACTIVE definitions sharing a display name is therefore a legal
database state, and refusing it would refuse a real answer. This matches the
Users parser, which records the same reasoning: *"a `Set` would hide a genuine
backend duplication bug rather than prevent one."* What pgTAP § J does prove is
narrower — a duplicate `(membership, role)` **assignment** is refused by
`member_roles_pkey` — which is about assignments, not about names.

---

## 6. The display-name fallback, and why it is unreachable

The SQL expression is
`coalesce(nullif(btrim(btrim(first_name) || ' ' || btrim(last_name)), ''), 'Member')`.

`public.profiles.first_name` and `.last_name` are both `NOT NULL` and both carry
a `length(trim(...)) > 0` CHECK (`profiles_first_name_not_empty`,
`profiles_last_name_not_empty`, `20260716124419`). The backend verification proves
every shape that would reach the `'Member'` floor is **rejected by the schema on
both INSERT and UPDATE** — `23502` for a null part, `23514` for an empty or
whitespace-only one. For any storable profile the result is exactly
`trim(first) + one space + trim(last)`.

**Flutter's posture:** accept any non-empty returned string, and do **not**
special-case `'Member'`. Treating it as a status would render something the
contract does not express, and would also refuse a perfectly ordinary single-word
name. The boundary test asserts no source compares against the literal.

Non-ordinary caller states never reach the fallback either — a suspended profile,
another Vendor's administrator and a caller whose `auth.users` row was deleted all
receive `42501` before any row is composed.

---

## 7. The empty role array

For an authorized caller the array **always** contains at least
`Vendor Super Admin`: that ACTIVE assignment is what authorized them, and pgTAP
§ J proves that removing it produces `42501` rather than a row with `{}`.

The client nevertheless renders `[]` safely as the neutral **"No active role"** —
the same wording the web directory uses, so the two clients agree. It is a
defensive branch, never a default, and it is deliberately **not** used in the
normal fixtures (`aminaAdministratorProfile` carries one role;
`noRoleAdministratorProfile` exists only to exercise the branch).

---

## 8. Authorization

The backend requires **active Vendor Super Admin authority** *and* **`RBAC_READ`**
— the latter because the returned role **names** come from `public.roles`, whose
policy `roles_select_rbac_authorized` requires exactly that of a browser client.
`ORGANIZATION_MEMBERS_READ` is deliberately *not* required: a caller's own rows
are admitted by ownership.

**Flutter inspects, sends and displays none of this.** Every refusal maps to one
generic `DeniedFailure` carrying no fields at all, rendered by the shared
`SrFailureView` as *"Not available to this account"* with **no retry**. The
screen never reveals which permission was missing, a role code, a SQLSTATE,
PostgreSQL text, the RPC name or a table name — asserted by the flow test, which
searches the rendered tree for each of them.

Route guards continue to deny **Retailer Owner**, **Retailer Manager** and
**Sales Staff**, and Supabase remains the final authority even after the guard
passes: `redirectFor` is presentation, and the SQL function re-decides on every
call.

---

## 9. Route and navigation

| | |
| --- | --- |
| Route | `/vendor/settings` (`VendorNavigation.settings`) |
| Page | `VendorCompanyProfilePage` |
| Nesting | none — neither half of the screen is addressable |
| Destination | the existing **Settings** entry, now routable |

The web has **no** `/settings`, `/company`, `/organization`, `/profile` or
`/account` route, and its Settings nav item is a `disabled: true` placeholder.
The Flutter route is therefore named after the navigation entry it enables rather
than after a web route it mirrors.

**What changed in `VendorNavigation`:** the Settings entry moved from
`RoleDestination.soon(...)` to a routable `RoleDestination` with
`path: settings`. It keeps its label and its **position** — last, exactly where
the web's nav list puts it — so the drawer order is unchanged. The Vendor model
is now **seven routable destinations plus five "Soon" placeholders**.

`indexForLocation` keeps Settings selected while the route is open, the Vendor
shell stays visible around the page, and browser back/forward is unaffected
(`go_router` handles both as for every other Vendor route).

**Unchanged:** Dashboard, Retailers, Users, Roles, Products and Audit Logs.
Campaigns, Claims, Coins, Payouts and Reports remain unavailable. No other
portal role gained a Settings destination. No company/profile quick link was
added to the Dashboard or anywhere else.

---

## 10. Company-profile scope

The company section shows **the organization name and nothing else**, and says so
once:

> *Additional company details are not configured in SalesReward yet.*

Neutral and product-focused. It does **not** read as a failure, because nothing
failed — the boundary test asserts the note contains no failure vocabulary, and
the flow test asserts no failure wording appears inside the company card.

`public.organizations` has exactly eight columns (`id`, `name`,
`organization_type`, `status`, `country_code`, `default_currency`, `created_at`,
`updated_at`). There is **no** legal name, trading name, registration identifier,
tax identifier, website, business email, business phone or postal address column
anywhere in the schema. So there is nothing to withhold and nothing to load —
and therefore **no disabled text field, no placeholder dash and no "coming soon"
row** stands in for one. A greyed-out field would imply a value exists and is
merely not editable here, which would be untrue.

`status`, `country_code`, `default_currency` and the timestamps do exist, and are
**never displayed for the caller's own Vendor by any web surface** — so they are
not displayed here either.

---

## 11. Personal-profile scope

Shown: the **display name** and the **active role display names**.

Not shown, and not modelled anywhere in the slice: email, mobile number, profile
status, membership status, organization status, `created_at`, `updated_at`, any
id, permission codes, role codes, metadata, avatar image, authentication details.

**No status badge, and none inferred.** A caller who receives a row *is* an
active administrator of an active Vendor — those are conditions of the read, not
output — so a returned status column could only ever hold `'ACTIVE'`. The
contract returns none, and nothing here builds a badge from their absence.

**Initials** are derived locally from `administrator_display_name` (and from the
organization name for the company disc) for a decorative avatar, exactly as both
shipped clients already do. No image URL is queried or stored: no logo, avatar or
image column exists in the schema, and the only Storage bucket in the project is
`receipts` — private, zero policies, unrelated to identity. The initials are
wrapped in `ExcludeSemantics`, so a screen reader hears the full name rather than
two letters.

---

## 12. Refresh behaviour

Two affordances, one method: a header **Refresh** button and pull-to-refresh.

1. Calls `get_my_vendor_profile()` again.
2. **Replaces the complete profile atomically** — `copyWith` has no per-field
   setter, so a state that showed one administrator's name beside another's roles
   is unrepresentable.
3. **Preserves the previous profile while refreshing** — the card does not blank
   and refill; `isRefreshing` drives the button spinner instead.
4. **Preserves stale profile data when a refresh fails** — the cards stay exactly
   as they were.
5. Shows a **safe, non-blocking** `SrAlert` above them: *"This profile may be out
   of date."*
6. **Avoids duplicate simultaneous requests** — a second call while one is in
   flight is a no-op, not a queued duplicate.
7. **Retry** is the same Refresh button; a failed *first* read offers
   `SrFailureView`'s own retry.
8. **Ignores stale responses after a session change** — every request carries a
   token, advanced by each request and by `clear()`.

The organization name is **not** refreshed from here. It is read from the session
on every build, so it updates when the effective session identity changes, and
this feature never resolves `PortalContext` itself.

---

## 13. Session isolation

`VendorProfileCubit` joins the ten cubits already owned and cleared by
`VendorShell`'s `_SessionIsolation` listener. That listener compares an
**identity** — `(authUserId, organizationId)` — rather than a boolean, so a direct
`Vendor A → Vendor B` transition with no intermediate state is detectable on its
own terms. It listens to the existing `SessionBloc`; **no second Supabase auth
listener is added** anywhere.

On logout, a direct Vendor A → Vendor B switch, a trusted organization change, a
move to another portal role, a session denial, unavailability or invalidation,
`clear()` drops:

* the administrator profile (name **and** role names, as one value),
* the loading state, the refresh state and the failure,
* and — by advancing the request token — invalidates any in-flight **initial** or
  **refresh** request, so a stale Vendor A response can never populate Vendor B's
  screen.

An **identical** re-emitted session (the shape a same-user token refresh takes)
compares equal, so it costs no clear and no duplicate load.

The **company** half needs no clearing: it is read from the session on every
build, so it changes with the session by construction.

---

## 14. Loading, denied and error states

| Condition | Screen |
| --- | --- |
| first read in flight | `SrLoadingView` skeleton for the whole screen |
| authorized | header + company card + administrator card |
| first read denied (`42501`) | company card, and `SrFailureView` — *"Not available to this account"*, **no retry**, no backend detail |
| first read failed (transport / malformed) | company card, and `SrFailureView` — *"Could not load this"*, **with retry** |
| refresh failed | both cards preserved, plus the non-blocking stale notice |
| malformed response | outage state — never a partially rendered field |

The company card renders whenever the session carries a Vendor name, including
beside a failed administrator read: it comes from a different contract with a
different authorization argument, and it is genuinely available. No fabricated
profile data is ever displayed, and the RPC's fallback literal is never displayed
as though it were real data.

---

## 15. Responsive design and accessibility

**Responsive.** `SrPageBody` applies the standard gutter and the `max-w-6xl`
content cap. `SrCardGrid` stacks the two cards on a phone and pairs them once
there is room for two columns (≥ 520 px), keeping company and administrator
visually distinct without a bespoke layout. Role chips `Wrap`, and a long role
name wraps *inside* its chip rather than overflowing. Refresh sits in the page
header and stays reachable at every width. Verified with no horizontal overflow on
a small phone (360×640), a phone (390×844), a tablet (900×1000) and a desktop
browser (1280×900), in light and dark themes, and at a 1.8× text scale.

**Accessibility.**

| Element | Semantics |
| --- | --- |
| page heading | `Semantics(header: true)` around the page header |
| Vendor organization name + company scope | one sentence: *"Vendor organization: &lt;name&gt;. Taken from your authenticated Vendor session."* |
| company limitation note | announced as its own sentence |
| administrator display name | *"Signed-in administrator: &lt;name&gt;."* |
| role list | one sentence — *"Active roles: A, B, C."* — so a reader is not made to walk N chips to learn one fact |
| each role chip | independently labelled *"Role: &lt;name&gt;"* via `explicitChildNodes` |
| empty role list | announced as *"Active roles: No active role."*, never silent |
| Refresh | labelled button, disabled while a read is in flight |
| retry | `SrFailureView`'s labelled action |
| stale notice | `SrAlert`, a live region |
| unavailable state | `SrFailureView`'s fixed per-discriminant copy |
| avatar initials | `ExcludeSemantics` — decorative |

Nothing relies on colour alone: every distinction is carried by text. Focus order
follows the visual order (header → Refresh → company → administrator → chips).

---

## 16. Tests

| Suite | File | Tests |
| --- | --- | --- |
| Parser / domain | `test/features/profile/vendor_profile_parser_test.dart` | 30 |
| Data source / repository | `test/features/profile/vendor_profile_repository_test.dart` | 22 |
| Cubit | `test/features/profile/vendor_profile_cubit_test.dart` | 28 |
| Widget / routing / accessibility / responsive | `test/features/profile/vendor_company_profile_flow_test.dart` | 63 |
| Security boundary | `test/security/vendor_profile_boundary_test.dart` | 47 |
| Session isolation (extended) | `test/features/users/vendor_session_isolation_test.dart` | +15 (68 → 83) |
| Support fake + fixtures | `test/support/vendor_profile_fakes.dart` | — |

**Updated for the navigation change:**
`test/app/navigation/role_navigation_test.dart` (seven routable plus five
"Soon"), `test/app/shells/role_shells_test.dart` (five SOON pills, Settings
present), `test/app/auth_flow_test.dart` and `test/support/pump_app.dart` (the new
repository is supplied to every pumped app).

---

## 17. Security boundary

Asserted by `test/security/vendor_profile_boundary_test.dart`:

* no service-role key, secret key or hardcoded credential; no
  `String.fromEnvironment` or `Platform.environment` read of its own
* `dart_defines.json` is git-ignored and untracked
* no direct read of `organizations`, `profiles`, `organization_members`,
  `member_roles`, `roles`, `permissions` or `role_permissions`; no `.from(`,
  `.select(`, `.eq(`, `.count(`, `.head(` anywhere in the slice
* no `auth.users` read, no admin API
* no `list_vendor_users()` / `get_vendor_user_detail()` call, and no import of the
  Users feature at all
* no caller-identity argument, no organization argument, no profile/member
  selector, no role/permission argument, no `p_` key anywhere
* no writes: no `.insert(`, `.update(`, `.upsert(`, `.delete(`, `.upload(`; the
  repository interface exposes exactly one method; the cubit exposes exactly
  `load`, `refresh`, `clear`
* no email or mobile number, no statuses, no timestamps, no ids (and no hardcoded
  UUID literal), no metadata, no token or session claim
* no image, avatar path, storage path or signed URL
* no fabricated legal/company field, and no placeholder value standing in for one
* the organization name comes only from `PortalContext`, read in the page alone
* the administrator name and roles come only from `get_my_vendor_profile()`; no
  name is composed, trimmed or re-cased, and the role order is never sorted,
  filtered or de-duplicated
* no role or permission **code** is named or derived; the `'Member'` floor is not
  special-cased
* no second auth or session listener
* no cross-role route access; no other portal role gained a Settings destination
* no company/profile quick link was added to the Dashboard

---

## 18. Manual hosted verification

To be performed by a human against the hosted environment. **Not performed as
part of this milestone.**

1. Start Flutter web:
   `flutter run -d chrome --dart-define-from-file=dart_defines.json`
2. Sign in as a **Vendor Super Admin**.
3. Open **Settings** in the Vendor drawer (or navigate to `/vendor/settings`).
4. Confirm the **Vendor organization name** matches the one shown on the
   Dashboard caption and in the shell header.
5. Confirm the **administrator display name** matches the signed-in account.
6. Confirm the **active role names** shown are the roles that account holds.
7. Open **Users**, find the caller's own row, and compare the role names **and
   their order** with the chips on this screen — they are produced by the same
   SQL ordering and must agree.
8. Press **Refresh**; confirm the profile reloads without the cards blanking, and
   that pull-to-refresh does the same on a narrow window.
9. Navigate to another Vendor section and return; confirm the screen renders what
   is already held rather than re-reading.
10. **Log out** and confirm the profile data clears — sign back in and confirm it
    is re-read under the new session.
11. Confirm **no email, mobile number, ID, status badge or timestamp** appears
    anywhere on the screen.
12. Confirm **Settings remains unavailable** to Retailer Owner, Retailer Manager
    and Sales Staff — the drawer entry does not exist for them, and typing
    `/vendor/settings` lands on their own home.

Do **not** modify production role assignments merely to observe multiple roles.
Do **not** put credentials, tokens, UUIDs or private screenshots in any
verification note.

---

## 19. Known limitations

1. **The company profile contains only the organization name.** That is the whole
   of what the product stores and displays about a Vendor company.
2. **No legal or business fields exist** — no legal name, trading name,
   registration identifier or tax identifier column exists anywhere in the schema.
3. **No company email, phone, address or website** — likewise, no column exists.
4. **No logo or avatar storage exists.** Both clients render initials; the only
   Storage bucket in the project is `receipts`, private with zero policies and
   unrelated to identity.
5. **No profile email or mobile number is exposed.** `profiles.mobile_number`
   exists and has never been displayed by any client; email lives in `auth.users`,
   which this read never touches.
6. **No edit capability.** There is no company or profile write path anywhere in
   this product — web or mobile — so no affordance is offered, not even a disabled
   one.
7. **No password or security settings**, and no session/MFA management.
8. **No organization switching.** There is no switcher anywhere in the product.
9. **Multi-Vendor callers retain the lowest-organization-id tie-break.** A Super
   Admin of two Vendors sees the lowest-id Vendor's roles, deterministically, and
   `PortalContext` names the same Vendor. This is the shipped behaviour of every
   Vendor RPC and of the web itself; it is reproduced rather than changed, because
   changing it would change which organization an existing operator sees as a side
   effect of a mobile read.
10. **The empty-role branch is defensive and unreachable for an authorized
    caller** (§ 7). It is kept so an unexpected answer renders safely rather than
    crashing.
11. **Duplicate role names are preserved rather than rejected**, because
    `public.roles` constrains `code` to be unique but not `name` (§ 5.2).
12. **All profile and company writes remain separate future work**, as do company
    editing, profile editing, logo/avatar upload, password settings, Vendor user
    writes, product writes and invitation writes.
