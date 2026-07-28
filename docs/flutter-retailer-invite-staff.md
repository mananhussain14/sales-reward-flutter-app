# Retailer Invite Staff

The third Retailer milestone, and the Retailer portal's **first write**. It adds
an Owner-only Invite Staff form to the existing Staff screen, backed by the
shared `send-retailer-staff-invitation` Edge Function that the Next.js portal
posts to as well.

---

## 1. Scope

| Capability | Where |
| --- | --- |
| Invite a Retailer Manager | **This milestone** — Flutter |
| Invite a Sales Staff member, with shops | **This milestone** — Flutter |
| Assignable-shop picker | **This milestone** — `list_retailer_staff_assignable_shops()` |
| Invitation history (read) | Previous milestone, re-read after a send |
| Accepting an invitation | Web portal only — see §10 |
| Resend / revoke an invitation | Web portal only |

### Not implemented, deliberately

- **Flutter invitation acceptance.** Acceptance happens by following the emailed
  link into the Next.js portal.
- **Mobile deep links.** No custom scheme, no App Links, no Universal Links, no
  link handler of any kind.
- **Post-acceptance Shop reassignment.** An accepted member's shops cannot be
  changed from here — see the backend limitation recorded in the previous
  milestone.
- **Role changes** for an existing member.
- **Staff activation / deactivation.**
- **Invitation revoke and resend controls.** A resend still *happens* — inviting
  the same address again with the same role and shops produces the `RESENT`
  outcome — but there is no dedicated Resend button in this milestone.
- **Shop writes** of any kind.

No RPC for any of those is named anywhere in `lib/`, and
`test/security/retailer_invite_staff_boundary_test.dart` asserts it.

---

## 2. The Edge Function request

```
POST send-retailer-staff-invitation
```

Called through `SupabaseClient.functions.invoke`, which carries the **caller's
own session**. That is the whole point: `auth.uid()` inside
`reserve_retailer_staff_invitation()` is the real person, the Retailer is
resolved in PostgreSQL, and every submitted shop is validated against *that*
Retailer.

The body is exactly five fields:

```jsonc
{
  "firstName": "Priya",         // trimmed, never case-folded
  "lastName":  "Raman",         // trimmed
  "email":     "priya@example.com", // trimmed and lower-cased
  "roleCode":  "SALES_STAFF",   // RETAILER_MANAGER | SALES_STAFF
  "shopIds":   ["…uuid…"]       // always present; [] for a Manager
}
```

**The function rejects an unknown top-level key rather than ignoring it.** A
sixth field would not degrade gracefully — it would break every send with
`INVALID_REQUEST`. So the encoder is a dedicated model with exactly five keys
(`retailerStaffInvitationRequestFields`), and there is no field anywhere on
`RetailerStaffInvitationRequest` for:

Retailer organization id · actor / user / profile id · membership id ·
invitation id · token · token hash · audit data · invitation state · normalized
email · expiry · permission code · privileged database key · delivery-provider
configuration.

**No privileged key exists anywhere in this application.** Three of the four
RPCs behind the function are granted to the privileged database role alone, and
the function also holds the email-provider credential; both live only in the
function's own environment. That is precisely why sending is a function call
rather than an RPC.

`shopIds` is **required even when empty**. An absent array and an empty one
would otherwise be the same request, and "I chose no shops" must not be
expressible as "I forgot the field".

---

## 3. Response version and outcomes

Every reply is exactly `{ version, outcome, code }`.

**`version` must be exactly `1`.** It is bumped only for a breaking change — a
removed field, a changed field meaning, or a repurposed outcome — so a version
this build has never seen is refused rather than read optimistically.

**`outcome` is read before `code`, always.** It answers the one question a
client must never get wrong: *might an email have been delivered?*

