# Retailer shell and Retailer Owner Overview

The first Retailer milestone in the Flutter application. It makes the Retailer
portal reachable, backend-authoritative, and useful for one role: a Retailer
Owner sees their organization and its shop counts, read from the deployed
contract and nothing else.

---

## 1. Scope

### What this milestone adds

| | |
| --- | --- |
| **Retailer Owner Overview** | The real screen, backed by `get_retailer_owner_portal_context()` |
| **Overview feature stack** | Entity, repository interface, RPC data source, parser, Supabase repository, cubit, widgets |
| **Shell wiring** | The Retailer Owner shell now owns and clears the Overview cubit |
| **Session isolation** | An identity listener on the Retailer Owner shell |
| **Failure mapping** | A Retailer-specific problem taxonomy, so operational failures stop collapsing into "check your connection" |

### What already existed and was **not** rebuilt

The Retailer shell, its navigation model, capability-aware destination
filtering, and backend-authoritative routing all shipped in earlier milestones
and are reused unchanged:

- `lib/features/auth/domain/entities/portal_context.dart`
- `lib/features/auth/domain/entities/portal_kind.dart`
- `lib/features/auth/domain/entities/retailer_capabilities.dart`
- `lib/features/auth/data/models/portal_context_parser.dart`
- `lib/app/shells/retailer_owner/retailer_owner_navigation.dart`
- `lib/app/router/app_router.dart`

No second portal-context implementation was introduced. The existing parser's
capability keys were verified against the deployed migration and match exactly.

### What this milestone explicitly does **not** implement

- Shop details, the shop list, or any shop write
- Staff management, the staff roster, or staff writes
- Invitation sending, re-sending, or revocation
- Assigned Product screens
- The Retailer Manager workspace
- Retailer audit logs
- Receipt review

Every one of these already works on the SalesReward **web** portal. The app's
copy says "not built into the app yet" and never "unavailable" — labelling a
feature a customer uses today as non-existent would be both false and alarming.

---

## 2. Portal routing contract

### The RPC

```
public.get_my_portal_context()
```

**Zero arguments.** Returns `jsonb`. Identity comes from `auth.uid()`.

Relevant fields: `context_version`, `portal_kind`, `vendor.*`, `retailer.*`.

`portal_kind` is one of `VENDOR_SUPER_ADMIN`, `RETAILER_OWNER`,
`RETAILER_MANAGER`, `SALES_STAFF`, `NONE`.

### Routing table

| `portal_kind` | Landing | Behaviour |
| --- | --- | --- |
| `VENDOR_SUPER_ADMIN` | `/vendor/dashboard` | Unchanged. The Retailer read is never issued. |
| `RETAILER_OWNER` | `/retailer-owner/overview` | The new Overview. |
| `RETAILER_MANAGER` | `/retailer-manager/staff` | **Never** the Owner Overview. |
| `SALES_STAFF` | `/sales-staff/submit` | Unchanged receipt workflow. |
| `NONE` | `/access-denied` | The existing safe state. No loop. |

Each role owns a **disjoint route prefix**, so "can this role reach that screen?"
is answerable from the route tree alone. A Manager, a Sales Staff member or a
denied caller who types `/retailer-owner/overview` is redirected to their own
landing, and the Owner read is never issued on their behalf.

The guard is presentation, not security. Every read behind it is decided again
in SQL.

### Why the Manager is routed away rather than shown an empty Overview

`get_retailer_owner_portal_context()` resolves through
`resolve_retailer_owner_organization`, which hard-filters `r.code =
'RETAILER_OWNER'`. A Manager therefore receives **zero rows** — not a partial
overview. Sending them to the Overview would land them on a permanent
"no workspace" state.

The Manager's existing route already handles this correctly: it lands on Staff,
carries no Overview destination, and its navigation declares no
`viewRetailerOverview` capability. Nothing was changed there, and no Owner
figure is reachable from it.

---

## 3. The Overview RPC

```
public.get_retailer_owner_portal_context()
```

**Zero arguments.** Returns **at most one row**.

### Exact returned fields

| Column | Type | Null? | Rendered as |
| --- | --- | --- | --- |
| `retailer_name` | `text` | no | The organization name |
| `retailer_status` | `text` | no | A status badge |
| `country_code` | `text` | **yes** | ISO alpha-2, or "Not recorded" |
| `default_currency` | `text` | **yes** | ISO 4217, or "Not recorded" |
| `membership_status` | `text` | no | A status badge |
| `total_shop_count` | `bigint` | no | "Total shops" |
| `active_shop_count` | `bigint` | no | "Active shops" |

