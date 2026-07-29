# Flutter — Vendor Retailer lifecycle (deactivate / reactivate)

The Vendor Super Admin control that takes one connected Retailer out of service
and puts it back. **PR 1 of two**: this milestone is the Vendor-side write only.
The Retailer-side inactive-access experience is PR 2 and is deliberately absent
here — see [What this milestone does not do](#what-this-milestone-does-not-do).

---

## 1. The deployed backend this depends on

Nothing in this milestone required a backend change. Everything below was already
deployed by `20260811090000_vendor_retailer_lifecycle.sql` in the
`salesreward-admin` repository, and this client calls the **same** function the
Next.js portal calls — there is no mobile twin and no second definition of
"deactivate a Retailer", so the two clients cannot disagree about the
multi-Vendor refusal, about which pairs are eligible, or about what survives a
deactivation.

```
public.set_vendor_retailer_status(
  p_relationship_id uuid,
  p_status          text
)
returns table (
  relationship_id     uuid,
  retailer_status     text,
  relationship_status text,
  status_changed      boolean
)
```

* Granted to `authenticated` and to nothing else — not the anonymous role, not
  PUBLIC, and not the privileged service role.
* Gated on **`RETAILERS_MANAGE`**, mapped to `VENDOR_SUPER_ADMIN` and to nothing
  else. The `role_permissions` row is the authority; no role code is compared
  anywhere in this application.
* The acting Vendor is derived from `auth.uid()` through
  `get_vendor_super_admin_context()`. It cannot be nominated.
* Both `organizations.status` and `vendor_retailers.status` move **atomically**,
  each with a compare-and-set predicate and a checked row count, with a fixed
  lock order (`vendor_retailers` → `organizations`).

The capability probe reuses the helper every RLS policy already asks the question
with:

```
public.has_organization_permission(target_organization_id uuid,
                                   target_permission_code text) -> boolean
```

---

## 2. The canonical identifier

`p_relationship_id` is a **`vendor_retailers.id`**, and Flutter already had it:
`VendorRetailerSummary.relationshipId`, `VendorRetailerDetail.relationshipId`,
and the route `/vendor/retailers/:relationshipId`. No new address space was
introduced.

A Retailer **organization** id is deliberately not accepted anywhere on the write
path. The schema permits several Vendors to manage one Retailer, so an
organization id does not identify *whose* relationship is meant; the relationship
id names exactly one Retailer as seen by exactly one Vendor, which is what makes
the RPC's single `vendor_organization_id` predicate a complete cross-tenant
boundary.

Holding a relationship id still grants nothing: another Vendor's id matches no
row and produces the same generic `42501` an unknown id does.

---

## 3. The capability probe, and why one was needed

`get_my_portal_context()` proves the caller holds the ACTIVE
`VENDOR_SUPER_ADMIN` role in an ACTIVE `VENDOR` organization, and returns **no
Vendor permission detail** — its `capabilities` block covers the Retailer portal
only. So before this milestone the app had no way to know whether a caller held
`RETAILERS_MANAGE`.

Inferring it from the portal kind was rejected: the role→permission *mapping* is
the authority and can change without this application being rebuilt, so a screen
that inferred the capability from the role would keep offering a control the
database refuses on the day the mapping is revoked.

`VendorRetailerCapabilityCubit` therefore probes directly, once per Vendor
session. Three rules:

| Rule | Why |
| --- | --- |
| The organization id comes from `PortalContext.vendor.organizationId` | Server-derived from `auth.uid()`. Never a route, form, storage or Retailer record. The helper is hard-filtered to `auth.uid()` anyway, so a substituted id could only answer `false`. |
| Three states — `confirmed` / `denied` / `unavailable` | `denied` is a fact about the caller; `unavailable` is "we could not ask". Both hide the control, but only one is a claim. |
| `isConfirmed` is `== confirmed`, never `!= denied` | Positive equality fails **closed** when a member is added to either enum. An exclusion list would fail open. |
| Nothing is persisted or cached across sessions | The answer describes a mapping an administrator can change at any moment. `clear()` drops it on every identity change. |

**A `confirmed` permits a control to render. It is never permission to write.**
The RPC re-derives every one of these facts under its own row locks regardless.

---

## 4. The exact argument contract

```dart
client.rpc<Object?>(
  'set_vendor_retailer_status',
  params: <String, Object?>{
    'p_relationship_id': relationshipId,
    'p_status': status,     // 'ACTIVE' | 'SUSPENDED'
  },
)
```

Two keys, and there is no third. No Vendor organization id, Retailer organization
id, actor id, profile id, membership id, role code, permission code, current
status, audit action or timestamp — the function declares none of them, and the
invoker typedef makes none of them expressible.

`p_status` can only ever come from `VendorRetailerLifecycleStatus.code`, a
two-member enum. The RPC compares case-sensitively and raises `23514` for
anything outside the pair, so a lower-cased or display value would be refused —
and none is representable here in the first place.

---

## 5. The response parser

`set_vendor_retailer_status` is the first Vendor write in this application that
returns a **table** rather than `void` or a bare scalar, so it needed a parser of
its own. `parseVendorRetailerLifecycleRow` accepts a body only when all eight of
these hold:

1. exactly one row (zero and two are both drift; two would otherwise have the
   second silently discarded);
2. `relationship_id` is present and a string;
3. it is a well-formed UUID;
4. **it is the row that was addressed** — compared case-insensitively, because a
   UUID's canonical form differs only in case;
5. `retailer_status` is exactly `ACTIVE` or `SUSPENDED`;
6. `relationship_status` is too;
7. the two agree;
8. `status_changed` is a genuine `bool`, not merely truthy.

Rule 4 is the one that makes the rest worth doing: a response describing a
*different* relationship must never be rendered as this Retailer's outcome. It
would attribute another Retailer's lifecycle change to the one on screen, and no
status check could catch it.

The validated identifier is checked and then **discarded** — the screen already
holds it from its own route.

The parser never throws, never logs, and never renders any part of the response.

---

## 6. No retry, and the `unconfirmed` outcome

`VendorRetailerWriteResult` has three cases, not two:

| Case | Meaning | Safe response |
| --- | --- | --- |
| `Success` | Committed, and describable. Carries the **confirmed** status and `status_changed`. | Re-read the canonical detail. |
| `Unconfirmed` | Committed, but the body could not be trusted. | Re-read. **Never** retry, never call it a failure, never call it "unchanged". |
| `Failure` | Did not happen — every deployed refusal raises and rolls back. | Offer the action again. Nothing automatic. |

Reporting an `Unconfirmed` as a failure would tell a Vendor their change was not
saved after it had been. Reporting it as "unchanged" would claim nothing happened
when an entire Retailer may have just been deactivated. Its copy says *"The
change may have been saved. Refresh the Retailer to confirm its current status."*
and deliberately contains no "try again", "retry" or "resubmit".

There is exactly one RPC call per confirmed action. No loop, no retry helper, no
re-armed button — asserted by both the repository test and the boundary scan.

### SQLSTATE mapping

| Code | Failure | Note |
| --- | --- | --- |
| `42501` | `DeniedFailure` | One wording for an unauthenticated caller, a caller without the permission, an unknown relationship, another Vendor's, and a non-`RETAILER` target. SQL refuses all five identically. |
| `23514` | `InvalidFailure` | The requested status was not one of the two. |
| `55000` | `NotReadyFailure` | See § 9. |
| `22P02` | `InvalidFailure` | **Mapped locally**, not centrally — see below. |
| anything else | `UnavailableFailure` | Including every transport fault. |

`22P02` is mapped in `mapVendorRetailerLifecycleError` rather than in the shared
`mapSupabaseError`. **Blast radius is the reason.** The shared mapper is used by
every Vendor read (Retailers, Users, Roles, Products, Audit, Dashboard, Profile)
and by the Product writes, all of which currently fold `22P02` into
`UnavailableFailure`; several of them guard against a malformed id *before* the
request leaves the device. Moving the mapping centrally would change the copy and
the retry affordance on all of those screens for a case none of them was written
or tested against. That is a change worth making deliberately, with its own
tests, and not as a side effect of this milestone.

No `error.message` is ever read, for display or for discrimination.

---

## 7. Terminology: Active / Inactive, and why `DEACTIVATED` is not collapsed

The database stores `SUSPENDED`. The product says **Inactive**.

| Stored | Shown | Verb |
| --- | --- | --- |
| `ACTIVE` | Active | Deactivate Retailer |
| `SUSPENDED` | **Inactive** | Reactivate Retailer |
| `DEACTIVATED` | **Deactivated** | *(no action)* |

"Suspended" reads as an accusation to a Retailer that is simply paused between
contracts, and the control that writes the value is labelled Deactivate /
Reactivate — the word on screen has to match the verb that produced it. The
*stored* word stays `SUSPENDED` everywhere: in both status columns, in
`p_status`, and in the audit trail. The translation is one-way; `INACTIVE` is not
a member of the request enum and appears in no executable line of the feature.

**`SUSPENDED` and `DEACTIVATED` are deliberately not collapsed.** The web's
shared badge renders both as "Inactive", on the argument that they read the same
to a user. This build does not follow it: `SUSPENDED` is a Retailer this Vendor
can reactivate with one press, while `DEACTIVATED` is terminal, is not this
operation's to clear, and is refused by the RPC with `55000`. Rendering both as
"Inactive" would invite somebody to look for a Reactivate button that cannot
exist. This is a **known, intentional divergence from the web** and is recorded
here so it is not "fixed" by accident.

The change is scoped to `VendorRetailerStatusBadge`. The shared
`SrStatusBadge` map in `core/` is **left unchanged**: it is reachable from the
Retailer Owner overview, the Vendor user directory and the staff surfaces, whose
`SUSPENDED` values are memberships and profiles rather than Retailer lifecycle —
a different fact, on a different contract, which this milestone has not analysed
and must not silently reword.

---

## 8. UI scope: the detail screen, and nowhere else

The control lives on `/vendor/retailers/:relationshipId` only. There is no action
on the directory, the dashboard, navigation, the shop tiles or any product
screen; a boundary test asserts that the list, card, grid and filter widgets name
none of it, and that the section widget is mounted by exactly one file.

It renders nothing unless **both** hold, each expressed positively:

1. `RETAILERS_MANAGE` is `confirmed` against a settled probe;
2. the canonical pair resolves to an action — `ACTIVE`/`ACTIVE` or
   `SUSPENDED`/`SUSPENDED` and nothing else.

A mismatched pair, either row `DEACTIVATED`, an unknown or blank token, a denied
capability, an unavailable capability and a probe still in flight all render
**nothing** — not a disabled button, which would still advertise that the
operation exists.

A mismatch is worth its own note: `ACTIVE`/`SUSPENDED` (or the reverse) is a
state this operation cannot have created. Something wrote one of those rows
outside this path. The RPC refuses it with `55000` and deliberately does not
reconcile it — quietly "repairing" it would overwrite whatever the other writer
intended and erase the only evidence that a second writer exists.

### Canonical re-read

`set_vendor_retailer_status` returns four scalars describing what it did. It does
**not** return a Retailer row. So after every committed write the statuses come
from `get_vendor_retailer_detail` and from nowhere else, through
`VendorRetailerDetailCubit.refreshAfterLifecycleChange`. Nothing patches a loaded
`VendorRetailerDetail` in place and no badge is flipped ahead of that read —
which is why a failed write leaves the previous statuses untouched rather than
having to undo a guess.

The shops are **not** re-read: a lifecycle change moves two status columns and
touches no shop row, not even its `updated_at`.

A refresh that fails does not undo the write. The Retailer stays on screen, the
page says the details may be out of date, and it offers a **Reload** — never
another write.

---

## 9. Multi-Vendor non-disclosure

`55000` covers **four** causes in SQL, with one message:

* the current pair is inconsistent;
* either row is `DEACTIVATED`;
* **another Vendor still holds a live relationship with this Retailer**;
* a compare-and-set row count drifted.

They are indistinguishable on purpose. The multi-Vendor case must not disclose
that another tenant exists, so this client renders one fixed sentence —
*"This Retailer's lifecycle status cannot be changed right now."* — that names no
cause, no count and no other organization. A widget test asserts that the copy
contains none of "another Vendor", "multi", "DEACTIVATED", "mismatch",
"inconsistent" or the SQLSTATE itself.

`42501` is generic for the same reason.

---

## 10. What this milestone does not do

This milestone owns the Vendor-side **write** — deactivating and reactivating a
Retailer — and nothing about how a blocked Retailer user is told why.

That explanation now exists, in its own milestone, and is documented separately
in [flutter-inactive-access-diagnostic.md](./flutter-inactive-access-diagnostic.md):
`get_my_lifecycle_access_state()` is called by the access-denied screen and by
nothing else, and the approved copy *"This Retailer is currently inactive.
Contact the Vendor or your Retailer administrator."* lives in one copy module
there.

**Nothing in this feature changed for it.** The boundary test in
`test/security/vendor_retailer_boundary_test.dart` still asserts that no source
under `lib/features/retailers/` names the diagnostic RPC, carries its vocabulary,
or reads its repository — the assertion was narrowed from "this does not exist
anywhere" to "this does not exist *here*", and every lifecycle-write protection
in that file is unchanged.

The division of labour is unchanged too: the diagnostic improves the
*explanation*, never the enforcement. An inactive Retailer's users are blocked by
the backend, which re-derives its answer from `auth.uid()` on every call,
whatever any screen says.

---

## 11. Files

**Domain (pure)**
```
domain/entities/vendor_retailer_lifecycle_status.dart      closed request vocabulary
domain/entities/vendor_retailer_lifecycle_action.dart      the transition table
domain/entities/vendor_retailer_manage_capability.dart     three-state capability
domain/repositories/vendor_retailer_write_result.dart      Success | Unconfirmed | Failure
domain/repositories/vendor_retailer_lifecycle_repository.dart
```

**Data**
```
data/datasources/vendor_retailer_lifecycle_rpc_data_source.dart    the one write RPC
data/datasources/vendor_retailer_capability_rpc_data_source.dart   the one probe
data/models/vendor_retailer_lifecycle_parser.dart                  the eight rules
data/repositories/supabase_vendor_retailer_lifecycle_repository.dart
```

**Presentation**
```
presentation/vendor/cubit/vendor_retailer_lifecycle_notice.dart
presentation/vendor/cubit/vendor_retailer_lifecycle_cubit.dart  (+ _state)
presentation/vendor/cubit/vendor_retailer_capability_cubit.dart (+ _state)
presentation/vendor/widgets/vendor_retailer_lifecycle_copy.dart
presentation/vendor/widgets/vendor_retailer_lifecycle_confirmations.dart
presentation/vendor/widgets/vendor_retailer_lifecycle_notices.dart
presentation/vendor/widgets/vendor_retailer_lifecycle_action.dart
```

The lifecycle write lives behind its **own** repository interface rather than on
`VendorRetailerRepository`, whose contract guarantees it is read-only and whose
boundary test asserts it. That is the same split
`RetailerStaffInvitationRepository` and `RetailerStaffShopAssignmentRepository`
already use — one repository per contract, so each one's boundary test can assert
its payload vocabulary exactly.

---

## 12. Session isolation

Both new cubits are owned by `VendorShell` and cleared by its `_SessionIsolation`
listener on every identity change, alongside the fourteen that were already
there. Each `clear()` advances a monotonic request token, so an answer already in
flight for the previous person is dropped on arrival.

Two things this specifically prevents:

* a stale `confirmed` rendering the control for a caller the database has not
  been asked about — the probe is re-issued against the **new** session's own
  organization id;
* a lifecycle answer landing after a `Vendor A → Vendor B` switch and leaving a
  "Retailer deactivated" acknowledgement over a Retailer B does not manage.
