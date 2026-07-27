# Retailer read portal — Shops, Staff and Assigned Products

The second Retailer milestone. It replaces the three empty tabs left by the
Overview milestone with real, backend-powered, **read-only** screens.

---

## 1. Scope

| Screen | Roles | Backing RPC(s) |
| --- | --- | --- |
| Overview | Owner | `get_retailer_owner_portal_context()` *(previous milestone, unchanged)* |
| **Shops** | Owner | `list_retailer_owner_portal_shops()` |
| **Staff** | Owner, Manager | `list_retailer_staff_members()` (+ `list_retailer_staff_invitations()` for Owner) |
| **Products** | Owner, Manager | `list_retailer_assigned_products()` |

**All four RPCs take zero arguments.** Every tenant scope, permission gate,
role-dependent filter and derived state is computed in SQL from `auth.uid()`.

### Not implemented, deliberately

Shop creation, editing, activation/deactivation, deletion or **detail**; staff
invitation sending, resending or revocation; staff role changes; staff
activation/deactivation; post-acceptance shop assignment changes; product
assignment writes; product editing; Retailer audit logs; receipt review.

No write RPC for any of these is named anywhere in `lib/`, and static tests
assert it.

---

## 2. Shops, and the no-`shop_id` limitation

```
list_retailer_owner_portal_shops() → shop_name, shop_code, city,
                                     country_code, shop_status
```

**The contract returns no `shop_id`.** That single fact drives the whole screen:

- the list is **not navigable** — there is no detail route, because there is no
  address to route to;
- **no row is tappable.** No `onTap`, no chevron, no "View details", no edit
  control — not disabled ones, *none at all*. A disabled affordance would imply
  the feature exists and is switched off;
- **a list index is not an identity.** The backend's `order by s.name, s.code
  nulls last, s.id` is stable for one response, but position is a property of a
  response, not of a shop. It is never persisted, sent or used as a key;
- `RetailerShop.presentationKey` exists **only** so Flutter can diff a list. It
  is built from the display fields, is never called an id, is never sent, and is
  never shown. Two identical-looking shops collide on it — harmless, because
  nothing keyed on it is addressable.

`shop_code`, `city` and `country_code` are all nullable in the schema. An absent
one is **omitted from the card**, never rendered as a dash or a placeholder.

### Manager access is *silent*, not a refusal

This is the one contract in the milestone that does **not** raise. Its `where`
clause compares `s.retailer_organization_id =
resolve_retailer_owner_organization('RETAILER_SHOPS_READ')`, and a NULL from
that resolver matches no row. The migration states the intent plainly: an
unauthorized caller "gets an empty list rather than another retailer's estate".

So a Retailer Manager, a Sales Staff member and an Owner whose organization
genuinely has no shops all receive **exactly the same empty result**.

The client preserves that ambiguity rather than resolving it:

- it does **not** probe the caller's role to decide which empty state to show;
- it does **not** convert emptiness into a denial, or a denial into emptiness;
- the empty-state copy describes what is on screen and points at a person,
  rather than asserting a cause;
- the **Manager never reaches the screen at all** — their navigation carries no
  Shops destination and their shell defines no Shops route, so the read is never
  issued. That is the app declining to render a screen whose only possible
  content is nothing, not the client enforcing a permission.

---

## 3. Staff roster

```
list_retailer_staff_members() → membership_id, first_name, last_name,
                                role_code, role_name, membership_status,
                                shop_ids, shop_names, joined_at, created_at
```

**Displayed:** full name, role *name*, membership status, assigned shop *names*,
joined date.

**Never displayed:** `membership_id` and `shop_ids` — neither is carried by the
entity at all, so no UUID can reach state or a screen. `role_code` is carried
(it is the stable value across renames) but is never rendered and is
**excluded from search**, so an internal token cannot surface a row for a reason
the user cannot see.

### The role filter is SQL's, and is not re-implemented

The function ends with `and (v_can_manage or m.status = 'ACTIVE')`, where
`v_can_manage` is `has_organization_permission(retailer,
'RETAILER_STAFF_MANAGE')`. An Owner therefore sees every membership status and a
Manager sees only `ACTIVE` members — decided per caller, on every call.

The client applies **no equivalent filter** and renders exactly the rows it was
given. A static test asserts no roster surface filters by membership status.

`joined_at` is nullable — a membership created by an invitation that was never
accepted has none. It renders as "Not recorded" and is **never** substituted with
`created_at`, which would state a joining day that never happened.

`shop_names` is empty for an Owner and a Manager, who hold no shop rows. The card
says "No shops assigned" rather than leaving a gap that reads as missing data.

**`shop_ids` / `shop_names` mismatch** cannot mis-pair anything, because the
client never pairs them: it reads names only and drops the ids at the parser.
That is a stronger guarantee than validating lengths, which would have to choose
between dropping, truncating and padding — all of which lose information.

---

## 4. Invitation history — Owner only

```
list_retailer_staff_invitations() → invitation_id, first_name, last_name, email,
                                    role_code, derived_state, created_at,
                                    sent_at, accepted_at, revoked_at,
                                    expires_at, failure_code, shop_ids
