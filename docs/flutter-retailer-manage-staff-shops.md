# Retailer Manage Staff Shops

The fourth Retailer milestone, and the Retailer portal's **first RPC write**. It
adds an Owner-only Manage Shops editor to the existing Staff screen, backed by
the same `set_retailer_staff_shop_assignments()` function the Next.js portal
calls.

It also closes the gap recorded as limitation 7 of
`docs/flutter-retailer-read-portal.md` and limitation 5 of
`docs/flutter-retailer-invite-staff.md`: an accepted staff member's shops were
previously unchangeable from any client, because no post-acceptance write
existed. One now does, and this milestone consumes it.

---

## 1. Scope

| Capability | Where |
| --- | --- |
| Edit an accepted Sales Staff member's ACTIVE shops | **This milestone** — Flutter |
| Assignable-shop picker | Existing `list_retailer_staff_assignable_shops()`, shared with Invite Staff |
| Canonical roster reread after a save | Existing `list_retailer_staff_members()` |
| Staff roster, invitation history, Invite Staff | Previous milestones, unchanged |

### Not implemented, deliberately

- **Staff activation / deactivation.** No RPC for it is named anywhere in
  `lib/`.
- **Staff role changes.** Likewise.
- **Invitation acceptance.** It happens by following the emailed link into the
  Next.js portal.
- **Invitation revoke / resend controls.** Unchanged from the previous
  milestone: still the web portal's.
- **Mobile deep links.** No custom scheme, no App Links, no Universal Links.
- **A zero-Shop stand-down.** Submitting an empty set is refused locally *and*
  by the backend (`23514`). Standing a Sales Staff member down to no shops is a
  different operation with different consequences, and this editor is not it.
- **Shop create / edit / status writes** of any kind.

`test/security/retailer_manage_staff_shops_boundary_test.dart` asserts that no
RPC for any of those is named in `lib/`.

---

## 2. Role access

The editor is offered only when **three** conditions hold, and none of them is a
role label compared in Dart:

1. **The shell provided the write.** `RetailerManageStaffShopsCubit` is
   constructed only in `RetailerOwnerShell`. A Retailer Manager's widget tree
   contains no shop-assignment machinery at all, so the editor could not be
   rendered there even by mistake.
2. **The caller's backend-derived capability hint offers it.**
   `RetailerCapability.assignStaffShops` comes from the portal context's
   `assign_staff_shops` flag, which the backend computes by calling the same
   resolver, with the same permission (`RETAILER_STAFF_SHOP_ASSIGN`), that the
   write itself resolves through. The hint therefore cannot drift from its gate.
3. **The row is eligible.** `RetailerStaffMember.isEditableSalesStaff` is
   `roleCode == 'SALES_STAFF' && status.isActive && joinedAt != null` — Sales
   Staff, ACTIVE membership, and accepted. All three are read from the backend's
   own answer.

| Role | Sees the roster | Sees Manage Shops | Can invoke the write |
| --- | --- | --- | --- |
| Retailer Owner | yes | for eligible rows | subject to SQL |
| Retailer Manager | yes (ACTIVE only, decided in SQL) | **no** | refused in SQL |
| Sales Staff | no (refused by the roster read) | no | refused in SQL |
| Vendor | not applicable | no | refused in SQL |

**All three signals are presentation scope, never authorization.** The database
re-derives the caller, the Retailer, the permission and the target's own role and
status on every call, and refuses a hand-crafted request whatever any UI
rendered. A false capability hint is a reason not to advertise a dead end — never
proof of anything.

The action is **absent** for Retailer Managers, Retailer Owner rows, inactive
memberships, never-accepted memberships, and every invitation-history card. It is
absent rather than disabled: a greyed-out control would imply the feature exists
and is merely switched off.

---

## 3. The RPC

```sql
public.set_retailer_staff_shop_assignments(
  p_membership_id uuid,
  p_shop_ids      uuid[]
)
returns table (
  shops_added     integer,
  shops_removed   integer,
  shops_unchanged integer
)
```

Called through `SupabaseClient.rpc`, on the **caller's own session**. That is the
whole point: `auth.uid()` inside the function is the real person, the Retailer is
resolved in PostgreSQL, the membership is matched against *that* Retailer, and
every submitted shop is validated against it too.

### Exact arguments

