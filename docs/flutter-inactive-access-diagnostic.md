# Flutter — inactive-access diagnostic

The signed-in access-denied screen can now say *why*, when saying why is safe.

A Retailer Owner, Manager or Sales Staff member whose Retailer was deactivated —
or whose own membership was — used to reach a generic, reason-free card and stay
there until they relaunched the app. They now read one approved sentence naming
the cause, and can recover in place with **Check access again** once the cause is
resolved. No sign-out, no relaunch.

**This changes the explanation. It changes no enforcement.** Every read and write
behind these screens is still decided in SQL by a `SECURITY DEFINER` function
that derives the caller from `auth.uid()` on every call.

---

## 1. The backend contract

```sql
public.get_my_lifecycle_access_state()
returns table (access_state text)
language plpgsql stable security definer set search_path = ''
```

Deployed in `20260810090000_retailer_staff_membership_lifecycle.sql`. **No
backend change was made or needed for this milestone.**

* **Zero parameters.** The subject is `auth.uid()` and can only ever be
  `auth.uid()`. There is no profile, membership, organization, role or tenant
  argument, so a caller cannot ask about anybody else.
* **One row, one column, one word** from a closed vocabulary.
* Granted to `authenticated` only. `anon` is explicitly revoked; `service_role`
  is granted nothing, deliberately — it has no `auth.uid()` and could only ever
  describe nobody.
* The only error it raises is `42501`, for an unauthenticated caller.
* It returns **no** identifier, organization name, role code, count, raw status,
  timestamp or database message. There is nothing of that kind to drop.

### Precedence, as deployed

| # | Condition | Result |
|---|---|---|
| 1 | no `profiles` row | `NO_SUPPORTED_ACCESS` |
| 2 | profile status is not `ACTIVE` | `PROFILE_INACTIVE` |
| 3 | zero supported Retailer contexts | `NO_SUPPORTED_ACCESS` |
| 4 | more than one supported context | `AMBIGUOUS` |
| 5 | organization status is not `ACTIVE` | `ORGANIZATION_INACTIVE` |
| 6 | membership status is not `ACTIVE` | `MEMBERSHIP_INACTIVE` |
| 7 | otherwise | `ACTIVE` |

**Organization precedes membership, and the order matters when both are
inactive.** Telling a Sales Staff member "your membership was deactivated" when
their whole Retailer is suspended would send them to an Owner who is themselves
locked out and can do nothing about it.

This client reproduces none of that logic. There is no join over profiles,
memberships, roles or organizations anywhere in `lib/`, and no precedence rule.

---

## 2. What the screen says

| Diagnostic result | Title | Body |
|---|---|---|
| `ORGANIZATION_INACTIVE` | Retailer inactive | This Retailer is currently inactive. Contact the Vendor or your Retailer administrator. |
| `MEMBERSHIP_INACTIVE` | Account inactive | Your access to this Retailer is inactive. Contact your Retailer administrator. |
| `PROFILE_INACTIVE` | Account unavailable | Your SalesReward account is currently inactive. Contact support or your administrator. |
| `AMBIGUOUS` | Account setup needs attention | More than one Retailer context is available for this account. Contact support. |
| `ACTIVE` | *(existing generic card, unchanged)* | |
| `NO_SUPPORTED_ACCESS` | *(existing generic card, unchanged)* | |
| unavailable / malformed / unknown | *(existing generic card, unchanged)* | |

The four lifecycle bodies are followed by one Flutter-specific line:

> If this changes, use Check access again.

The first four strings are byte-identical to the web's approved copy in
`lib/staff/lifecycle-access-state.ts`. The closing line exists only here, because
the web's access-denied page is a server component with no equivalent affordance.

### Why two states keep the generic card

`ACTIVE` and `NO_SUPPORTED_ACCESS` have **no entry** in the copy map, so
`noticeFor` returns null and the ordinary card renders. Both omissions are
deliberate and both match the web:

* **`ACTIVE`** — nothing about this person's lifecycle explains the refusal, so
  some other condition did: a missing permission, a wrong role, a route they are
  simply not entitled to. Saying anything specific would be a guess, and a wrong
  one. `ACTIVE` is emphatically **not** an authorization grant.
* **`NO_SUPPORTED_ACCESS`** — the ordinary "you are signed in but this is not for
  you" case, which is exactly what the existing card already says. Distinct copy
  would tell an unauthorized, possibly hostile account that it holds no Retailer
  membership at all — a fact the screen deliberately does not disclose.

### Why both controls appear in every state

**Check access again** and **Sign out** are offered identically for all seven
outcomes above. That is a disclosure decision, not a convenience one: if the
recovery control appeared only alongside a lifecycle explanation, its *absence*
would itself reveal that the caller is in one of the states that has none —
recreating, through the affordance set, the oracle the fixed copy exists to
close. A test asserts that the `ACTIVE`, `NO_SUPPORTED_ACCESS` and unavailable
renderings are textually identical.

---

## 3. When the diagnostic runs

Once per **denied episode**, and never otherwise.

It runs when, and only when, `SessionBloc` is in `SessionDenied` — a verified
`portal_kind: NONE` answer from `get_my_portal_context()`. It does **not** run:

* before portal-context resolution;
* from an active portal shell;
* after an ordinary feature failure or any `42501`;
* from `SessionUnavailable`;
* on app resume;
* on a timer, and there is no polling anywhere.

### The gate is on the session, not on mounting

`_roleShell` in `app_router.dart` renders `const AccessDeniedPage()` whenever the
session is not `SessionActive` for its own role, and pages genuinely co-mount for
a frame or two during a go_router transition. A diagnostic fired from `initState`
alone would therefore run for callers who have not been denied anything. The page
reads `SessionBloc.state is SessionDenied` and renders a diagnostic-free fallback
otherwise — in which case the diagnostic repository is never even resolved.

### Why the episode is counted rather than inferred from the page's lifetime

The tempting design is to let the widget lifetime bound the diagnostic: press
**Check access again**, the session goes `Denied → Resolving → Denied`, the router
shows the splash in between, the page is rebuilt, and a fresh cubit asks again.

**That is only what happens when the portal-context RPC takes a real round trip.**
When the resolution is fast, `SessionResolving` and the next `SessionDenied` land
in a single frame, `redirectFor` never gets a chance to move the location, the
page's `State` survives, and a mount-scoped cubit would never re-ask — leaving the
*previous* episode's copy on screen after the user explicitly asked for a fresh
answer. A member reactivated moments ago would keep reading "your access to this
Retailer is inactive", and the faster the backend, the likelier it gets.

So `AccessDeniedPage` counts entries into `SessionDenied` and keys the
`BlocProvider` on that counter. Each denial builds a genuinely new cubit which
asks exactly once; the previous cubit is closed, and its in-flight answer is
dropped by its own guards. This is **not** an in-place refresh — no cubit ever
performs a second read — and it is correct whether or not the router happens to
unmount the page.

*(This was found by a failing test, not by reading the code. The earlier
architectural probe used a manually-completed fake, which held `SessionResolving`
open artificially and made the remount look guaranteed.)*

---

## 4. Check access again

1. The button dispatches the **existing** `SessionContextRequested()`. No new
   session event, no new state, and `SessionBloc` is unchanged.
2. `SessionBloc` re-checks that a session still exists, then re-runs canonical
   `get_my_portal_context()` resolution.
3. **Restored** → `SessionActive` → the router sends the user to their role
   landing. No sign-out, no re-authentication.
4. **Still denied** → `SessionDenied` → a new episode → one fresh diagnostic →
   refreshed copy.
5. **Operational failure** → `SessionUnavailable` → the existing
   `/unavailable` screen with its own **Try again**. An outage is never dressed
   as a lifecycle explanation.