| Outcome | HTTP | Meaning | This app's behaviour |
| --- | --- | --- | --- |
| `SENT` | 200 | First delivery, accepted and recorded | Success notice · clear the form · re-read history |
| `RESENT` | 200 | New email sent for an existing invitation; **previous link is no longer current** | Success notice saying so · clear the form · re-read history |
| `DELIVERY_ACCEPTED_STATUS_UNCONFIRMED` | 202 | Provider accepted it; the bookkeeping write could not be confirmed | Partial-success notice · clear the form · re-read history · **never resend** |
| `DELIVERY_FAILED` | 502 | Provider did not accept it | Failure notice · **keep every entered value** · re-read history · no automatic retry |
| `NOT_SENT` | 4xx/5xx | Nothing was handed to the provider | Notice chosen from `code` · keep every entered value |

An **unrecognised `outcome`** fails the whole response — the safety-critical
question is left unanswered and both available guesses are wrong in a way that
matters. An **unrecognised `code`** degrades to
`RetailerStaffInvitationCode.unrecognized` and the screen falls back to the
outcome's generic copy, which is what the contract requires of a client meeting
a newer code. A `code` whose declared outcome contradicts the response's own
`outcome` is treated the same way; the outcome wins.

---

## 4. Stable codes, and how each is spoken

| Code | User-facing notice |
| --- | --- |
| `METHOD_NOT_ALLOWED` | "The invitation could not be sent" — a fault on our side |
| `INVALID_REQUEST` | "The invitation was refused" — check the details |
| `INVALID_ROLE_SHOP_COMBINATION` | "The role and shops do not match" |
| `AUTH_REQUIRED` | "Your session has ended" — sign in again |
| `ACCESS_DENIED` | "You cannot invite staff" |
| `INVITATION_CONFLICT` | "This person already has an invitation" |
| `RETAILER_INACTIVE` | "Your organization cannot invite staff right now" |
| `FEATURE_DISABLED` | "Invitations are switched off" |
| `NOT_CONFIGURED` | "Invitations are unavailable right now" |
| `INTERNAL_ERROR` | "The invitation could not be sent" |

Plus five transport cases the function never got to answer:

| Transport problem | Notice | Form kept? | History re-read? |
| --- | --- | --- | --- |
| `network` — request never left | "Check your connection" | yes | no |
| `signedOut` — no usable session, or a bare gateway `401` | "Your session has ended" | yes | no |
| `timeout` — sent, no answer in time | "status could not be confirmed" | no | **yes** |
| `malformed` — an answer this build could not read | "status could not be confirmed" | no | **yes** |
| `unexpected` — anything else | "status could not be confirmed" | no | **yes** |

**There is no `RATE_LIMITED` code, because there is no rate limiter in this
system.** Nothing in this app claims one exists, and a static test asserts the
copy never implies it.

Nothing here is ever built from a response. Every sentence is a fixed literal
chosen by a discriminant, so an HTTP body, a PostgREST message, a SQLSTATE, a
provider reply, a stack trace, an invitation id, a raw token, a token hash, an
accept link or any Supabase project detail cannot reach a screen.

---

## 5. Manager versus Sales Staff shop rules

| | Retailer Manager | Sales Staff |
| --- | --- | --- |
| Shop picker shown | no | yes |
| Shops submitted | **always `[]`** | at least one |
| Assignable-shops RPC called | never | on first switch to this role |

The two rules are enforced structurally rather than remembered:

- `RetailerInviteStaffState.submittableShopIds` returns `[]` whenever the role
  does not carry shops, so a stale tick cannot ride along on a Manager
  invitation;
- for Sales Staff it **intersects the selection with the options the backend
  returned**, so an id that is no longer assignable — or was never in a response
  at all — cannot be sent;
- `RetailerStaffInvitationRequest.validated` refuses to *build* a Manager
  request that carries a shop, and a Sales Staff request that carries none.

A tick survives a switch to Manager and back, because the estate belongs to the
Retailer rather than to the role. It is simply never submittable meanwhile.

---

## 6. The assignable-Shops RPC

```
list_retailer_staff_assignable_shops() → shop_id, shop_name, shop_code, city
```