```dart
client.rpc<Object?>(
  setRetailerStaffShopAssignmentsRpc,
  params: <String, Object?>{
    staffShopAssignmentMembershipParameter: membershipId, // 'p_membership_id'
    staffShopAssignmentShopIdsParameter: shopIds,         // 'p_shop_ids'
  },
);
```

Two keys, and there is no third. **Not sent:** organization id, Retailer id,
tenant id, actor / auth-user / profile / member-role id, invitation id, email,
role code, permission code, status, timestamp, audit metadata, current
assignments, separate add/remove arrays, token, or idempotency key. The request
entity has no field any of them could occupy, and the invoker typedef has no
parameter — both are pinned by the boundary test.

**No Edge Function.** The invitation send is a function call because it holds a
delivery credential and three service-role RPCs; this operation is a plain RPC
under the caller's own token. No service-role key exists anywhere in this
application.

### Canonical identifier

`p_membership_id` is `RetailerStaffMember.membershipId` — `organization_members.id`
as returned by `list_retailer_staff_members()`. Never an auth user id, profile
id, email, invitation id, member-role id, staff name, or list index. Two
colleagues may share a name; a list index is a property of one filtered response
rather than of a person.

**It is never rendered.** It is not put in a label, a semantics string, a widget
key, or the local search index.

### Result shape

Exactly one row, three non-negative integers. Parsed strictly by
`RetailerStaffShopAssignmentParser`, which refuses: a non-list body, a non-object
row, **no** row, **more than one** row, a missing field, a non-integer value
(including a whole `double`), and a negative count. Unrecognized extra keys are
ignored — the contract is additive.

A malformation becomes `RetailerStaffShopAssignmentProblem.malformedResponse`,
whose copy says the change **may or may not** have been saved and points at the
roster. It is never reported as a failed write: the statement may well have
committed, and only this build's ability to read the answer failed.

---

## 4. The ACTIVE-Shop projection

This is the rule the whole feature is shaped around.

`list_retailer_staff_members()` returns a member's shops through a subquery
ending `removed_at is null and s.status = 'ACTIVE'`, and
`list_retailer_staff_assignable_shops()` filters `status = 'ACTIVE'` itself. So
**every shop this client can see is an ACTIVE one**, and a member may also hold a
live assignment to a suspended or deactivated shop that no contract returns.

Consequences, all enforced:

- the editor **preselects only** the roster's ACTIVE shop ids, intersected with
  the assignable options actually on offer;
- selection is possible **only** from currently assignable ACTIVE shops;
- the save submits the **complete desired visible ACTIVE set**;
- the backend **preserves** the hidden non-ACTIVE assignments — it retires only
  ACTIVE rows the request did not name;
- nothing in this client attempts to remove a hidden assignment, and nothing
  claims the visible list is every row;
- the returned counts are a **change summary of the visible replacement**, never
  the employee's total shop count.

A roster shop id that is absent from the latest assignable options is dropped
from the preselection **silently and correctly**: it stopped being ACTIVE between
the two reads, so it is a hidden assignment the write preserves rather than
something a person deselected. That case is distinguished in
`_applyOptions` from a shop the person *ticked* disappearing, which does warn.

### Replacement, not a diff

`p_shop_ids` is the whole desired set. The client computes no additions and no
removals; the function does, which is why counts come back rather than going out.
Sending a diff would put that computation in two places, with the client working
from a snapshot.

---

## 5. Selection behaviour

| Situation | Behaviour |
| --- | --- |
| Opening | Options re-read every time — availability is exactly what goes stale. Preselection = roster ACTIVE ids ∩ options. |
| Duplicates | Impossible: the selection is a `Set`, keyed on the backend's id. The request canonicalizes and sorts again. |
| An id not in the options | Ignored outright by `shopSelectionToggled`. |
| Zero selected | Save disabled; `save()` refuses locally with `noShopsSelected`; the backend refuses with `23514`. |
| Unchanged selection | Save disabled — order-insensitive comparison against the baseline the editor started from. |
| Options read fails | Editor-scoped notice, a retry for the **read only**, Save disabled, roster untouched. Never converted into a write failure. |
| A ticked shop disappears from a later read | Removed from the valid set, `availabilityChanged` set, Save **blocked** until reviewed (an explicit "Review and continue", or any selection change). Never silently submitted. |
| Editor open | Selection is preserved for as long as it stays open. |

`submittableShopIds` is the selection intersected with the options the backend
returned, so an id that is no longer assignable — or was never in a response —
cannot be sent. No id is ever fabricated from a name or a position.