**Not returned, deliberately:** any UUID (organization, membership, profile,
role, permission, shop, relationship, invitation), the auth user id, any email
address, personal names, mobile numbers, role codes, permission codes,
invitation state, audit metadata, timestamps, and service configuration.

There is nowhere in `RetailerOwnerOverview` to put an identifier, which is what
keeps a raw UUID off the screen by construction rather than by a rendering rule.

### Status vocabularies

Two **separate** closed sets, modelled as two enums because only one of them has
an `INVITED` state:

- `organizations.status` → `ACTIVE` | `SUSPENDED` | `DEACTIVATED`
- `organization_members.status` → `INVITED` | `ACTIVE` | `SUSPENDED` | `DEACTIVATED`

An **unrecognised** token degrades to `unknown` and renders as a neutral
"Unknown" badge — additive forward compatibility, and never `active`. A
**missing, blank or non-string** status is a different thing: a required value
the response did not supply, and it rejects the whole row.

### The counts are computed in SQL, and must be

`retailer_shops` carries exactly one **vendor-scoped** SELECT policy, which
returns **zero rows to a Retailer Owner** by design. A client that counted shops
itself would render `0` for every Owner and look entirely plausible doing it.
Both counts are therefore scalar subqueries keyed on the *resolved* organization
id, which is also why the client never needs a shop id in order to count shops.

The parser rejects `active_shop_count > total_shop_count`: the active set is a
subset of the total by construction, so the pair cannot both be true and cannot
be repaired by picking one.

---

## 4. Zero-row behaviour

Zero rows is a **successful answer**, not an error. It is the single answer the
backend gives to every ineligible caller — signed out, suspended profile,
`INVITED` or inactive membership, suspended or deactivated organization, missing
`RETAILER_OWNER` role, inactive role, missing `RETAILER_PORTAL_READ`, a Vendor
Super Admin without a Retailer Owner membership, and the ambiguous
multi-Retailer case — so that the function cannot be used as an oracle to learn
*why* access failed or whether an account exists.

The app preserves that exactly:

- it renders a distinct "No Retailer overview for this account" state;
- it offers **no retry**, because a second identical call returns the same
  nothing;
- it renders **no cards** and no zeros;
- it **clears** any previously held overview, which is what stops Owner A's
  organization from staying on screen when Owner B turns out to be ineligible.

There is no `RetailerOverviewProblem` member for "inactive membership" or
"suspended Retailer", because the backend does not distinguish them. Inventing
one in Dart would fabricate a distinction the database deliberately refused to
make.

---

## 5. Capability hint behaviour

`retailer.capabilities` carries seven backend-derived booleans. The deployed key
names, verified against the migration:

```
view_retailer_overview   view_shops   view_staff   manage_staff
assign_staff_shops       view_assigned_products    submit_receipts
```

**These are presentation hints and nothing else.** They may only ever *hide or
disable a navigation destination*. Specifically:

- a false hint hides its bottom-bar destination and omits its "Coming to the
  app" entry;
- a false hint **never** suppresses a screen's own read — the Overview calls its
  RPC regardless of `view_retailer_overview`, and there is a test asserting so;
- an entirely empty or unreadable capability block falls back to showing the
  role's full navigation, so a bad hint cannot cost a role its whole shell;
- a **non-boolean** value (`'true'`, `1`, `[]`) reads as `false`, never as
  truthy.

The backend re-decides every operation in SQL on every call. Hiding a link
removes an accident, never a capability.

---

## 6. Session isolation

`RetailerOwnerShell` wraps its subtree in a `BlocListener` on `SessionBloc`
keyed on an **identity**, not a boolean:

```dart
typedef _RetailerOwnerIdentity = ({String? authUserId, String organizationId});
```

A boolean ("is this still a Retailer Owner session?") cannot tell one Owner from
another: a direct `Owner A → Owner B` transition is `true → true`, so the
listener would never run. The identity comparison makes that transition
detectable on its own terms, and assumes **no intermediate state** — it does not
rely on `SessionBloc` happening to emit `SessionInitial` in between.

On any identity change the cubit is cleared **first**, before anything is
requested for the new identity, and `clear()` advances a request token so an
answer already in flight is dropped on arrival rather than repopulating state
that was just emptied.

