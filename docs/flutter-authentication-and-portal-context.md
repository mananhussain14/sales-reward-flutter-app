# Flutter Authentication & Portal-Context Routing — SalesReward

The first real authentication milestone: email/password sign-in, session
restoration, one trusted call to `public.get_my_portal_context()`, and routing
to the correct role shell — built on the merged role foundation (PR #1).

Companion to [`flutter-application-foundation.md`](./flutter-application-foundation.md),
which covers the design system, themes, shells and navigation this milestone
routes into.

---

## 1. Authoritative backend source

| | |
| --- | --- |
| **Web repository** | `salesreward-admin` |
| **RPC** | `public.get_my_portal_context()` |
| **Migration** | `supabase/migrations/20260729090000_shared_portal_context.sql` |
| **Merged at** | `f527b69` (PR #26, *feat: add shared authenticated portal context*) |
| **Read on** | 2026-07-24 |

The migration adds **exactly one function** and modifies no table, policy, role
or existing RPC. It was executed against local PostgreSQL and its 58 pgTAP
assertions passed (reported with the task). This milestone consumes that
contract and reproduces none of the authorization logic behind it.

Nothing in the web repository was modified, and no migration was created here.

---

## 2. The RPC contract

`get_my_portal_context()` takes **zero arguments** and returns one `jsonb` value,
never SQL NULL, never zero rows. Identity is derived from `auth.uid()`.

```json
{
  "context_version": 1,
  "portal_kind": "VENDOR_SUPER_ADMIN | RETAILER_OWNER | RETAILER_MANAGER | SALES_STAFF | NONE",
  "vendor":   null | { "organization_id": "uuid", "organization_name": "string" },
  "retailer": null | {
    "kind": "RETAILER_OWNER | RETAILER_MANAGER | SALES_STAFF",
    "organization_id": "uuid",
    "organization_name": "string",
    "capabilities": {
      "view_retailer_overview": bool, "view_shops": bool, "view_staff": bool,
      "manage_staff": bool, "assign_staff_shops": bool,
      "view_assigned_products": bool, "submit_receipts": bool
    }
  }
}
```

Properties this client depends on, all guaranteed by the migration:

- **Vendor-first precedence.** A caller who holds both roles gets
  `portal_kind: VENDOR_SUPER_ADMIN`, while their `retailer` block is still
  populated so the Retailer portal stays reachable without a second call.
- **`NONE` is a decision, not an error.** Every unauthorized case — signed out,
  suspended, ambiguous multi-Retailer, no role — returns the identical
  `NONE`/null/null value. The function raises no exception of its own.
- **Capabilities are resolver-derived hints.** Each flag is computed by the same
  resolver the operation it describes calls, so a hint cannot drift from its
  gate. They are still only hints.
- **`anon` is granted nothing.** A call without a session is a transport
  refusal, distinguishable from a well-formed `NONE`.

### How the client uses the result

The RPC result is used for **presentation and navigation only**: which shell to
open, which organization name to caption it with, and which destinations to
show. Every protected operation is still authorized by Supabase, in SQL, on
every call. The client:

- never accepts a role from user input, email, profile metadata or local
  storage;
- never chooses an organization;
- never reproduces a backend join or a permission rule;
- never treats a capability flag as authorization;
- never routes on cached role data without re-resolving when the user changes.

---

## 3. Architecture

Clean Architecture, one feature (`features/auth`), Supabase confined to the data
layer.

```
features/auth/
├── domain/
│   ├── entities/
│   │   ├── portal_kind.dart          PortalKind, RetailerKind — fail-closed parse
│   │   ├── retailer_capabilities.dart RetailerCapabilities + RetailerCapability
│   │   ├── portal_context.dart       PortalContext, Vendor/RetailerContext, version
│   │   └── auth_user.dart            AuthUser + AuthChange (signed in/out/refreshed)
│   └── repositories/
│       ├── auth_repository.dart          sign in/out, currentUser, changes stream
│       └── portal_context_repository.dart resolve() → resolved / denied / failed
├── data/
│   ├── datasources/
│   │   └── portal_context_data_source.dart  the nullary RPC invoker
│   ├── models/
│   │   └── portal_context_parser.dart       jsonb → PortalContext, fail-safe
│   └── repositories/
│       ├── supabase_auth_repository.dart          GoTrue → AuthChange
│       └── supabase_portal_context_repository.dart call → parse → classify
└── presentation/
    ├── bloc/session_bloc.dart         the session coordinator
    ├── cubit/login_cubit.dart         the login form
    ├── cubit/logout_cubit.dart        sign-out + its own failure state
    └── pages/
        ├── login_page.dart, splash_page.dart, unavailable_page.dart
        └── access_denied_page.dart
```

`UnimplementedPortalContextRepository` (the previous milestone's honest stub) is
**replaced** by `SupabasePortalContextRepository` through DI. The
`PortalContextRepository` abstraction is kept, not deleted.

### The presentation layer never touches Supabase

`Supabase.instance.client` and every `supabase_flutter` type stay in the data
layer (plus `bootstrap.dart`, the DI `injector.dart` that wires the client in,
and `failure_mapper.dart`, the one seam that classifies SDK exceptions). A
source-safety test enforces this.

---

## 4. The authentication flow

```
App starts
  → SessionBloc subscribes to auth changes and reads the restored session
     → no session          → SessionUnauthenticated → /login
     → a session exists     → SessionResolving → get_my_portal_context()
         → resolved(kind)    → SessionActive     → that role's shell
         → NONE              → SessionDenied      → /access-denied
         → threw / malformed → SessionUnavailable → /unavailable (retry)
```

### Session restoration

`SessionBloc` evaluates `authRepository.currentUser` directly at startup rather
than waiting for GoTrue's replayed `initialSession` event — relying on the
stream alone would race restoration against the first frame. The two paths are
made idempotent by the coordinator's dedupe, so a replayed event after the
direct read changes nothing.

### The four coordinator rules

The whole reason authentication and portal resolution are joined in one BLoC is
so these can be stated and tested once:

1. **Never resolve without a session.** Checked at startup *and* on every retry.
   The RPC is `authenticated`-only; calling it signed-out would misreport as
   "unavailable".
2. **A token refresh changes nothing.** `tokenRefreshed` for the same user is
   ignored outright — no re-resolution, no state change, no bounce to login.
   This is the bug that otherwise logs users out hourly.
3. **A different user discards the previous context first.** On a genuine user
   switch the old context is cleared (`SessionInitial`) *before* the new resolve
   begins, so one person's shell can never render against another's session.
   Arriving from signed-out emits no spurious clear.
4. **One resolution at a time.** A re-entrancy guard collapses duplicate auth
   events and repeated retry taps, so router rebuilds cannot produce two
   concurrent RPC calls.

---

## 5. The routing state machine

`redirectFor(SessionState, location)` is a **pure function**, tested against a
table. It is the whole guard.

| Session state | Home | Role routes redirect to |
| --- | --- | --- |
| initial / resolving | `/` (splash) | splash — **no shell before resolution** |
| unauthenticated | `/login` | login |
| active(kind) | that kind's landing | own group allowed; other group → own landing |
| denied (`NONE`) | `/access-denied` | access-denied |
| unavailable | `/unavailable` | the retry screen |

- **No shell flashes before resolution:** while indeterminate, every role route
  redirects to the splash.
- **Route isolation is preserved:** an active caller may roam only within their
  own role group; any other group redirects to their own landing, so a user
  cannot reach another shell by typing a URL. The `ShellRoute` builder also
  re-checks the resolved kind and refuses if it somehow does not match.
- **The guard is presentation, not security.** Supabase re-decides every
  operation in SQL. If the guard were deleted, a wrong-role URL would reach a
  shell whose every query was refused.

Duplicate RPC calls from router rebuilds are avoided two ways: the coordinator's
re-entrancy guard, and `refreshListenable` firing only on genuine session-state
changes.

---

## 6. Error versus denial semantics

The distinction the migration is emphatic about, preserved end to end:

| Backend outcome | Result | State | Screen | Retry? |
| --- | --- | --- | --- | --- |
| `portal_kind: NONE` | `PortalContextDenied` | `SessionDenied` | Access denied | No — same answer forever |
| RPC threw | `PortalContextFailed` | `SessionUnavailable` | Retry | Yes |
| Body unparseable / wrong version | `PortalContextFailed` | `SessionUnavailable` | Retry | Yes |

A malformed body is a **failure**, not a denial: the backend refusing you and
the backend answering incomprehensibly are different events, and only one is
worth retrying. The retry re-checks the session first, so a token that lapsed
while the failure screen was up sends the user to login rather than into another
doomed call.

### The parser fails safe

`PortalContextParser` throws `PortalContextFormatException` — which the
repository turns into an operational failure, never a role — for:

- an unknown or missing `portal_kind`;
- a `context_version` that is not exactly `1` (a **higher** version means the
  backend is newer than this build; guessing is what the version field exists to
  prevent);
- a missing required field, a blank name, or a non-UUID organization id;
- a `portal_kind` naming a block that is absent, or disagreeing with
  `retailer.kind`.

The one safe default: a **missing capability → `false`**. A hint that cannot be
read is a destination not offered, which can only ever hide, never grant — and
the backend re-decides the operation regardless.

---

## 7. Security boundaries

- **Only the publishable key ships.** The client is initialized with the URL and
  `SUPABASE_PUBLISHABLE_KEY` alone. No service-role key, Resend key or OCR
  credential appears in the binary, a `--dart-define`, or CI.
- **The RPC call carries no identity.** The data source models the call as a
  **nullary** `PortalContextInvoker` — there is no argument to pass, so a user
  id, organization id, role, email, token or tenant *cannot be expressed* at
  that boundary. A source test also asserts no such name appears near the call.
- **No hardcoded role, ever.** No demo credentials, no `?? PortalKind.x`
  fallback, no role from `SharedPreferences` or a decoded JWT. Asserted at
  runtime and by source scan.
- **Sign-out is local scope**, matching the web, so other sessions of the same
  person survive.
- **Generic auth errors.** A wrong password and an unknown account produce the
  identical login message — the screen is never an account-enumeration oracle.
- `dart_defines.json` is git-ignored and untracked.

---

## 8. Tests

`flutter test` — **265 passing**, 17 files. New this milestone:

| File | Covers |
| --- | --- |
| `features/auth/portal_context_parser_test.dart` | Every valid kind, vendor/owner/manager/staff, capability values, `NONE`; and every fail-safe rejection — unknown kind, unsupported version, malformed UUID, incoherent block |
| `features/auth/session_bloc_test.dart` | Startup (no session / restored / NONE / failure), sign-in, sign-out, **token refresh does not log out**, user change clears context, duplicate events don't double-resolve, retry, retry-after-expiry → login |
| `features/auth/portal_context_repository_test.dart` | RPC name, **zero-argument invocation**, called once, resolved / denied / failure classification, malformed → failure |
| `features/auth/login_cubit_test.dart` | Validation, trimmed email, generic rejection, unavailable ≠ rejected, no duplicate submit |
| `features/auth/logout_cubit_test.dart` | Sign-out call, failure surfaced, no duplicate |
| `features/auth/login_page_test.dart` | No overflow at 360×640 and 390×844, keyboard-safe, both themes, visibility toggle, no sign-up/forgot/social affordances |
| `app/auth_flow_test.dart` | Full widget flow: each kind → its shell, NONE → denied, failure → retry, **no shell flash**, login success, invalid-credentials stays, logout clears shell, token refresh keeps shell, cross-role URL denied, retry succeeds |
| `app/router/routing_state_machine_test.dart` | `sessionHome` and `redirectFor` as a full truth table |

Updated: navigation (capability filtering), shells (context caption, capability
hiding), theme-mode (account sheet), startup (DI wiring), and the two security
suites (no hardcoded role, no secrets, no-identity RPC args, no direct Supabase
in presentation).

---

## 9. Current limitations

Implemented: email/password sign-in, session restoration, auth-state listening,
the real portal-context repository, one RPC call, trusted routing, logout, and
the loading / unavailable / unauthenticated / access-denied states.

**Not** implemented in this branch (deliberately):

- registration, invitation acceptance, password reset, magic links, MFA;
- receipt submission, camera, shop / staff / product loading;
- any dashboard with real data — the landing screens still show placeholder
  "Unavailable" stats;
- deep linking, offline session handling, biometric unlock;
- **secure session storage.** The app uses `supabase_flutter`'s default session
  persistence. The architecture handoff calls for `flutter_secure_storage`
  (Keychain / EncryptedSharedPreferences); adopting it is the first item of the
  next milestone.
- **re-resolution on app resume.** The coordinator re-resolves on a user change,
  but nothing yet dispatches a re-resolve on `AppLifecycleState.resumed`.

Unresolved product decisions carried forward: Q1 receipt viewing, Q2 multi-
Retailer (currently a silent `NONE`), Q3 Manager tenant name, Q4 Vendor on
mobile, Q5 offline capture, Q6 deep-link domain, Q8 owner-invitation revoke.

---

## 10. Next recommended milestone

**Sales Staff receipt submission, end to end** — now unblocked for its first
half. In order:

1. **Secure session storage** — swap in `flutter_secure_storage`, and purge the
   session, cached context and any queued data on sign-out.
2. **Re-resolve on resume** — dispatch `SessionContextRequested` on
   `AppLifecycleState.resumed` so a server-side role change is picked up.
3. **Assigned shops** — `list_my_assigned_receipt_shops()` (ready today).
4. **Capture + submit** — the `submit-receipt` Edge Function (camera → downscale
   → hash the exact bytes → upload), then **history** via
   `list_my_receipt_submissions()`.

Q6 (deep-link domain) must be answered before invitation acceptance, which is a
separate slice.
