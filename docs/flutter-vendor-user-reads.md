# Vendor User list and detail

**Branch:** `feat/flutter-vendor-user-reads`
**Scope:** an authenticated Vendor Super Admin lists the users of their own
Vendor organization and opens one of them.
**Backend repository:** not modified. Nothing was deployed.

The backend contract this implements is
`salesreward-admin/docs/mobile-vendor-user-reads-audit.md` and the migration
`20260801090000_mobile_vendor_user_reads.sql`. Where this document and those
differ, those are right — they describe what is deployed.

> **This milestone is read-only.** There is no invite, edit, activate,
> deactivate or role-assignment path anywhere in it, and the repository
> interface has no method that could become one without changing the interface.

---

## 1. What a Vendor Super Admin can now do

| # | Step | Backend operation |
| --- | --- | --- |
| 1 | See every user of their Vendor organization | `public.list_vendor_users()` |
| 2 | See each display name | — (column of the above) |
| 3 | See profile status and membership status separately | — |
| 4 | See the active roles each user holds | — (a `text[]` in the same row) |
| 5 | Search the loaded users by name | — (local) |
| 6 | Filter by profile status | — (local) |
| 7 | Filter by membership status | — (local) |
| 8 | Refresh the directory | `list_vendor_users()` again |
| 9 | Open one user | `public.get_vendor_user_detail(uuid)` |
| 10 | See membership created, joined and deactivated dates | — (columns of the above) |
| 11 | Retry a failed read | the same call |
| 12 | Return to the directory without reloading it | — |

Nothing else. No inviting, editing, activating, deactivating, role assignment,
permission display, audit history, email, phone number, Retailer users, Retailer
staff or Sales Staff data.

---

## 2. Architecture

```text
presentation/vendor/
  pages/     vendor_users_page.dart             the directory
             vendor_user_detail_page.dart       one user
  cubit/     vendor_user_list_cubit.dart        one list read + local narrowing
             vendor_user_detail_cubit.dart      one detail read
  widgets/   vendor_user_card.dart              one directory row
             vendor_user_badges.dart            the two status pills
             vendor_user_role_chips.dart        the role array, incl. the empty case
             vendor_user_filter_bar.dart        search + two status chip rows
             vendor_user_copy.dart              every user-facing sentence
             vendor_user_formatting.dart        dates and count phrases
        │
        ▼  domain types only — never a Supabase or transport type
domain/
  entities/      VendorUserSummary · VendorUserDetail · VendorUserStatus
  repositories/  VendorUserRepository (interface)
        │
        ▼
data/
  datasources/   vendor_user_rpc_data_source.dart   the two RPCs
  models/        vendor_user_parsers.dart           strict parsing
  repositories/  supabase_vendor_user_repository.dart
```

Wiring: `lib/app/di/injector.dart` registers `VendorUserRepository`;
`lib/app/app.dart` provides it to the tree;
`lib/app/shells/vendor/vendor_shell.dart` constructs both cubits from it.

**Rules the layering enforces**, each covered by a test in
`test/security/vendor_user_boundary_test.dart`:

- The presentation layer never imports `supabase_flutter` or `package:http`, and
  never touches `Supabase.instance`.
- The domain layer imports no SDK, no transport package, and not even
  `package:flutter`.
- No BLoC state holds a raw SDK map — or any `dynamic` at all.
- Only the data layer names an RPC.

### Two shared abstractions were promoted, and why

Both were introduced by this milestone because it is the point at which the
duplication became real, and both left every existing test green.