**Zero arguments.** No Retailer id, organization id, relationship id or
membership id is passed, because the deployed function has no parameter for one:
the Retailer is derived inside the function from `auth.uid()`.

This is the **one Retailer read in the application whose rows carry an id**, and
the migration says why in as many words: shop ids exist here so they can be
passed straight back to the reservation. So the id is bounded by that purpose —
never displayed, never persisted, never typed or derived from a name, and
travelling to exactly one place.

- **A refusal raises `42501`**, which arrives as `RetailerReadProblem.denied`. It
  is never rendered as an empty picker: "you may not see this" and "your Retailer
  has no active shops" are opposite claims, and the migration raises rather than
  returning nothing precisely so the two stay distinguishable.
- **Only ACTIVE shops exist on this contract.** The function filters
  `status = 'ACTIVE'` itself, matching what the reservation accepts, so there is
  no status column and no client-side status filter. A suspended shop is not
  "shown as unavailable" — it is absent.
- **`shop_code` and `city` are nullable**; an absent one is omitted, never
  rendered as a placeholder.
- **A malformed or duplicated `shop_id` fails the whole read.** Everywhere else
  an odd value would only be displayed; here it would become an element of
  `shopIds`.
- The list loads on the first switch to Sales Staff. A **successful** list
  survives every later role switch; a **failed** one is retried on the next
  switch back, because that answer can change.
- Picker states: loading · ready · empty · denied · other failure with a retry ·
  malformed (reported as unreadable, never as a connection problem).

---

## 7. Partial-success semantics

`DELIVERY_ACCEPTED_STATUS_UNCONFIRMED` arrives with **HTTP 202 — a success
status**, deliberately, so that no HTTP library, proxy or retry policy
resubmits the write on its own.

The invitation is still acceptable: the token hash and the expiry were stored
before the email went out, and neither the recipient lookup nor the acceptance
path reads `sent_at`. What is unconfirmed is the bookkeeping, not the
recipient's ability to accept.

The copy says, near-verbatim:

> The email may have been sent, but the latest invitation status could not be
> confirmed. Refresh the invitation history before trying again.

**The write is never repeated automatically.** Repeating it re-reserves, mints a
new token and rotates the hash — killing a link that may already be in the
recipient's inbox and sending a second email.

**The form is emptied** on this outcome, and on the three other unresolved ones
(timeout, unreadable answer, unexpected fault). That follows the project's
existing convention for an unconfirmed write — the unconfirmed product create
removes the submit affordance rather than re-arming it — and an empty form
cannot be resubmitted. A **definite** failure does the opposite and keeps every
value, so a deliberate retry costs no retyping.

---

## 8. Canonical invitation-history re-read

**The send's response carries no invitation record.** A returned row would be a
second invitation shape free to drift from the one
`list_retailer_staff_invitations()` returns. So nothing is appended locally: a
row assembled from the form would state a `derived_state`, an `expires_at` and a
`sent_at` this client never received.

`RetailerStaffCubit.rereadInvitations()` re-reads the canonical history and
returns whether it landed. The roster is left alone — sending an invitation
creates no membership.

The history is re-read whenever the message may have reached the provider
(`SENT`, `RESENT`, the 202, **and** `DELIVERY_FAILED`, whose recorded failure is
itself a row on the history) and whenever the outcome is unresolved.

If the send succeeded but the re-read failed:

- the send is **never** restated as a failure;
- the previous invitation rows stay on screen;
- a second notice says the history could not be reloaded;
- the action offered is a **read** — "Refresh invitation history" — never
  another send.

---

## 9. Session isolation

The Retailer Owner shell's `_SessionIsolation` listener calls
`RetailerInviteStaffCubit.clear()` on every identity change, alongside the three
read cubits. `clear()` drops:

typed names and email · the chosen role · the ticked shops · the
assignable-shop options · the submission result · every field message and
notice — and advances a request token, so a shop read, an invitation send or a
history re-read already in flight for the previous identity is **dropped on
arrival**.