What is cleared: the organization name, both statuses, both shop counts, the
loading state, the refresh state, and any problem.

The organization id is compared **locally only**. It is never sent anywhere —
the reload RPC takes no arguments, so it cannot carry the previous organization
forward even by accident.

Vendor and Retailer state cannot mix: the two shells share chrome and nothing
else. No Vendor cubit is provided anywhere inside the Retailer subtree, and no
Retailer cubit inside the Vendor subtree. Both facts are asserted statically.

Deterministic tests cover `Vendor → Retailer Owner`, `Retailer Owner A →
Retailer Owner B`, `Retailer Owner → Sales Staff`, `authenticated → signed out`,
a stale answer landing after a role switch, and an identical re-emitted session
(which reloads nothing).

---

## 7. Failure mapping

`RetailerOverviewProblem` exists because the shared `Failure` union collapses
every transport, serialization and unrecognised fault into `UnavailableFailure`,
whose copy is *"Check your connection and try again."* On the first screen after
sign-in that would report a packaging fault, an unreadable response and a real
outage with the same sentence.

| Outcome | Source | User-facing copy | Retry? |
| --- | --- | --- | --- |
| **Loaded** | one row | the overview | — |
| **Ineligible** | zero rows | "No Retailer overview for this account" | no |
| `denied` | `42501` | "Not available to this account" | no |
| `signedOut` | `AuthException` | "Your session has ended" | no |
| `malformed` | parser rejection | "Could not read your overview" | yes |
| `network` | `http.ClientException` | "Could not reach SalesReward" | yes |
| `timeout` | 20 s elapsed | "This took too long" | yes |
| `unexpected` | anything else | "Something went wrong" | yes |

Only `network` and `timeout` mention the connection.

**Discrimination is by exception type and SQLSTATE only.** Nothing reads
`error.message`, for display or for branching. Postgres messages name tables,
columns, functions and policies; GoTrue messages are prose that changes between
releases. No SQLSTATE, PostgREST body, stack trace, token or backend string
reaches a screen, and a test asserts that for every problem value.

`http.ClientException` is the single check that covers both platforms:
`postgrest` propagates the transport exception unchanged, and `package:http`
wraps a VM `SocketException` in a subclass of `ClientException` — so a refused
socket, an unresolved host and a browser CORS refusal all classify as `network`
without importing `dart:io`, which does not exist on Flutter web.

### Stale vs. failed

A failed **first** read is the whole screen. A failed **refresh** keeps the
figures and puts a non-blocking notice above them: they are still the last thing
the backend actually said, and discarding them would replace real figures with
nothing while zeroing them would replace them with a lie.

---

## 8. Architecture

```
lib/features/dashboard/
├── domain/
│   ├── entities/retailer_owner_overview.dart          entity + two status enums
│   └── repositories/retailer_owner_overview_repository.dart
│                                                      interface + result + problem enum
├── data/
│   ├── datasources/retailer_owner_overview_rpc_data_source.dart
│   ├── models/retailer_owner_overview_parser.dart     strict parser
│   └── repositories/supabase_retailer_owner_overview_repository.dart
└── presentation/retailer_owner/
    ├── cubit/retailer_owner_overview_cubit.dart       + immutable state
    ├── pages/retailer_owner_overview_page.dart
    └── widgets/                                       copy, detail grid, count card
```

Rules held:

- Widgets, pages and cubits never touch `Supabase.instance`, and never import
  the SDK. Both are asserted statically.
- Raw maps stay in the data layer. No cubit state holds an unparsed map.
- The repository is registered in `lib/app/di/injector.dart` and provided
  through `SaleRewardApp`, so a widget test drives the whole flow over a fake
  with no Supabase client.
- The cubit is owned by the **shell**, not the route — so it survives a tab
  round trip and, more importantly, sits *below* the session listener that must
  be able to clear it.

---

## 9. Security boundary

`test/security/retailer_portal_boundary_test.dart` asserts, statically:

- both RPCs are invoked with **zero arguments** — the invoker typedefs are
  nullary, no `params` map is passed (not even an empty one), and no
  organization / retailer / vendor / user / profile / membership / role /
  permission / tenant / token identifier appears at either call site;
- the repository interface exposes no parameter either;
- no Retailer source performs a direct table read or write, and none names a
  Retailer table in code;