* **`ReadResult<T>` → `lib/core/result/read_result.dart`.** The receipt feature
  declared a local result type and said explicitly that one feature is not
  enough evidence for a shared abstraction; the Vendor Retailer feature repeated
  the shape and recorded the trigger — *"when a third feature needs one, that is
  the evidence to promote it."* Vendor Users is the third. The promotion is two
  constructors and no helpers: no `map`, no `fold`, no `getOrElse`, each of
  which would be a place for a caller to turn a failure into a value.
  `VendorRetailerResult<T>` is now a `typedef` of it, so the Retailer feature
  moved with **zero call-site changes**. `ReceiptResult<T>` stays separate — it
  sits beside `ReceiptSubmissionOutcome`, which models a *write*, and untangling
  the two belongs to a receipt milestone.
* **`SrResponsiveGrid` → `lib/core/widgets/`.** The three-column-count layout
  the Retailer directory used is the same algorithm the user directory needs at
  *different* widths, so the widget moved to the design system with the
  thresholds as parameters. `VendorRetailerGrid` now delegates to it and keeps
  only its own two numbers; the user directory passes wider ones (820 / 1180)
  because a user card carries two prefixed status pills **and** a wrapping row
  of role chips.

Neither refactor changed any public behaviour, and the full Retailer suite (193
tests) passes unchanged.

---

## 3. Exact backend operations

| Method | RPC | Arguments |
| --- | --- | --- |
| `users()` | `list_vendor_users()` | **none** |
| `userDetail(id)` | `get_vendor_user_detail(p_membership_id)` | the membership id only |

`list_vendor_users()` takes **zero arguments**, and the data source models it as
a nullary Dart function — so an auth user id, profile id, Vendor organization
id, membership id, role code, permission code, tenant id, email or status is not
merely absent, it is *inexpressible* at that boundary. The detail read passes one
key, `p_membership_id`, and a test greps the source to prove no other `p_*`
literal exists in the file.

### 3.1 Returned shapes, parsed strictly

**`list_vendor_users()`** — `membership_id` (uuid), `display_name` (text),
`profile_status` (text), `membership_status` (text), `membership_created_at`
(timestamptz), `joined_at` (timestamptz, **nullable**), `role_names` (`text[]`,
never null, **may be empty**).

**`get_vendor_user_detail(uuid)`** — the same columns **plus** `deactivated_at`
(timestamptz, **nullable**). One row, or **zero**.

Ordering is `display_name, membership_id` for the list and `role name, role id`
inside every role array. Both are total, and neither is re-sorted on the client:
the database collation is not Dart's `compareTo`, and a second sort would be a
second definition of "the directory order".

### 3.2 Status vocabularies

`profile_status` and `membership_status` both draw from `INVITED` / `ACTIVE` /
`SUSPENDED` / `DEACTIVATED` — the same four-value `check` on two tables — so one
`VendorUserStatus` enum serves both. They remain **independent facts**: a person
with an `ACTIVE` profile can hold a `SUSPENDED` membership in this Vendor, and
the screens render two badges and offer two filters for exactly that reason.

### 3.3 There are no Vendor user invitations

Both invitation tables in the schema are asserted Retailer-scoped; **nothing
invites a person into a VENDOR organization**. So a Vendor user who has not
joined is not an invitation row — they are an ordinary membership carrying
`INVITED`, with `joined_at` null.

This feature therefore has no invitation entity, no invitation list or tab, no
invitation id space, no token or hash, and no resend or cancel action. A
disabled "Invite user" button would advertise a backend that does not exist; a
test asserts no such affordance is rendered.

### 3.4 Email is not returned, and is not stood in for

Email lives in `auth.users`, which neither deployed function reads and which the
web Vendor Users page neither queries nor displays. The UI simply omits it —
there is no address, no placeholder, and no "Email unavailable" row, because a
label for an absent field is still a claim about it. A test forbids the strings
`email`, `phone` and `mobile_number` from executable source in this feature.

### 3.5 What is deliberately not sent, and not received

**Not sent:** any auth user id, profile id, Vendor organization id, role,
permission code, tenant id, email, status, search term, limit or offset.

**Not received, and therefore not modelled:** the auth user id; email; mobile
number; password, provider, session or login metadata; role ids or role codes;
permission rows or codes; the Vendor organization id; the profile id; any
membership in another organization; any invitation field; `updated_at`.