It also advances `formRevision`, which is what makes the text controllers in the
widget follow: cleared in state but still on screen would leave the previous
session's colleague's name and address visible.

Covered by tests: Owner A → Owner B · Owner → Manager · Owner → Vendor ·
Owner → Sales Staff · authenticated → signed out · logout while a submission is
pending.

**No write result from a previous session can affect the new session.**

---

## 10. Chrome verification, and the localhost `APP_ORIGIN` limitation

Verified in Chrome only, per the milestone's instruction:

```bash
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

No APK was built, no emulator was launched, no device was used, and `adb` was
not run.

**The hosted backend is configured with `APP_ORIGIN=http://localhost:3000`.**
Every invitation link therefore points at the locally-run Next.js portal. That
is a backend deployment setting and is **not** changed from Flutter. A recipient
opening an invitation on a device that is not running the local portal will not
reach an acceptance page.

---

## 11. Owner-only, and why that is not authorization

`RetailerInviteStaffCubit` is provided **only** in the Retailer Owner shell, so
a Manager's widget tree contains no invitation-sending machinery at all. The
form renders when `RetailerStaffCubit.includeInvitations` is true — the same
flag the invitation history already used, set once at construction by the shell.

That is **presentation scope, never authorization**. The backend decides, twice,
on every call: the Edge Function re-applies the whole request contract, and
`reserve_retailer_staff_invitation()` re-derives the Retailer from `auth.uid()`,
re-checks the permission, and locks and validates every submitted shop. A hidden
form removes the accident; only those checks remove the capability.

---

## 12. Architecture

```
domain/entities/    retailer_staff_invitation_role.dart      role + wire token
                    retailer_staff_invitation_request.dart   the 5 fields + validation
                    retailer_staff_invitation_outcome.dart   version, outcomes, codes
                    retailer_assignable_shop.dart            picker row (the one id)
domain/repositories/retailer_staff_invitation_repository.dart interface + results

data/datasources/   retailer_staff_invitation_rpc_data_source.dart  RPC + function names
data/models/        retailer_staff_invitation_request_body.dart     the 5-key encoder
                    retailer_assignable_shop_parser.dart            strict row parser
                    retailer_staff_invitation_response_parser.dart  strict reply parser
data/repositories/  supabase_retailer_staff_invitation_repository.dart

presentation/retailer/cubit/   retailer_invite_staff_cubit.dart + _state.dart
presentation/retailer/widgets/ retailer_invite_staff_form.dart, _copy.dart
```

Raw maps stay in the data layer: `RetailerStaffInvitationReply` is the only type
that holds a body, and a static test asserts it never appears outside `data/`.
No widget or cubit touches `Supabase.instance`.

The existing read-only `RetailerStaffRepository` was **not** widened. Its
documentation guarantees it holds no write, and both of its methods are nullary
reads of `STABLE` functions; bolting a send onto it would falsify that for the
roster and history too. The invitation contracts get their own interface in the
same feature.

---

## 13. Known limitations

1. **Invitation links open `http://localhost:3000`.** A backend deployment
   setting; see §10.
2. **No resend or revoke control.** Re-inviting the same address with the same
   role and shops produces `RESENT`, but there is no dedicated button, and a
   revoke still requires the web portal.
3. **`INVITATION_CONFLICT` cannot say what differs.** The backend refuses with
   one byte-identical exception so an invitation cannot be used to probe who
   exists; restating the difference here would undo that.
4. **A timeout is unresolvable from the client.** The invitation history is the
   only authority, which is why the copy points there.
5. **Post-acceptance shop assignment remains unreachable** from any client — the
   backend limitation recorded in the previous milestone still stands.
6. **The Owner sees no confirmation of *which* shops were attached** until the
   history re-read lands, because the send response carries no invitation record
   and nothing is assembled locally.
7. **Chrome-only verification.** Android and iOS were not exercised in this
   milestone.