---

## 6. After a save

1. The write is treated as **committed**.
2. The editor is **closed out entirely** — no target, no selection, no options —
   which is what makes an ordinary retry impossible: there is nothing left to
   resubmit.
3. Safe success copy is shown **beside the roster**, with the counts as a change
   summary: *"1 shop added and 1 shop removed."* Never `added + unchanged` as a
   total; `RetailerStaffShopAssignmentChange` deliberately exposes no `total`
   getter for anyone to reach for.
4. `list_retailer_staff_members()` is re-read through
   `RetailerStaffCubit.rereadMembers()`.
5. The refreshed card's shop **names** come from that read. **No row is ever
   patched locally** — a row rebuilt from the submitted ids would state an
   assignment set this client never received, and would silently drop the hidden
   non-ACTIVE assignments the write just preserved.

An all-unchanged answer (`0 / 0 / n`) is a real, committed no-op and is reported
as a success, not a failure.

### Write succeeds, roster reread fails

Two separate facts, in that order, and never merged:

> **Shop assignments updated** — 1 shop added and 1 shop removed.
>
> **The staff list could not be refreshed** — Shop assignments were updated, but
> the latest staff details could not be refreshed, so the list below may be out
> of date.

The action offered is **Refresh staff list**, which performs the read alone. The
write is never repeated, automatically or by that button, and the editor is
already closed so an ordinary retry cannot resubmit the committed change.

---

## 7. Error classification

By SQLSTATE and exception type only. **No message text is read**, for display or
for branching — Postgres messages name tables, columns, functions and policies,
and the backend contract is explicit that message text is not an API.

| Source | Problem | What the person is told |
| --- | --- | --- |
| `42501` | `denied` | Access or membership may have changed; refresh the staff list |
| `23514` | `invalidSelection` | At least one active shop is required, and every shop must be one of your organization's active shops |
| `55000` | `retailerUnavailable` | Your organization cannot accept staff changes right now |
| `22P02` | `malformedRequest` | This version could not put the request together correctly |
| `AuthException` | `signedOut` | Sign in again |
| `http.ClientException` | `network` | **The only copy that mentions the connection** |
| `TimeoutException` | `timeout` | May or may not have been saved — refresh the staff list |
| `RpcFormatException` | `malformedResponse` | May or may not have been saved — refresh the staff list |
| anything else | `unexpected` | May or may not have been saved — refresh the staff list |

`42501` is **deliberately overloaded**: the backend raises it with byte-identical
messages for "you may not do this", "that membership does not exist" and "that
membership is another Retailer's", so the operation is not an existence oracle
for memberships. Splitting it in Dart on anything would rebuild that oracle, so
all three arrive as one problem and nothing downstream is given anything to tell
them apart with.

The last three are the **unresolved** group: the request was sent and the outcome
is genuinely unknown, so the copy says so and points at the roster instead of
re-arming the button. `network` and `signedOut` are definite — the request never
left — so a deliberate retry is safe and the editor keeps the selection.

Nothing exposes a SQLSTATE, a SQL message, a PostgREST detail or hint, a function
or table name, a UUID, a stack trace, a project URL, a token or a key. Every
user-facing string is a fixed literal in `RetailerManageStaffShopsCopy`, chosen
by a discriminant.

---

## 8. Architecture

```
lib/features/staff/
  domain/entities/retailer_staff_shop_assignment.dart      request, counts, problems
  domain/entities/retailer_staff_member.dart               + membershipId, shopIds
  domain/repositories/retailer_assignable_shops_reader.dart  the shared zero-arg read
  domain/repositories/retailer_staff_shop_assignment_repository.dart
  data/datasources/retailer_staff_shop_assignment_rpc_data_source.dart
  data/models/retailer_staff_shop_assignment_parser.dart
  data/models/retailer_staff_parsers.dart                  + strict uuid columns
  data/repositories/supabase_retailer_staff_shop_assignment_repository.dart
  presentation/retailer/cubit/retailer_manage_staff_shops_cubit.dart (+ state)
  presentation/retailer/widgets/retailer_manage_staff_shops_dialog.dart
  presentation/retailer/widgets/retailer_manage_staff_shops_copy.dart
```

### Why the roster entity now carries identifiers

The read-portal milestone deliberately dropped `membership_id` and `shop_ids`: it
was read-only, nothing was addressable, and identifiers lying around invite a
later feature to address a row from a stale list. That reasoning ended when the
write was deployed — the operation takes a membership id, and the desired set has
to start from what the backend says the person holds.