- no Retailer source compares a permission code;
- the capability type cannot throw, return a `Failure`, or assert — it can only
  hide a destination;
- the Overview read is not gated on a capability hint;
- the entity holds no identifier of any kind;
- user-facing copy contains no SQLSTATE, function name, table name or
  permission code;
- no Vendor cubit is provided in the Retailer shell, and vice versa;
- the Retailer Manager navigation has no Overview destination and no route into
  the Owner tree;
- `dart_defines.json` remains untracked.

Plus, from the flow tests: no raw UUID is rendered anywhere on the screen, and
no failure state leaks a backend detail.

---

## 10. Hosted verification

`dart_defines.json` is local-only and must never be printed or committed. Verify
its **shape** without revealing the value:

```bash
python3 - <<'PY'
import json
c = json.load(open('dart_defines.json'))
url = c.get('SUPABASE_URL', '')
key = c.get('SUPABASE_PUBLISHABLE_KEY', '')
print('https:', url.startswith('https://'))
print('hosted:', not any(h in url for h in ('localhost','127.0.0.1','10.0.2.2')))
print('key present:', bool(key), 'length ok:', len(key) > 20)
print('no service-role key:', not any('SERVICE_ROLE' in k for k in c))
PY
```

### Web

```bash
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

With a real **Retailer Owner** account, confirm:

1. login succeeds;
2. `get_my_portal_context()` returns `RETAILER_OWNER` and the shell is captioned
   with the Retailer organization name;
3. the Overview loads;
4. the shop counts match the existing web portal exactly;
5. Refresh re-reads and updates;
6. logout clears the state and returns to `/login`.

Then confirm the regressions: a **Vendor** account still enters the Vendor
shell, a **Sales Staff** account still enters the receipt workflow, and a
**Retailer Manager** lands on Staff and is *not* shown the Owner Overview.

### Android

```bash
flutter run -d <device> --dart-define-from-file=dart_defines.json
```

Never `flutter run` without the config — an unconfigured build cannot reach
Supabase.

```bash
flutter build apk --release --dart-define-from-file=dart_defines.json
```

Confirm the release APK declares network access:

```bash
$ANDROID_HOME/build-tools/<ver>/aapt2 dump permissions \
  build/app/outputs/flutter-apk/app-release.apk | grep INTERNET
```

---

## 11. Known limitations

1. **Shop counts are the only shop data.** `list_retailer_owner_portal_shops()`
   is deployed and deliberately unused. The backend audit also records that it
   returns no `shop_id`, so a list could not key its rows or open a detail
   screen even if it were built.
2. **The Retailer Manager workspace is a placeholder.** Its Staff page renders
   an empty state and reads nothing. Its copy predates this milestone and still
   says "not connected to Supabase in this build" — accurate, but more internal
   in tone than the Owner Overview's wording. Worth aligning in the Staff
   milestone.
3. **A shop count above 2^53−1 is refused rather than rendered.** Unreachable in
   practice; refused on every platform so the app and the web portal cannot
   quietly disagree.
4. **`retailer_status` and `membership_status` are always `ACTIVE` in practice.**
   The resolver requires both, so a non-active value cannot occur against the
   deployed contract. The warning path is modelled and tested anyway, so a
   backend change cannot silently render a suspended organization as healthy.
5. **Android startup fixes are on a separate branch.** This milestone is based on
   `main`, which does not yet include `fix/android-release-startup-auth` (PR #13
   — release-APK `INTERNET` permission, bounded startup, sign-in failure
   classification). Android verification of *this* branch is therefore subject
   to those defects until #13 merges.

---

## 12. Next Retailer milestones

Recommended order:

1. **Retailer Owner Shops (read-only).** The natural next step: the Overview
   already shows the counts, and `list_retailer_owner_portal_shops()` is
   deployed. Needs the backend contract fix to return `shop_id` before rows can
   be keyed or opened.
2. **Retailer Staff roster (read-only), Owner and Manager.**
   `list_retailer_staff_members()` is deployed and identical for both roles, and
   it is the Manager's landing — so it is the milestone that turns the Manager
   placeholder into a real workspace.
3. **Assigned Products (read-only), Owner and Manager.**
   `list_retailer_assigned_products()` is deployed and identical for both.
4. **Staff invitations.** Reads and revocation are ready; *sending* needs the
   `send-staff-invitation` Edge Function, which holds the token and the Resend
   key.