---

## 4. The membership id is the selector

The route and both reads address a user by `organization_members.id`, never by a
profile id and never by an auth user id.

A **membership row names one person in one organization**, so scoping it to the
caller's Vendor is a predicate on the same row. A profile id is not: one profile
may hold memberships in several organizations, so it names a person globally and
would have to be narrowed back to a membership before it could be authorized. An
auth user id is worse still — it is the subject Supabase Auth mints tokens for,
and the contract neither returns nor accepts it.

---

## 5. Loading

```
directory  →  list_vendor_users()                    ONE call, on first open
                 · rows keyed by membership_id
                 · roles arrive in the same row from a correlated array_agg
                 · no per-user read, no role query, no permission query

tap a row  →  get_vendor_user_detail(membership_id)  ONE call
                 · zero rows ⇒ "not available", stop
                 · one row   ⇒ render
```

There is no companion read to sequence: roles are part of the row.

**Duplicate calls are structurally impossible, not merely unlikely:**

- Both cubits are owned by the Vendor shell and built lazily, so entering the
  shell fetches neither directory and opening Retailers never fetches Users — a
  test pins this.
- The list cubit loads **once**, on first build of its page. A router refresh, a
  rebuild or a return from a detail screen renders rows already held.
- `VendorUserDetailCubit.open(id)` is idempotent for the id it already shows, and
  is started from `initState`, which runs once per mounted route.
- Both cubits refuse a second read while one is in flight, so repeated refresh
  taps produce one request.
- Every read captures a request token and compares it before emitting, so an
  answer that lands after a newer read — or after a session change — is dropped
  rather than overwriting fresher state.

A background refresh **keeps the loaded rows on screen** and shows that it is
running (button spinner, pull-to-refresh indicator); it never blanks the list.

---

## 6. Routing

| Route | Page |
| --- | --- |
| `/vendor/users` | `VendorUsersPage` |
| `/vendor/users/:membershipId` | `VendorUserDetailPage` |

The detail route is **nested** under the directory route, so a `go` into it
stacks the directory beneath: the back gesture, the browser back button and the
*Back to Users* button all return to a list that is still loaded. Because both
paths share the `/vendor/users` prefix and `indexForLocation` takes the longest
match, **Users stays the selected navigation destination** while a user is open.

Route isolation is unchanged: both paths sit under the `/vendor` prefix, so
`redirectFor` sends a Retailer Owner, Retailer Manager or Sales Staff caller back
to their own landing — and the Vendor shell that owns the cubits is never built
for them, so no read is issued on their behalf.

**The guard is presentation, not security.** Deleting it would let another role
reach a screen whose every RPC returns `42501`.

---

## 7. Parser behaviour

Every field reader throws rather than substituting a default; the repository maps
a throw to `UnavailableFailure`. There is no branch anywhere that produces a
value the backend did not send.

| Input | Result |
| --- | --- |
| Malformed, empty or missing `membership_id` | parse failure → outage |
| Missing, blank or non-string `display_name` | parse failure → outage |
| Missing or blank `profile_status` / `membership_status` | parse failure → outage |
| Malformed or non-string `membership_created_at` | parse failure → outage |
| Malformed `joined_at` when non-null | parse failure → outage |
| Malformed `deactivated_at` when non-null | parse failure → outage |
| **Null** `role_names` | parse failure → outage (never read as "no roles") |
| Missing `role_names`, or not a list | parse failure → outage |
| `role_names` containing a non-string, null or blank entry | parse failure → outage |
| Several rows from the single-row read | parse failure → outage |
| Unrecognised status token | `VendorUserStatus.unknown` — neutral badge, **never active**, and the user is still listed |
| `joined_at` null | `null`, rendered "Not joined yet" |
| `deactivated_at` null | `null`, and the row is not rendered at all |
| `role_names` empty | an empty list, rendered "No active role" |
| **Zero rows** from the detail read | `null` inside a **success** |