```

**Displayed:** name, email, intended role *label*, derived state, the one date
that matters for that state, and a delivery-failure notice.

**Never displayed:** `invitation_id` and `shop_ids` (not carried), and
`failure_code` — which is **reduced to a boolean at the parser** and does not
exist beyond it. What a person needs to know is that the email did not arrive,
not which internal code recorded it.

The intended role is mapped through a fixed label table, because this contract
returns only `role_code` (unlike the roster, which returns a name too).
`SALES_STAFF` on screen would be an internal identifier leaking into the UI; an
unrecognised code falls back to a neutral "Another role".

### `derived_state` can be NULL, and that is a real state

The backend's `CASE` has **no `ELSE` branch**. A `PENDING` invitation that is
unexpired, has been sent, and carries a `failure_code` other than
`EMAIL_DISPATCH_FAILED` matches no arm — and PostgreSQL returns `NULL`.

That is reachable on the deployed contract, so it is modelled as
`RetailerInvitationState.indeterminate` and rendered as a neutral "Status
unavailable". Rejecting the row would hide an invitation that genuinely exists;
guessing `PENDING` would assert something the backend declined to say. An
unrecognised non-null token degrades the same way, to `unknown`.

### Why the Manager does not call it

The function resolves through `RETAILER_STAFF_MANAGE` and **raises `42501`** when
that returns NULL, so a Manager always fails it. The Manager's shell constructs
the staff cubit with `includeInvitations: false`, so the request is never issued.

This is **not** the client enforcing the permission — the backend decides and
would keep deciding. It avoids issuing a request whose only possible outcome is a
refusal, which would put a denial notice on a screen where nothing is wrong. If a
Manager's role were granted the permission tomorrow, flipping the flag in the
shell is all that would be needed; the cubit, repository and page are unchanged.

The flag is presentation scope only, and a static test asserts it appears in no
repository or parser.

---

## 5. Assigned Products

```
list_retailer_assigned_products() → product_id, product_code, barcode,
                                    product_name, brand, description,
                                    assignment_status