The button never calls the diagnostic. The diagnostic explains a refusal and
cannot lift one; only `PortalContextResolved` can restore access.

**Duplicate presses are collapsed three times over**: the control is disabled
while `SessionResolving`; `SessionBloc._beginResolution` drops a same-user
request while one is in flight; and the page usually unmounts within a few
frames. A test presses rapidly and asserts exactly one resolution.

### The splash bounce is intentional

`sessionHome(SessionResolving)` is the splash, so a slow resolution briefly
shows it before returning. This is pre-existing behaviour shared with
`UnavailablePage`'s **Try again**, and the router was deliberately **not**
special-cased to remove it: `redirectFor` is a pure function pinned by a
table-driven suite and load-bearing for the "no shell before resolution"
invariant. A test asserts the bounce so that removing it stays a decision.

---

## 5. Stale results and session safety

The cubit is **page-scoped**: created by `AccessDeniedPage`, disposed with it,
never registered in the service locator, never app- or shell-scoped, no `static`,
nothing written to disk. There is consequently no object that outlives the page
in which one person's diagnostic could survive to be rendered under another's.

On top of that structural guarantee, every result passes a four-part commit
check:

```
if (isClosed)                          return;   // page gone
if (generation != _generation)         return;   // superseded
if (currentOwner == null)              return;   // signed out mid-flight
if (currentOwner != owner)             return;   // subject changed mid-flight
```

* The **owner** is captured from `AuthRepository.currentUser` *before* the
  request and re-read *after* the await — the same two-point check
  `SessionBloc._onResolutionSettled` performs.
* A null owner before the request means **no request at all**: no session, no
  subject, and no sign-out either — that decision belongs to the session
  coordinator.
* `close()` advances the generation before delegating, so an in-flight read is
  invalidated rather than merely unable to emit.
* The cubit **subscribes to nothing** — not `AuthRepository.changes`, not
  `SessionBloc`. The router unmounts the page on every session transition, and a
  second subscription would be a second opinion about who is signed in.
* Ordering cannot matter: the diagnostic is not an input to routing or
  authorization, so a result arriving out of order can only render into a page
  that is about to go away.

---

## 6. Strict parsing, and one deliberate divergence

| # | Rule |
|---|---|
| 1 | root must be a `List` |
| 2 | exactly one row — zero and two are equally refused |
| 3 | the row must be a `Map` |
| 4 | `access_state` must be present |
| 5 | its value must be a `String` |
| 6 | exact, case-sensitive match against the six codes |
| 7 | no trimming |
| 8 | no case-folding or coercion |
| 9 | extra keys ignored — a future column does not break this build |

There is no `trim()`, no `toUpperCase()`, no `??` fallback and no default branch.
`' ACTIVE '`, `'active'`, `'Active'` and `'ACTIVE\n'` are all **refused**, not
repaired. Repairing them would be guessing at intent, and a build that accepted
`'active'` would also accept whatever a future migration renamed it to.

**This is stricter than the deployed web parser**, which does
`Array.isArray(data) ? data[0] : data` and so tolerates a non-array root and
extra rows. Both agree on every response the function can actually produce, so
this is hardening rather than a contract disagreement — but the web version is
**not** the reference implementation for this file. If the two must converge, the
web one is the one to tighten.

Every parser failure becomes `LifecycleAccessUnavailable`, which renders the
ordinary access-denied card.

---

## 7. Error handling

```dart
try {
  final Object? raw = await _dataSource.fetch().timeout(_timeout);
  return LifecycleAccessResolved(LifecycleAccessParser.parse(raw));
} on Object catch (_) {
  return const LifecycleAccessUnavailable();
}
```

One `try`, one `catch`, and **the error is deliberately unbound**. That is the
enforcement mechanism, not a style choice: with no identifier in scope there is
nothing to inspect, log, branch on or accidentally surface. A reviewer does not
have to verify that `error.message` is unused — it is unreachable.