Three rules deserve their own line:

1. **An empty role array is never a privilege.** `[]` means the person holds no
   active role, and it is never a default and never `Vendor Super Admin` — the
   one place in this feature where a wrong guess would grant something. Null is
   refused rather than read as empty, because the SQL coalesces to `'{}'` and a
   null array is a response this build was not written against.
2. **An unknown status degrades but never drops the user.** Losing sight of a
   colleague because their status is unfamiliar would be worse than showing it
   plainly, so the row renders with a neutral "Unknown" badge. `isActive` tests
   `active` positively, so nothing arrives at "active" by elimination.
3. **A date is never fabricated, and a status is never read out of one.**
   `joined_at` is not filled in from `membership_created_at`, `deactivated_at` is
   not invented, and neither timestamp is used to infer a lifecycle state — the
   badges carry that.

---

## 8. Error semantics

| Situation | State | Copy | Retry |
| --- | --- | --- | --- |
| Directory loaded | ready | rows | — |
| Only the caller's own row | ready | rows + "You are the only user" | — |
| Empty response (defensive) | ready + empty | "No users to show" | no |
| `42501` | `DeniedFailure` | "Not available to this account" | no |
| Expired session | `UnauthenticatedFailure` | "Your session has ended" | no |
| Timeout / unreachable backend | `UnavailableFailure` | "Could not load this" | **yes** |
| Malformed response | `UnavailableFailure` | same as above | **yes** |
| Refresh failed over loaded rows | rows kept + warning alert | "This list may be out of date" | yes |
| Unknown / foreign / Retailer-owned / malformed membership id | `notFound` | "User not available" | **no** |

Three rules hold throughout, inherited from the shared `SrFailureView`:

1. **No raw backend text.** `mapSupabaseError` discriminates on SQLSTATE and
   returns a discriminant; no Postgres message, SQLSTATE, stack trace, table,
   column, function or policy name reaches a screen.
2. **An outage is never a denial**, and a denial never reads as "not found".
3. **An inaccessible membership is never described as somebody else's.** "User
   not available" is the single wording for an unknown id, another Vendor's id, a
   **Retailer-owned** membership id and a malformed id alike — and it offers no
   retry, because the backend already answered and will answer the same way.
   Wording them differently would confirm that a membership the caller may not
   read nevertheless exists.

A malformed id in the URL never leaves the client: the repository refuses the id
shape and answers `null`, which is the *same* answer the backend gives for an id
that names no row — so a mistyped URL cannot surface as a database outage, and
cannot be told apart from a foreign one.

### The empty state is written against **one** row, not zero

An authorized caller is by definition an ACTIVE member of the Vendor they are
listing, so their own row is always present and a truly empty response is not
reachable while they can see the screen. The real "no colleagues" case is a
one-row directory, and that is what the interface says. The zero-row branch is
kept as a defensive floor and is covered by tests.

---

## 9. Security boundary

The client never decides which Vendor it is, and never learns more about a person
than the contract returns. Asserted by
`test/security/vendor_user_boundary_test.dart`:

- No service-role key, secret key or hardcoded credential.
- No environment read outside `AppConfig`.
- No hardcoded organization or membership identifier — a UUID literal anywhere in
  the feature fails the scan.
- No direct table query: no `.from(`, `.select(`, `.eq(`, `.maybeSingle(`, and no
  quoted `organization_members`, `profiles`, `member_roles`, `roles`,
  `permissions`, `role_permissions` or `organizations`.
- **No `auth.users` access** under any spelling, and no admin API.
- No identity, tenant, role, permission, status, search, limit or offset argument
  on either RPC; the selector name is `membershipId`, never `profileId`,
  `authUserId` or `userId`.
