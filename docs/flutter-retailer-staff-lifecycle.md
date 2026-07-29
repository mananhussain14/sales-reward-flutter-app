# Flutter — Retailer staff lifecycle (deactivate / reactivate)

The Retailer Owner control that stands a colleague down and brings them back.
**Owner-side control only**: the inactive-access diagnostic experience is a
separate milestone and is deliberately absent here — see
[What this milestone does not do](#what-this-milestone-does-not-do).

---

## 1. The deployed backend this depends on

Nothing here required a backend change. Everything below was already deployed by
`20260810090000_retailer_staff_membership_lifecycle.sql`, and this client calls
the **same** function the Next.js portal calls — no mobile twin, no second
definition of "deactivate a staff member".

```
public.set_retailer_staff_membership_status(
  p_membership_id uuid,
  p_status        text
)
returns table (
  membership_id     uuid,
  membership_status text,
  role_code         text,
  status_changed    boolean
)
language plpgsql volatile security definer set search_path = ''
```

* Granted to `authenticated` and to nothing else. **`service_role` is granted
  nothing, deliberately** — the function's whole authority is `auth.uid()`, which
  a privileged connection does not have, so the write would have no actor to
  attribute its audit row to.
* Retailer resolved by `resolve_retailer_member_organization('RETAILER_STAFF_MANAGE')`,
  which fails closed on zero **or more than one** qualifying Retailer. **No caller
  role code is named in the function** — the `role_permissions` mapping is the
  authority, and it maps that permission to `RETAILER_OWNER` alone today.
* Accepted requested statuses: **`ACTIVE`, `DEACTIVATED`**, compared exactly and
  case-sensitively. `INVITED` and `SUSPENDED` are members of the column's
  vocabulary and deliberately **not** of this operation's, in either direction.
* The write moves `status` and `deactivated_at` in one statement, under a
  `FOR UPDATE` lock, with a compare-and-set predicate and a checked row count.
* **Always exactly one returned row**, including on the no-op path.

---

## 2. Eligibility — the whole-roster rule

This is the single most important rule in the milestone.

`public.list_retailer_staff_members()` joins `member_roles` and `roles`
**without `DISTINCT`**, so a membership holding two ACTIVE roles is emitted as
**two rows sharing one `membership_id`**. This client's parser produces one
`RetailerStaffMember` per row, so those become two entities with the same id.

A per-row predicate would be wrong in the most dangerous direction:

* the `SALES_STAFF` row of a Manager+Sales member looks eligible, and the control
  would be offered for a target the RPC refuses outright — it compares the
  **complete** ACTIVE role set to a single-element array;
* worse, for a member holding `RETAILER_OWNER` **alongside** another role, the
  Owner row is excluded by the role test but the other row is not — so the Owner
  exclusion, the headline rule of this feature, would be defeated by an extra role
  assignment.

So `RetailerStaffLifecycleEligibility.eligibleMemberships` computes the set **per
membership over the whole roster**, and a membership is eligible only when:

1. it is represented by **exactly one** row — any duplicate hides the control on
   **every** occurrence, whatever the other row says; and
2. that row's role is exactly `RETAILER_MANAGER` or `SALES_STAFF`, and its status
   is exactly `ACTIVE` or `DEACTIVATED`.

Rule 1 is blind to *why* a membership appears twice. A second role, a historical
duplicate and malformed data all produce the same answer — hidden.

**It is computed from `state.members`, never `state.visibleMembers`.** The latter
is narrowed by a local search term, and a search matching only one row of a
two-role member would make that membership look unique. A widget test pins this.

Ids are trimmed and lower-cased before grouping, so two spellings of one id
cannot read as two unique memberships.

### The self-target rule

`list_retailer_staff_members()` returns **no `user_id` and no self flag**, so this
layer cannot identify the caller's own row — and nothing pretends otherwise. It
does not need to: `RETAILER_STAFF_MANAGE` is mapped to `RETAILER_OWNER` alone, so
every caller who can reach this operation is an Owner, and the role rule refuses
every Owner row including their own. The database does **not** rely on that
coincidence — it compares the target's user id to `auth.uid()` explicitly, which
is why the RPC and not this file is the authority.

---

## 3. Capability — the existing hint, no new probe

`PortalContext.capabilities.manageStaff` is used as-is. It is derived by the
backend from the same resolver this RPC gates on (`RETAILER_STAFF_MANAGE`), held
in memory only, and cleared on every identity change.

**No second permission probe was added.** One would duplicate this and be strictly
worse: this flag comes from the very resolver the write uses, whereas a client
probe would be a second question that could drift. Every capability flag defaults
to `false`, so an unreadable one fails closed.

This differs from the Vendor Retailer lifecycle milestone, where no Vendor
capability existed at all and a narrow `has_organization_permission` probe was the
only option.

---

## 4. The exact argument contract

```dart
client.rpc<Object?>(
  'set_retailer_staff_membership_status',
  params: <String, Object?>{
    'p_membership_id': membershipId,   // organization_members.id
    'p_status': status,                // 'ACTIVE' | 'DEACTIVATED'
  },
)
```

Two keys, and there is no third. The membership id is the only identifier that can
name a membership at all — one person may be staff at several Retailers, so a
profile id or an Auth user id would force the function to guess which employment
was meant.

`p_status` can only come from `RetailerStaffLifecycleStatus.code`, a two-member
enum. `INACTIVE` is not representable; `SUSPENDED` and `INVITED` are not either.

---

## 5. The response parser — stricter than Web

Accepts a body only when all seven hold:

1. exactly **one** row;
2. the row is a map;
3. `membership_id` present and a string;
4. it is a well-formed UUID;
5. **it equals the submitted id** (case-insensitive, trimmed);
6. `membership_status` is exactly `ACTIVE` or `DEACTIVATED`;
7. `status_changed` is a genuine `bool`.

`role_code` is present in the contract and **deliberately never read** — the
roster already carries the display role, and a role code has no business
travelling further. It is not a second status, so no synchronisation check
applies.

**This is deliberately stricter than the Next.js wrapper.** Its `readStatusRow`
takes `data[0]` with no length check and never compares the returned
`membership_id`. Both checks are implemented here anyway: a stricter parser can
only ever produce *more* `unconfirmed` and never a false success, and the id-echo
check is the only thing that stops one colleague's outcome being rendered under
another colleague's name.

Any failure → **`RetailerStaffLifecycleUnconfirmed`**. Never a refusal, never
"unchanged", never a retry, never exposing the returned UUID, raw data, SQLSTATE
or message. The parser never throws and never logs.

---

## 6. Outcomes, failure mapping and no-retry

| Case | Meaning | Response |
| --- | --- | --- |
| `Applied` | Committed and describable. Carries the **confirmed** status and `status_changed`. | Re-read the roster. |
| `Unconfirmed` | Committed, body untrustworthy. | Re-read. **Never** retry, never call it a failure or "unchanged". |
| `Refused` | Did not happen (four SQLSTATEs), or could not be established (timeout / unexpected). | Offer the action again. Nothing automatic. |

| SQLSTATE | Problem | Note |
| --- | --- | --- |
| `42501` | `denied` | **Eleven causes, one message.** Not signed in · lacks the permission · resolves to zero or several Retailers · target unknown / another Retailer's / **self** / **Owner** / **multi-role** / role-less / `INVITED` / `SUSPENDED`. |
| `23514` | `invalidStatus` | |
| `55000` | `retailerUnavailable` | **The acting Retailer** stopped being ACTIVE — a fact about the caller's own organization, so it is safe to word specifically. |
| `22P02` | `malformedRequest` | Mapped **locally**, not centrally — see below. |
| — | `signedOut` / `network` / `timeout` / `unexpected` | |

`22P02` is mapped in this repository rather than in the shared `mapSupabaseError`,
for the same reason the Vendor Retailer lifecycle repository maps it locally: that
mapper serves every Vendor read and the Product writes, none of which was written
or tested against this case.

`timeout` and `unexpected` are the two genuinely **unresolved** outcomes — the
write may have committed after this device stopped waiting. Both are toned as a
warning rather than an error, say so plainly, point at the roster rather than the
button, and are never retried.

**A refusal does not re-read the roster.** Nothing was written for the four
SQLSTATE members, so re-reading would spend a request to learn that; the two
unresolved members say so in their own copy and point at a manual refresh. This
matches the shop-assignment precedent.

---

## 7. Terminology

| Stored | Shown | Verb |
| --- | --- | --- |
| `ACTIVE` | Active | Deactivate |
| `DEACTIVATED` | **Inactive** | Reactivate |
| `SUSPENDED` | **Suspended** | *(no action)* |
| `INVITED` | Invited | *(no action)* |

`DEACTIVATED` reads **Inactive** because it is the state this control writes and
clears, and the word has to match the verb. The stored token stays `DEACTIVATED`
everywhere — in the column, in `p_status`, and in the audit trail.

`SUSPENDED` deliberately keeps its own word. It is an administrative state the RPC
refuses in **both** directions; rendering both as "Inactive" would put two words on
screen meaning "the button is there" and "the button can never be there".

> **This is the mirror image of the Vendor Retailer milestone, and for the same
> reason.** There, on `organizations` / `vendor_retailers`, `SUSPENDED` is the
> reversible state and reads "Inactive" while `DEACTIVATED` is terminal and reads
> "Deactivated". Here, on `organization_members`, it is `DEACTIVATED` that is
> reversible. The same stored token, two different facts, because they live in
> different tables under different operations.

The shared `SrStatusBadge` map in `core/` is untouched. `RetailerMemberStatus` is
used only inside the staff feature; the Retailer shop card uses a different enum.

Labels, verbs and the requested status all live in **one table** on
`RetailerStaffLifecycleAction`, so a button cannot read "Deactivate" while the
request asks for `ACTIVE`.

---

## 8. UI and state

Inline card action beside the existing **Manage shops** button, on the Retailer
Owner staff screen only. Card verb `Deactivate` / `Reactivate`; dialog heading and
confirm `Deactivate staff` / `Reactivate staff`; pending `Deactivating…` /
`Reactivating…`.

### Everything is keyed by membership id

The roster renders many cards at once, and each is an independent target: the
deployed function serializes on the **target row** with `FOR UPDATE`, so two
different memberships are two different rows and never contend.

`RetailerStaffLifecycleState` therefore holds **three collections**, not one
current decision:

| Field | Answers |
| --- | --- |
| `busyMembershipIds` | which rows have a request in flight |
| `problems` | which rows have an outstanding refusal |
| `notices` | which rows have a committed outcome to acknowledge |

Every question a card asks — `isBusyFor`, `problemFor`, `noticeFor` — is answered
for its own id alone, and a `BlocBuilder` per card means one request rebuilds one
card.

#### An enabled control is never silently ignored

This is the property the design exists for, and it needs **both** halves:

* `apply` refuses only a **duplicate for the same membership**
  (`if (state.isBusyFor(membershipId)) return;`);
* the card disables exactly that row (`onPressed: lifecycleBusy ? null : …`,
  where `lifecycleBusy` is `state.isBusyFor(id)`).

Because the guard and the disabled state read the same predicate, a button that is
enabled is a button whose press will always be acted on.

> An earlier iteration guarded on "any request in flight" while disabling only the
> asking row. That combination left every other button visibly enabled and quietly
> inert — a press that opened a dialog, took a confirmation, and did nothing. A
> boundary test now pins the correct guard and rejects the global form.

*(This is the one place the Vendor Retailer lifecycle pattern was deliberately not
copied: its cubit-global guard was fine for a single detail page and would be a
regression here.)*

#### Generations, and what invalidates a result

Each membership carries its own generation, bumped when a request starts; the
cubit carries one epoch, bumped by `clear()`. A result is applied only if **both**
still match on arrival.

| Event | Effect on an in-flight result |
| --- | --- |
| `clear()` (session change) | epoch bumped → **every** in-flight result dropped, no re-read |
| `rosterChanged` removes that membership | its generation bumped → that result dropped, no re-read; other rows unaffected |
| a newer `apply` for the same membership | generation bumped → the older result dropped |
| membership still present | result applied normally |

`rosterChanged` acts on **in-flight requests as well as settled outcomes**. An
earlier iteration did nothing while a request was in flight, which left the
contradiction of "drops an outcome" and "does nothing while in flight" unresolved:
the answer would arrive after the card was gone and attach itself to whichever row
took its place.

**A suppressed result triggers no canonical re-read.** For a session change there
is nothing to read for; for a departed membership the roster was *just* re-read —
that is how it departed — so a second call would learn nothing. This is stated
explicitly because it is a deliberate choice rather than an omission, and it is
tested.

### Nothing is optimistic, nothing retries

The badge changes only when a fresh `list_retailer_staff_members()` says so.
Success, no-op and unconfirmed all trigger that re-read; a refusal does not.
`rosterChanged` drops an outcome whose target has left the roster, so a notice
cannot attach itself to whichever row took its place.

The dialog is popped before the request exists, so dismissing can never abandon a
committed write.

---

## 9. What this milestone does not do

This milestone owns the Retailer-side **write** — deactivating and reactivating a
colleague's membership — and nothing about how a blocked colleague is told why.

That explanation now exists, in its own milestone, and is documented separately
in [flutter-inactive-access-diagnostic.md](./flutter-inactive-access-diagnostic.md):
`get_my_lifecycle_access_state()` is called by the access-denied screen and by
nothing else, `MEMBERSHIP_INACTIVE` / `ORGANIZATION_INACTIVE` / `PROFILE_INACTIVE`
each map to one approved sentence there, and a blocked colleague can recover
in place with **Check access again** rather than waiting for the next session
resolution.

**Nothing in this feature changed for it.** The boundary test in
`test/security/retailer_staff_lifecycle_boundary_test.dart` still asserts that no
staff source names the diagnostic RPC, carries its vocabulary or copy, or reads
its repository — the assertion was narrowed from "this does not exist anywhere"
to "this does not exist *here*", and every lifecycle-write protection in that
file is unchanged.

The division of labour is unchanged too: the diagnostic improves the
*explanation*, never the enforcement. A deactivated colleague is blocked by the
backend, which re-derives its answer from `auth.uid()` on every call, whatever
any screen says.

---

## 10. Files

**Domain (pure)**
```
domain/entities/retailer_staff_lifecycle_status.dart     closed request vocabulary
domain/entities/retailer_staff_lifecycle_action.dart     transition table + whole-roster eligibility
domain/repositories/retailer_staff_lifecycle_repository.dart  problem enum + sealed result + interface
```

**Data**
```
data/datasources/retailer_staff_lifecycle_rpc_data_source.dart
data/models/retailer_staff_lifecycle_parser.dart
data/repositories/supabase_retailer_staff_lifecycle_repository.dart
```

**Presentation**
```
presentation/retailer/cubit/retailer_staff_lifecycle_cubit.dart  (+ _state)
presentation/retailer/widgets/retailer_staff_lifecycle_copy.dart
presentation/retailer/widgets/retailer_staff_lifecycle_confirmations.dart
presentation/retailer/widgets/retailer_staff_lifecycle_notices.dart
```

The write lives behind its **own** repository interface. `RetailerStaffRepository`
documents that it holds no write; `RetailerStaffShopAssignmentRepository` is about
*which shops* an accepted member works in, on a different permission. This is about
*whether they may work at all*.

---

## 11. Session isolation

`RetailerStaffLifecycleCubit` is provided by the **Retailer Owner shell alone** —
the Manager, Sales Staff and Vendor shells have no such provider, so their widget
trees contain no staff-deactivation machinery at all. A boundary test asserts that
exactly one shell file names it.

It is cleared by `_SessionIsolation` alongside the other Owner cubits, and `clear()`
advances a request token, so a write already in flight for the previous identity is
dropped on arrival: no "now inactive" acknowledgement from a previous session can
land on the new one's roster.