```

**Displayed:** name, code, brand, barcode, description. **Never displayed:**
`product_id` — not carried by the entity.

Identical contract for both Retailer roles: the same member resolver on the same
`RETAILER_PRODUCTS_READ` permission, so both shells route to the same page. Sales
Staff are refused with `42501`.

### There is no history, and the UI does not imply one

The `where` clause is `a.status = 'ACTIVE' and vp.status = 'ACTIVE'`, so every
returned row is **doubly active** and a withdrawn assignment is simply absent. No
RPC returns inactive assignments to a Retailer.

Consequently there is **no status badge** (it would say the same word on every
card, and imply an inactive variant exists to find), **no status filter, no
"show inactive" toggle and no archive tab.** The note under the header states the
scope once, in words: *"This list shows what is assigned right now. Products are
assigned and withdrawn by the Vendor, and past assignments are not shown."*

`assignment_status` is still parsed and validated — a value that is constant by
construction is exactly the assumption that silently stops being true when a
contract widens.

A Retailer cannot modify assignments at all: that is a Vendor capability on
`PRODUCT_RETAILER_ASSIGN`, and neither assign RPC is named in the Retailer
portal.

---

## 6. Role access summary

| | Overview | Shops | Staff roster | Invitations | Products |
| --- | --- | --- | --- | --- | --- |
| Retailer Owner | ✅ | ✅ | ✅ all statuses | ✅ | ✅ |
| Retailer Manager | ✗ route absent | ✗ route absent | ✅ ACTIVE only *(SQL)* | ✗ not called | ✅ |
| Sales Staff | ✗ | ✗ | `42501` | `42501` | `42501` |
| Vendor | ✗ | ✗ | `42501` | `42501` | `42501` |

Each role owns a **disjoint route prefix** (`/retailer-owner/*`,
`/retailer-manager/*`), so "can this role reach that screen?" is answerable from
the route tree alone. A Manager who types an Owner URL is redirected to their own
landing, and the Owner reads are never issued on their behalf.

---

## 7. Capability hints

Navigation visibility uses the existing backend-derived
`retailer.capabilities` hints from `get_my_portal_context()`. They may only ever
**hide or disable a navigation destination**.

Every screen still relies on its own RPC authorization. A false hint never
suppresses a read: the Overview milestone's test asserting that
`view_retailer_overview: false` does not stop the Overview call still holds, and
the same principle governs these three.

No role-to-permission table exists in Dart. A static test asserts no Retailer
source compares a permission code.

---

## 8. Loading, refresh and partial success

Each tab has **independent state** and its own cubit.

- The shell creates all three cubits but **does not load them.** Each page calls
  `loadOnce()` after its first frame, so entering the shell issues exactly one
  RPC — the Overview's — and opening Shops fetches neither Staff nor Products.
- **Returning to a loaded tab reads nothing.** `loadOnce` is a no-op once the
  phase has left `initial`.
- Every screen has an explicit **Refresh** button *and* pull-to-refresh. Both
  call the same method, which ignores a second call while a read is in flight.
- A refresh **keeps the current rows on screen** while it runs and replaces them
  whole on success. A failed refresh keeps them and says so above them.

### Staff partial success

The roster and the invitation history are **companion reads on different
permissions**, not a transaction. Each has its own phase, rows and problem:

- a roster that loaded is **never erased** because the invitation history failed,
  and vice versa;
- the screen **never claims both failed** when only one did — each section shows
  its own scoped message and its own retry;
- only when *both* fail with nothing loaded does one whole-screen state appear.

---

## 9. Session isolation

Both Retailer shells wrap their subtree in a `BlocListener` on `SessionBloc`
keyed on an **identity** — `({authUserId, organizationId})` — not a boolean. A
boolean cannot tell one Owner from another: a direct `Owner A → Owner B`
transition is `true → true`, so the listener would never run.

On any identity change every cubit is cleared **first**, before anything is
requested, and each `clear()` advances a request token so an in-flight answer is
dropped on arrival.

Cleared: shops, staff roster, invitation history, products, every local search
term, every notice and error, and all pending refresh state. The Overview
reloads; the three tabs return to `initial` and re-read only when opened.

The organization id is compared **locally** and sent nowhere — all four RPCs take
no arguments.

Deterministic tests cover: `Owner A → Owner B`, `Owner → Manager`,
`Manager → Owner`, `Retailer → Vendor`, `Retailer → Sales Staff`,
`authenticated → signed out`, a stale answer landing after a role switch, and an
identical re-emitted session (which re-reads nothing).

---

## 10. Local search

Search is **presentation-only**, applied to rows already read. It issues no
request, so a term never reaches the backend and can never become a predicate the
database evaluates.

| Screen | Matches |
| --- | --- |
| Shops | name, code, city |
| Staff | name, role *name*, shop name, invited email |
| Products | name, code, brand, barcode |

Each search box states its coverage in words, so a user does not conclude a row
is missing when it is merely unmatched by the fields the contract returned.
`role_code` and product `description` are deliberately excluded — the first is an
invisible internal token, the second is prose that produces hits a user cannot
see the reason for.

Search state is cleared on session change. A static test asserts no repository or
data source knows the words `search`, `filter`, `query` or `ilike`.

---

## 11. Failure mapping

One shared taxonomy, `RetailerReadProblem`, in `lib/core/errors/`:

| Problem | Source | Copy | Retry? |
| --- | --- | --- | --- |
| `denied` | `42501` | "Not available to this account" | no |
| `signedOut` | `AuthException` | "Your session has ended" | no |
| `malformed` | parser rejection | "Could not read this" | yes |
| `network` | `http.ClientException` | "Could not reach SalesReward" | yes |
| `timeout` | 20 s elapsed | "This took too long" | yes |
| `unexpected` | anything else | "Something went wrong" | yes |

Only `network` and `timeout` mention the connection. **Discrimination is by
exception type and SQLSTATE only** — nothing reads `error.message`. The three
raising RPCs use three *different* English sentences and all classify
identically, because the SQLSTATE carries the meaning and the sentence is not
part of the contract.

`http.ClientException` is the single check covering both platforms: `postgrest`
propagates the transport exception unchanged, and `package:http` wraps a VM
`SocketException` in a subclass of `ClientException` — so no `dart:io` import is
needed (it does not exist on Flutter web).

**No row is ever "there are none of these".** A malformed body, a denial and an
empty list are three different answers and are never collapsed.

---

## 12. Security boundary

`test/security/retailer_read_portal_boundary_test.dart` asserts, statically:

- all four RPCs are invoked with **zero arguments** — nullary invoker typedefs,
  no `params` map (not even an empty one), and no organization / retailer /
  vendor / shop / membership / invitation / product / user / profile / tenant /
  role / permission / token identifier at any call site;
- every repository method is nullary;
- no Retailer source performs direct table access, and none names a backend table
  in code;
- **no invitation write RPC** and no `send-staff-invitation` reference exists
  anywhere in `lib/`;
- **no shop write RPC** and **no membership write RPC** exists anywhere;
- **no product assignment write RPC** is named in the Retailer portal;
- no Retailer source compares a permission code;
- the roster surfaces re-implement no membership-status filter;
- `includeInvitations` appears in no repository or parser;
- no entity holds an identifier, and no parser reads an id column;
- `failure_code` is not carried onto the invitation entity;
- user-facing copy contains no SQLSTATE, function name, table name or enum token;
- no Retailer presentation source touches Supabase or imports the SDK;
- no cubit state holds an unparsed map;
- no search term reaches a repository or data source;
- the Manager shell and navigation carry no Shops or Overview;
- neither Retailer shell provides a Vendor cubit, and the Vendor shell provides
  no Retailer cubit;
- `dart_defines.json` remains untracked.

Plus, from the flow tests: **no raw UUID** appears on any of the three screens,
and no failure state leaks a backend detail.

---

## 13. Hosted verification

`dart_defines.json` is local-only and must never be printed or committed.

```bash
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

**Retailer Owner:** shops match the web portal · staff roster matches · invitation
history matches · products match · refresh works · logout clears everything.

**Retailer Manager:** staff roster loads with only backend-returned members ·
invitation history absent · products load · Overview inaccessible · Shops
inaccessible.

**Sales Staff / Vendor:** existing workflows unchanged.

---

## 14. Android

```bash
flutter run -d <device> --dart-define-from-file=dart_defines.json

flutter build apk --release --dart-define-from-file=dart_defines.json
aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk | grep INTERNET
```

Never `flutter run` without the config file.

---

## 15. Known limitations

1. **No shop detail, and none is possible** until the backend returns `shop_id`.
2. **Manager Shops denial is invisible** by contract — an empty list, not a
   refusal. The app avoids the screen entirely rather than guessing.
3. **`RetailerOverviewProblem` and `RetailerReadProblem` are structurally
   identical.** The Overview shipped and was device-verified in the previous
   milestone and the instruction was to preserve it, so the two were not merged.
   Consolidating them is a mechanical follow-up.
4. **`formatDayDate` (core) duplicates `formatProductDate` (Vendor).** The new
   one was promoted for the three features that needed it; renaming the working
   Vendor helper is churn this milestone had no reason to spend.
5. **A control at the very bottom of a long page sits below the fold** on a
   phone and needs a scroll before it is tappable. Pre-existing shell behaviour;
   the flow tests use `ensureVisible`, matching the existing Vendor helper.
6. **Invitation `RESERVED`/`indeterminate` states are untested against live
   data** — they need a backend state the hosted environment may not contain.

---

## 16. Next milestones

The read portal is complete. Everything remaining is a **write**, and each needs
its own milestone because each carries a different failure surface:

1. **Staff invitation sending** — needs the `send-staff-invitation` Edge Function
   (holds the delivery credential); the largest and most user-visible.
2. **Invitation revoke / resend** — reads already exist; adds two write RPCs and
   the eligibility rules that stay in SQL.
3. **Staff shop assignment** — `RETAILER_STAFF_SHOP_ASSIGN`; needs shop ids,
   which the staff contract already returns even though this client drops them.
4. **Shop create / edit / status** — blocked on the `shop_id` contract fix, since
   editing requires addressing a row.