- No permission code, and no reference to `has_organization_permission` or
  `get_vendor_super_admin_context` — the Vendor Super Admin resolver is **not**
  duplicated.
- No email, phone, invitation, token, hash, role id, role code, permission,
  provider or session field.
- No role name is ever compared or branched on — role chips are display only.
- No write RPC and no client mutation (`.insert(`, `.update(`, `.upsert(`,
  `.delete(`).
- No role inferred from an email, JWT claim or user metadata; a `PortalKind` is
  read for its display label and nothing else.
- No fabricated user, role or status literal outside the domain enum, and no
  fallback for an empty role array.

Supabase remains the authority. Both reads are decided again in SQL on every
call, by `SECURITY DEFINER` functions that derive the Vendor from `auth.uid()`,
require **both** `ORGANIZATION_MEMBERS_READ` and `RBAC_READ`, and match each
membership on **both** its own id and that derived Vendor.

### Session isolation

`VendorShell` wraps all four Vendor cubits — two Retailer, two User — in a single
`BlocListener<SessionBloc>` that fires whenever the session stops or starts being
a Vendor session. It clears every one of them in **both** directions, then
reloads the directories for a new Vendor.

This is not a second authentication listener: `SessionBloc` is the application's
existing session lifecycle, and subscribing to Supabase's auth stream again would
create a second opinion about who is signed in.

The widget lifetime is **not** relied on. A user switch emits `SessionInitial`
and the next person's `SessionActive` within one microtask drain, so no frame
renders in between — and a Vendor→Vendor switch keeps the location inside the
same role group, so the guard has no reason to redirect and the element is
certain to survive.

Cleared on a session change: user summaries with their names and roles, the open
user, **and the search term and both status filters** — a search term is usually
a fragment of a colleague's name, so leaving it behind would leave one Vendor's
staff legible to the next person on the device. Derived counts go with the rows
they were counted from.

---

## 10. Responsive UI and accessibility

Built from the existing design system (`SrPageBody`, `SrPageHeader`, `SrCard`,
`SrSectionCard`, `SrBadge`, `SrButton`, `SrTextField`, `SrStatCard`,
`SrCardGrid`, `SrResponsiveGrid`, `SrEmptyState`, `SrFailureView`,
`SrLoadingView`, `SrAlert`).

- **Directory:** one column on a phone, two from 820px, three from 1180px.
  Deliberately **not** a desktop table: cards read identically at every width, so
  there is no wide-only layout to keep in step with a phone fallback.
- **Detail:** label/value pairs stack below 420px and sit side by side above it.
- **Pull-to-refresh** on every platform, plus a header **Refresh** button — the
  button is what a browser, keyboard or screen-reader user can actually operate.
- **Long content wraps.** A long display name takes two lines then ellipsises; a
  long role name wraps inside its own chip; chips wrap onto further lines. A
  five-role user with a 45-character name is covered by a test at 360×640.
- **Light and dark** are both covered, on four surfaces from a 360×640 phone to a
  1280×900 desktop, each asserting no overflow, plus a 1.6× text-scaling case.
- **Colour is never the only signal.** Every status badge states its word and
  carries a distinct glyph; the "no roles" state is worded and italicised, not
  merely absent.
- **Accessibility.** Each user card is one semantics node with `button: true` and
  a spoken summary — name, `Profile status: …`, `Membership status: …`,
  `Roles: …`, and the joined phrase — plus the hint "View details". It names no
  identifier. Status badges spell out their subject, so a screen reader never
  hears a bare "Active" it cannot attribute. Filter chips carry
  `Profile status: Invited` style labels and the `selected` flag. Detail facts are
  spoken as label-and-value pairs. Refresh, retry and back all carry explicit
  button semantics.
- **Openability** is signalled three ways per row: the interactive card
  treatment, a trailing chevron, and an explicit "View details" affordance. The
  whole card is the touch target.

---

## 11. Manual verification (hosted)