Everything collapses identically: `PostgrestException` on any SQLSTATE (`42501`,
`55000`, `22P02` included), `AuthException`, `ClientException`,
`TimeoutException`, `RpcFormatException`, and any other object.

`LifecycleAccessUnavailable` is a const with **no fields** — no `Failure`, no
SQLSTATE, no message, no identifier.

**The shared `mapSupabaseError` is deliberately not used.** It maps
`42501 → DeniedFailure`, which would recreate exactly the
unauthenticated-versus-transport distinction this feature exists to collapse. A
caller able to tell those apart holds a probe. A boundary test asserts the
diagnostic imports neither `failure_mapper.dart` nor `sql_state.dart`.

There is **no retry**, no fallback query, no second RPC and no direct table
access. One `fetch()` per `read()`, bounded at 20 seconds to match
`portalContextTimeout`.

---

## 8. Files

**Domain (pure)**
```
domain/entities/lifecycle_access_state.dart          six-member enum, no wire codes
domain/repositories/lifecycle_access_repository.dart Resolved | Unavailable + interface
```

**Data**
```
data/datasources/lifecycle_access_rpc_data_source.dart  nullary invoker, the one RPC name
data/models/lifecycle_access_parser.dart                the nine strict rules
data/repositories/supabase_lifecycle_access_repository.dart
```

**Presentation**
```
presentation/cubit/lifecycle_access_cubit.dart        page-scoped, generation + owner guards
presentation/cubit/lifecycle_access_view_state.dart   phase + optional enum, nothing else
presentation/widgets/lifecycle_access_copy.dart       the only approved-copy module
presentation/pages/access_denied_page.dart            MODIFIED — episode counter, gate, wiring
core/widgets/sr_lifecycle_notice_view.dart            the explained card
core/widgets/sr_access_denied_view.dart               MODIFIED — optional action only
```

`SrAccessDeniedView` gained **only** `onCheckAccessAgain` and `checkingAccess`.
Its copy is untouched, and with a null callback it renders exactly as before —
which is what the route guard's fallback relies on. Its standing prohibition
stands: **no `role`, `reason`, `title` or `body` parameter**, because a copy
override would be that parameter under another name.

---

## 9. The enum carries no wire code

`LifecycleAccessState` has no `code` field, no `name` override and no
`toString()` yielding one. The six strings live in a single private map inside
the parser.

That is not tidiness. A widget cannot render a state code it has no way to
obtain, so "never display a raw backend state" is enforced by the **shape of the
type** rather than by a reviewer noticing an interpolation. Tests additionally
assert that no rendered `Text` on the screen contains any of the six codes, a
UUID, a SQLSTATE or a backend message.

---

## 10. What this milestone does not do

* No backend, migration, grant, Edge Function or SQL change.
* No change to `SessionBloc`, `session_event.dart`, `session_state.dart`,
  `app_router.dart` or `app_routes.dart`.
* No change to the Vendor Retailer lifecycle write (PR #18) or the Retailer staff
  membership lifecycle write (PR #19). Their boundary tests were **narrowed**,
  from "the diagnostic does not exist anywhere" to "it does not exist *here*";
  every write protection in both files is unchanged.
* No app-resume detection. Reactivation is picked up by **Check access again**,
  by a relaunch, or by the next session resolution — not by a lifecycle observer.
* No Android-specific code, and no polling of any kind.

### A known, deliberate limitation

The cubit does **not** retain a previous episode's resolved state. If mount 1
resolves `ORGANIZATION_INACTIVE` and the user presses **Check access again**, and
the second diagnostic hits a transport failure while the denial persists, the
screen falls back from "Retailer inactive" to the generic card.

Retaining across episodes would mean hoisting the cubit above the router, which
reintroduces cross-user retention risk and could show *"This Retailer is
currently inactive"* to somebody whose Retailer was reactivated seconds earlier.
**A fresh generic answer beats a stale specific one**, so this is a decision
rather than an oversight, and a cubit test is named for it.