Both are bounded by that purpose: never displayed, never persisted, never typed
or derived from a name or a route, and dropped the moment the editor closes or
the session changes. They are also parsed **strictly** — a malformed or duplicate
id fails the row — where the display columns beside them are lenient, because a
dropped shop *name* is one missing chip while a dropped shop *id* silently
shortens the set the editor preselects, and saving from a short set retires an
assignment nobody chose to remove.

The two arrays are still **never paired**. The backend builds them from the same
subquery with the same ordering, so they are positionally aligned by
construction — and no code anywhere zips them, which makes a length mismatch
incapable of mislabelling anything.

### Why a third staff repository

`RetailerStaffRepository` documents that it holds **no write**, and both of its
methods are nullary reads of `STABLE` functions; adding a write would falsify
that guarantee for the roster and the invitation history too.
`RetailerStaffInvitationRepository` is about invitations, which this operation
deliberately is not: it changes an already-accepted membership, on a different
permission, with no email, token or expiry anywhere near it.

The assignable-shop read is **shared** rather than duplicated. It was extracted
into `RetailerAssignableShopsReader`, which the invitation repository implements
and which the editor consumes — one deployed contract, one Dart contract, one
registered instance. A second data source would have been a second definition of
"which shops may be assigned", free to drift and free to acquire a parameter the
deployed function does not have.

### Why a dedicated cubit

`RetailerStaffCubit` owns two reads that must survive anything this editor does.
Combining them would put a save failure in the same state object as the roster,
one `copyWith` away from clearing it. Separate cubits make it structural rather
than remembered that a Manage Shops failure cannot erase the roster, the
invitation history, the Invite Staff form, or the local search term.

---

## 9. Session isolation

`RetailerManageStaffShopsCubit.clear()` drops the selected membership, the staff
name and role, the selected shop ids, the assignable options, the write result,
every message, and the editor's visibility — and advances a request token first,
so an options read, a save, or a roster reread already in flight for the previous
identity is dropped on arrival rather than refilling an editor that has just been
emptied.

It is called from `RetailerOwnerShell`'s `_SessionIsolation` listener, which
compares an `(authUserId, organizationId)` identity rather than a boolean, so a
direct **Owner A → Owner B** switch is detected on its own terms rather than
relying on an intermediate state another bloc happens to emit today.

The token also discriminates a **change of target**: `open()` advances it, so an
answer for the previously opened colleague cannot fill the current editor.

`rosterChanged()` closes the editor when the canonical roster no longer contains
the open target — a person who left, was deactivated or was re-roled is no longer
addressable, and an editor over one would be collecting a selection with nowhere
to send it. It deliberately does nothing while a save is in flight: that write
already names the target, and its answer decides what happened.

Covered by tests: Owner A → Owner B, Owner → Manager, Owner → Vendor, Owner →
Sales Staff, authenticated → signed out, logout during a write, a role change
during the options load, and opening Staff A then Staff B.

---

## 10. Tests

| File | What it covers |
| --- | --- |
| `test/features/staff/retailer_staff_shop_assignment_parser_test.dart` | one row exactly, three non-negative integers, zero counts, missing row, multiple rows, missing fields, wrong types, negatives, additive fields |
| `test/features/staff/retailer_staff_shop_assignment_repository_test.dart` | exact RPC name, exactly two arguments, canonicalization, one call per save, no retry, `42501`/`23514`/`55000`/`22P02`, timeout, network, auth, malformed response, unexpected |
| `test/features/staff/retailer_manage_staff_shops_cubit_test.dart` | initial state, eligibility, preselection intersection, options loading and retry, toggling, duplicate prevention, empty and unchanged selections, stale-option removal, submitting state, duplicate-submit prevention, success, counts as a change summary, roster reread success and failure, definite failure, logout during a write, stale responses, target changed during load, clear |
| `test/features/staff/retailer_manage_staff_shops_flow_test.dart` | the whole screen through the real router and shells: who sees the action, preselection, multi-select, at-least-one, Save disabled while submitting, Cancel, success, refresh-failure, stale-option notice, no raw UUID, narrow and wide layouts, session isolation, Invite Staff and history regression |
| `test/security/retailer_manage_staff_shops_boundary_test.dart` | static guards — see below |
| `test/features/staff/retailer_staff_parsers_test.dart` | extended: strict `membership_id` and `shop_ids` |
| `test/security/retailer_read_portal_boundary_test.dart` | extended: exactly two identifiers on the roster entity, and neither rendered |