Run against the hosted project with an existing Vendor Super Admin account. Use
whatever account your environment already provides; no credential, token,
identifier or personal detail belongs in this document.

```
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

1. **Sign in** as a Vendor Super Admin. Expect the Vendor shell.
2. **Open Users** from the drawer. Expect a skeleton, then the directory.
3. **Confirm real users appear** — at minimum the signed-in administrator, whose
   own row is always present.
4. **Compare with the web** `/users` page for the same account: the same people,
   the same display names, the same statuses and the same role names, in the same
   alphabetical order. (Ordering can differ in exotic cases — SQL uses the
   database collation, the web uses `localeCompare(…, "en")`; they agree on
   ordinary names.)
5. **Verify search** — type part of a name and confirm the count line narrows and
   nothing is re-requested.
6. **Verify profile-status filtering** — the chips offered should be only the
   statuses actually present.
7. **Verify membership-status filtering** — independently of the profile filter.
   Confirm the two compose.
8. **Refresh** with the header button and by pulling down. Rows stay on screen
   while it runs; repeated taps issue one request.
9. **Open one user.** Expect exactly one request.
10. **Verify the fields** — display name, both statuses, roles, membership
    created date, joined date, and a deactivated date only if there is one.
11. **A user with multiple roles**, if one exists: all roles appear as chips on a
    single row, in the backend's order, with no duplicate row for the person.
12. **An invited user**, if one exists: `INVITED` badges and "Not joined yet"
    rather than a fabricated date.
13. **A user with no roles**, if one exists: "No active role" — never a default.
14. **Browser back** from a detail screen: the list is still loaded, with no
    skeleton and no second request, and Users is still the selected destination.
15. **A membership id you do not own:** paste `/vendor/users/<any other uuid>`.
    Expect "User not available", no retry, and no claim about existence.
16. **Log out.** Sign back in: the directory, any open user, and the search box
    are all empty and re-read.

On a phone build (`flutter run -d <device>`) every step is identical; the drawer
and pull-to-refresh are the only differences.

---

## 12. Known limitations

- **No pagination.** `list_vendor_users()` returns the Vendor's whole directory
  in one response. No page counter is invented here; when the backend grows
  cursor parameters, the cubit gains them.
- **No backend search or filtering.** The deployed function has no search or
  filter parameter by design, so **search and both status filters run locally**
  over the complete trusted answer. Nothing typed is sent anywhere, and the
  search field says so.
- **No email address is returned**, so a Vendor cannot tell two people with the
  same display name apart from this screen. Adding one means reading `auth.users`
  from a `SECURITY DEFINER` function and deciding, as a product question, that a
  Vendor Super Admin may see their organization's addresses — a deliberate
  change, with the web updated to match.
- **No phone number.** `mobile_number` is a private profile field the Vendor UI
  has never shown.
- **There is no Vendor user invitation system at all** — not merely no read
  contract. Invited users are represented through `profile_status` and
  `membership_status`; there is no invitation record, token, resend or cancel.
- **No add, invite, edit or deactivate operations**, and **no role assignment**.
  All of them remain web-only, and the interface offers no disabled affordance
  for any of them.
- **No permission display.** Which permissions a role carries is authorization
  internals; neither function reads `permissions` or `role_permissions`.
- **No audit history.** The web detail screen this would mirror does not exist,
  and inventing one would exceed the milestone.
- **Multi-Vendor Super Admins see one Vendor.** The lowest-id qualifying Vendor,
  per the shipped rule that every existing Vendor RPC follows. Changing it is a
  backend product decision, not a mobile one.
- **Ordering collation differs subtly from the web's.** SQL uses the database
  collation; the web uses `localeCompare(…, "en")`. They agree on ordinary names,
  and reconciling them would mean changing the web.
- **Vendor Roles, Products, Audit Logs and dashboard metrics remain
  placeholders.** None has a mobile backend contract yet, and each needs its own
  audit before a screen is built against it.