### Static guards

`set_retailer_staff_shop_assignments` is the only assignment write and is named
once; the request contains exactly `p_membership_id` and `p_shop_ids`; no
organization, actor, user, profile, role, permission, status, timestamp or audit
argument exists; no diff is sent; no Edge Function is invoked; no direct
`retailer_shop_members` access exists; no service-role key exists; no raw
database message is rendered; no membership or shop UUID is rendered; the
canonical roster reread occurs after a success and only there; no automatic
retry exists anywhere; and the assignable-shop RPC is still zero-argument.

---

## 11. Security boundary

- The Retailer is derived server-side from `auth.uid()`. Nothing here nominates
  a tenant, and there is no parameter to nominate one with.
- A membership id is **not** an authorization. Holding one grants nothing:
  another Retailer's id is refused byte-identically to one that names nothing.
- A shop id is not an authorization either — every submitted shop is re-validated
  against the derived Retailer.
- Hiding a button is not a boundary. The three presentation signals in §2 exist
  to avoid dead ends; the SQL is what removes the capability.
- `retailer_shop_members` grants nothing to `authenticated`, so a client-side
  write would not merely be poorly layered — it would not work.
- The audit row is written by the function, inside the same transaction. A client
  that wrote its own would be recording an event it cannot attest to.
- The presentation layer never imports `package:supabase_flutter` and never
  touches `Supabase.instance`.

---

## 12. Chrome verification

```
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

Verified as a Retailer Owner: the action appears only for active, accepted Sales
Staff; the editor preselects the current active shops; adding and removing while
keeping at least one saves; the success notice shows the change summary; the
roster re-reads and shows the updated names; a refresh confirms persistence; an
empty selection is blocked; a duplicate tap does not write twice; Cancel changes
nothing; Invite Staff and the invitation history still work; and no UUID, backend
code, crash or overflow appears.

Verified as a Retailer Manager: the roster remains visible and no Manage Shops
control exists anywhere.

Android and iOS were **not** exercised in this milestone — see §13.

---

## 13. Known limitations

1. **The ACTIVE projection is not the whole truth, and cannot be shown.** A
   member may hold assignments to suspended or deactivated shops that no contract
   returns. They are preserved by the write and invisible here, so the editor
   cannot report "this person works in N shops" and does not try to.
2. **The returned counts describe the visible replacement only.** They are used
   as a change summary and never summed into a total.
3. **A zero-shop stand-down is not available.** The backend refuses an empty
   array with `23514`, and this editor refuses it locally before anything leaves.
   Removing a Sales Staff member from every shop needs a different operation.
4. **A timeout or an unreadable answer is unresolvable from the client.** The
   roster is the only authority, which is why the copy points there rather than
   re-arming Save.
5. **`42501` cannot say which of three things happened.** The backend refuses
   with one byte-identical exception so the operation is not an existence oracle;
   restating the difference here would undo that.
6. **Concurrent edits are last-write-wins.** The function replaces the visible
   ACTIVE set with what it was sent; there is no optimistic-concurrency token on
   this contract, so two Owners editing one member simultaneously will see the
   second save win. The roster reread after each save is what makes that visible.
7. **Staff activation/deactivation, role changes, invitation acceptance,
   invitation revoke/resend and mobile deep links remain unimplemented.** See §1.
8. **Chrome-only verification.** Android and iOS were not exercised, and no APK
   was built.

---

## 14. Flutter feature matrix — Retailer portal

The canonical `docs/mobile-feature-matrix.md` lives in the backend/web
repository, which this milestone does not modify. This is the Flutter-side view.

| Capability | Web | Flutter |
| --- | --- | --- |
| Retailer Owner overview | ✅ | ✅ |
| Shops (read) | ✅ | ✅ |
| Staff roster | ✅ | ✅ |
| Invitation history | ✅ | ✅ |
| Invite staff | ✅ | ✅ |
| **Manage shops for existing staff** | ✅ | ✅ **this milestone** |
| Invitation acceptance | ✅ | ❌ web only |
| Invitation revoke / resend | ✅ | ❌ web only |
| Staff activation / deactivation | — | ❌ not implemented |
| Staff role changes | — | ❌ not implemented |
| Shop create / edit / status | ✅ | ❌ not implemented |
