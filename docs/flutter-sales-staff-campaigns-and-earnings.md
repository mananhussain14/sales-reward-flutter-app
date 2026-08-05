# Sales Staff Current Campaigns and My Campaign Earnings

**Branch:** `feature/flutter-sales-staff-campaigns-earnings`
**Scope:** what a Sales Staff member can **sell into**, how far along a target
is, and what they have actually **earned**.
**Backend repository:** not modified. Nothing was deployed. No migration was
created or changed.

The contracts this implements are deployed migrations **30**
(`vendor_campaign_operations`, functions 23–25) and **70**
(`sales_staff_campaigns_earnings_reads`). Where this document and those
migrations differ, the migrations are right — they describe what is deployed.

---

## 1. What already existed, and what this milestone added

The Sales Staff **campaign list** and **campaign detail** screens shipped in a
previous milestone (`feat: add Flutter campaign experience`). They read the three
Migration 30 contracts and were left structurally intact.

| Area | Before | Now |
| --- | --- | --- |
| Campaign list | `list_my_staff_campaigns()` | unchanged, plus target progress |
| Campaign detail | `get_my_staff_campaign(uuid)` + products | unchanged, plus target progress, recipient scope and the snapshot / live-temporal wording |
| Target progress | absent | `get_my_campaign_target_progress()` |
| Reward history | absent | `get_my_campaign_rewards(integer, timestamptz, uuid)` |
| Earnings totals | absent | `get_my_campaign_earnings_summary()` |
| Navigation | Submit · History · Campaigns | Submit · History · Campaigns · **Earnings** |

---

## 2. The six contracts, exactly as deployed

| RPC | Parameters | Permission |
| --- | --- | --- |
| `list_my_staff_campaigns` | none | `STAFF_CAMPAIGNS_VIEW` |
| `get_my_staff_campaign` | `p_campaign_id uuid` | `STAFF_CAMPAIGNS_VIEW` |
| `list_my_staff_campaign_products` | `p_campaign_id uuid` | `STAFF_CAMPAIGNS_VIEW` |
| `get_my_campaign_rewards` | `p_limit integer`, `p_before_awarded_at timestamptz`, `p_before_reward_id uuid` | `STAFF_EARNINGS_VIEW` |
| `get_my_campaign_earnings_summary` | none | `STAFF_EARNINGS_VIEW` |
| `get_my_campaign_target_progress` | none | `STAFF_EARNINGS_VIEW` |

`get_my_staff_campaign` takes **`p_campaign_id`**, not a version id.
`campaign_id` is the authoritative identifier for navigation and for joining
progress — never the campaign **name**, which two campaigns may share.

Each RPC name is written in exactly **one** file, and a source test asserts it.

### Two permissions, two repositories

`STAFF_CAMPAIGNS_VIEW` and `STAFF_EARNINGS_VIEW` are separate in the deployed
schema — *"Seeing which campaigns are running is a different question from seeing
what you personally earned, and a future role that should see one without the
other must be expressible without a code change."*

So `StaffCampaignRepository` and `StaffEarningsRepository` are separate
interfaces over separate data sources, and a source test proves neither names the
other's functions. Widening either cannot widen the other by an edit that
type-checks.

### Nothing about the caller is ever transmitted

Not one of the six calls carries a profile, auth user, Retailer, Vendor,
organization, shop, role or permission. The only values sent are a **campaign
id** (an address), a **page size**, and a **cursor the previous page returned**.

`sales_staff_earnings_profile()` — the helper the three earnings reads resolve
through — takes no arguments at all and is owner-execute-only: execute is revoked
from `anon`, `authenticated` **and** `service_role`. A source test asserts the
name appears nowhere in this application.

---

## 3. Typed models

### Campaigns (unchanged from the previous milestone)

`StaffCampaign` → `CampaignOffer`, parsed by `CampaignParsers`.

### Earnings

| Type | Contract | Columns carried |
| --- | --- | --- |
| `CampaignRewardRecord` | `get_my_campaign_rewards` | 15 of 17 |
| `CampaignEarningsSummary` | `get_my_campaign_earnings_summary` | 7 of 7 |
| `CampaignTargetProgress` | `get_my_campaign_target_progress` | 7 of 9 |
| `CampaignRewardCursor` | — | the `(awarded_at, id)` pair, held whole |

**What is returned and deliberately not carried**

* `campaign_version_id` — on both the reward and the progress row. It addresses
  nothing this application can open, and no field exists to hold one.
* `campaign_id` on a **reward** — a reward does not navigate anywhere.

**What the contracts never return, and therefore cannot leak**

`verified_sale_id`, `campaign_sale_evaluation_id`, `cap_subject_type`,
`cap_subject_id`, `beneficiary_profile_id`, `target_bonus_awarded`,
`coins_awarded_total`, and every organization, Vendor and shop id.

`receipt_submission_id` arrives in place of the verified sale — it is unique per
verified sale, the seller submitted that receipt themselves, and Migration 69
exists specifically to keep the sale key out of a client. It is rendered
**shortened** (`ABCD1234`), never whole and never as a link: there is no
authorized Sales Staff route that opens a receipt from a reward, and adding one
would be a different feature.

### Numeric handling

Every numeric column is read through one strict reader. It accepts an `int`, and
a `num` whose value is integral — JSON has one number type and a transport may
hand back `1.0`. It refuses:

* a **string** — `int.parse` on it would launder a wrong contract into a
  plausible number;
* a fraction, an infinity or a NaN;
* anything outside the bound the deployed `CHECK` enforces —
  `units_counted` `1..5000`, `qualifying_item_count` `0..50`, `coins_uncapped`
  `0..5e12`, `configured_reward_coins` `1..1e9`, `threshold_units` `>= 1`,
  counts `>= 0`;
* **any integer above `2^53 - 1`**, on every platform. On the Dart VM a `bigint`
  fits a 64-bit `int`; on the web an `int` *is* a double and anything larger is
  silently rounded. Refusing it everywhere is what makes the two agree, and it
  costs nothing — one reward's uncapped ceiling is three orders of magnitude
  below it.

Two cross-field rules the schema also enforces are re-checked, because this is
the boundary where "not the contract this build was written against" has to be
caught: `coins_capped_to < coins_uncapped`, and `reward_coins <= coins_uncapped`.

A row that fails any of these fails the **whole page**. A history quietly short
by one reward is worse than one that honestly failed to load.

---

## 4. What the client never computes

| Value | Where it comes from |
| --- | --- |
| `reward_coins` | stored |
| `coins_uncapped` | stored |
| `coins_capped_to` | stored |
| `target_reached` | stored — **never** re-derived from progress vs target |
| `bonus_awarded_to_me` | stored — reconstructed in SQL from the caller's own `TARGET_BONUS` reward |
| totals, counts, latest date | stored |

The only arithmetic on an amount in the entire feature is
`coinsUncapped - rewardCoins`, used to *describe* a difference already on screen.
It decides nothing, and a source test asserts it is the only subtraction in the
reward model.

There is no wallet, ledger, balance, payout, redemption or withdrawal anywhere —
no such object exists in the deployed schema, and inventing one in a read would
be inventing money.

---

## 5. Current Campaigns

Two reads, joined on `campaign_id`, behind **two** cubits.

Two cubits rather than one is what makes the partial-failure rule structural: a
progress read that fails cannot blank a campaign list it does not own.

### Sections

`Running now` (`ACTIVE`) and `Starting soon` (`SCHEDULED`). The filter is applied
in SQL on the derived state; the client restates none of it, so a campaign paused
while the list is open simply disappears on the next read. There is no ended,
finished or history section for a seller, because the contract returns none.

### Progress

A `TARGET_BONUS` campaign renders an indicator; a `PER_UNIT_COINS` campaign has
no row in the progress contract and gets none — showing one a bar would invent a
goal the Vendor never set.

| `performance_scope` | Label | Explanation |
| --- | --- | --- |
| `INDIVIDUAL_STAFF` | **Your progress** | counts the seller's own eligible sales |
| `RETAILER_TEAM` | **Team progress** | *"includes eligible sales by the whole Retailer team, not only your own"* |

When the team reached the target and somebody else took the bonus, the screen
says exactly:

> Your team reached this target. The bonus for crossing it was awarded to another
> team member.

It never says the reader earned it. That distinction is the whole reason the
contract withholds the per-subject `target_bonus_awarded` flag and returns
`bonus_awarded_to_me` instead.

### Empty and failure states

| State | Copy |
| --- | --- |
| No campaigns | *No active or upcoming campaigns are available for your shop.* |
| Progress failed, campaigns loaded | *Campaign information could not be loaded. Try again.* — a banner **above** a rendered list |
| Campaigns failed outright | the shared `SrRetailerProblemView` taxonomy |

**Recorded deviation.** The milestone specified one sentence for the campaign
error state. The shared problem view is kept as the primary failure screen
instead, because Phase 9 also requires an **authorization failure** and an
**expired session** to be distinguishable, and one flat sentence cannot express
either. The specified sentence is used verbatim for the partial-failure banner,
where there was no existing pattern. No failure path renders a
`PostgrestException` message, a SQLSTATE, an RPC name, a table name or a stack
trace; a source and a widget test both assert it.

---

## 6. Campaign detail

Addressed by `campaign_id`. When the RPC returns no row the existing not-found
screen renders, and it says nothing about **why** — an unknown id, another
Retailer's campaign and one that has since been paused are one answer, and no
retry is offered because the backend will answer the same way again.

Sections, in order: status · name · description · zero-product warning · reward ·
**target progress** · how performance is measured · **who the reward goes to** ·
eligible products · schedule · stacking · where the results are.

### Product eligibility wording

| `product_eligibility_resolution` | Heading | Explanation |
| --- | --- | --- |
| `SNAPSHOT` | Published campaign product selection | This campaign uses the product selection captured when it was published. |
| `LIVE_TEMPORAL` | Eligibility checked at sale time | Final qualification depends on the product and Retailer assignment state when the sale is verified. |

Products render in the backend's own order (`product_name, product_code, id`);
nothing re-sorts them. Only `product_name`, `product_code`, `barcode` and `brand`
are shown — the four the contract returns. No price, stock, margin, category or
Vendor.

Empty product list, for a seller: *No product list is available for this
campaign.*

### No duplicated labels

`coins` and `units` are appended in exactly one helper each, so `coins coins` and
`units units` are unreachable by construction. The maximum reward is stated once,
as its own sentence. Widget tests assert all three.

---

## 7. My Campaign Earnings

### Summary

Five values, all stored, all rendered exactly: total campaign coins earned, coins
earned this month, rewarded sales, rewarded campaigns, latest reward date. A
seller with no rewards sees four zeros and *No rewards yet* — never a dash, an
error or `Unavailable`.

"This month" is the **UTC** window the backend computed and returned; the hint
under the tile names its exact bounds rather than asserting a month the device
happens to be in.

Above the tiles, once:

> These are campaign rewards earned. Wallet, payout and redemption features are
> not available yet.

That notice is the only place in the feature the words *wallet*, *payout* and
*redemption* appear. A widget test strips it out and then asserts that
*wallet*, *balance*, *redeem*, *withdraw*, *payout*, *ledger* and *credit* appear
nowhere else on the screen.

**Zero rows from the summary is not a summary of zeros.** The contract returns no
row when the caller is not an active Sales Staff member of exactly one active
Retailer holding the permission. That is rendered as the shared refusal, because
"you have earned nothing" and "this surface is not yours" are different
statements.

### Reward history

Newest first, in the backend's order. Each card shows the campaign, the rule that
paid, the scope, the coins earned, the qualifying products and units, the target
and configured bonus where the row has them, the sale and award dates, the
shortened receipt reference, and the shop where it is recorded.

When a cap bit, **both** stored amounts are shown and the difference is named:

> Reduced by the campaign maximum.

The migration keeps `coins_uncapped` beside `reward_coins` precisely so a screen
can explain the shortfall *"instead of a staff member discovering an unexplained
number"*.

Empty: *You have not earned any campaign rewards yet.*

---

## 8. Keyset pagination

| Rule | How |
| --- | --- |
| Fixed page size | `campaignRewardPageSize = 20`, a `const`. No control reads it, and the contract clamps `p_limit` to `1..100` regardless |
| No offset | The contract has no offset parameter; a source test asserts none is named |
| First request | both cursor values `null` |
| Older request | **both** `p_before_awarded_at` and `p_before_reward_id`, from the last row on screen |
| Both together, always | the pair is held in one `CampaignRewardCursor`; half a cursor is unrepresentable, and the repository additionally resets one to none |
| No duplicates | the predicate is strict `<`; the cubit also filters by reward id when appending |
| Deterministic order | `awarded_at desc, id desc`, preserved |
| One request at a time | guarded in the cubit, not only by disabling the button |
| No infinite scroll | an explicit **Load older rewards** button |
| End of list | the control disappears and the screen says the history is complete |
| A failed page | keeps every reward *and* the totals; the button stays, retryable |

Half a cursor matters: the deployed guard is
`p_before_awarded_at is null or p_before_reward_id is null or (…)`, so sending one
half returns the **first** page — which a screen appending it would render as
duplicated rows.

---

## 9. Navigation

`/sales-staff/earnings`, a fourth bottom-bar destination after Campaigns. Submit
remains the landing tab and Receipts is untouched.

**Recorded deviation on the label.** The milestone names the destination *My
campaign earnings*. The visible bottom-bar label is **Earnings**: three words
under an icon in a quarter of a phone's width either ellipsise or force every
other tab to shrink. The specified name is carried where it has room — the
screen's title, its header and its accessible announcement.

Exposed to Sales Staff alone. Each role's navigation is declared in full in its
own file; none is a filtered view of a master list, so a Vendor, Retailer Owner,
Retailer Manager or Claim Reviewer cannot inherit the entry, and the route guard
turns away a direct URL. Navigation is not authorization regardless —
`STAFF_EARNINGS_VIEW` is re-decided in SQL on all three reads.

---

## 10. Loading, errors, refresh and session isolation

| Situation | Behaviour |
| --- | --- |
| First load | skeleton, once per tab, from `initState` |
| Pull to refresh | re-reads both contracts on each screen, together |
| Refresh button | the same, and disabled while it runs |
| Retry after a campaign failure | re-reads campaigns **and** progress |
| Partial failure | each read holds its own problem; neither erases the other |
| Pagination failure | rewards and totals both survive |
| Authorization refusal | the shared non-leaking refusal, no retry |
| Expired session | its own copy — *Your session has ended* |
| Person or Retailer changes | every campaign, progress and earnings cubit is cleared by a `BlocListener`, and a request token drops any read already in flight |

---

## 11. Accessibility and small screens

* Each campaign card is one semantics node; the **progress block is a sibling**,
  not a child, so it keeps its own announcement — label, current value, target
  and state. A bare `LinearProgressIndicator` announces a percentage and says
  nothing about whose units it counts.
* Each reward card is one utterance in visual order, including the cap
  explanation.
* Status is carried by **text** as well as tone, everywhere.
* Long campaign, shop and product names wrap or ellipsise at two lines; coin
  totals soft-wrap rather than clip.
* Fact chips are a `Wrap`, so a large text scale reflows instead of overflowing.
* Every control is `SrButton` at `md` or larger — at or above the 44pt minimum.
* Tests cover a 360×640 Android phone and a 1.6× text scale on both screens.

---

## 12. Tests

| File | Covers |
| --- | --- |
| `test/features/rewards/earnings_parsers_test.dart` | the three contracts, every bound, bigint safety, boolean strictness, the tier pairing, the cap rules |
| `test/features/rewards/earnings_repository_test.dart` | exact RPC and parameter names, cursor behaviour, zero rows vs zeros, error classification, timeout |
| `test/features/rewards/earnings_cubits_test.dart` | both cubits, pagination, duplicate suppression, partial failure, session isolation |
| `test/features/rewards/earnings_flow_test.dart` | both screens through the real router and shell |
| `test/security/earnings_boundary_test.dart` | the boundary, read from the source |
| `test/features/campaigns/*` | the existing campaign suites, unchanged behaviour |

---

## 13. Manual test plan — local Supabase only

Nothing below writes to a hosted project. Do not run any of it until
`flutter analyze`, `dart format` and `flutter test` pass.

### The fixture is the Web repository's, and is not modified

`/Users/mananhussain/Projects/salesreward-admin/scripts/sales-staff-campaigns-earnings-manual-fixture.mjs`

It is safe to reuse against the same local stack, and it is the **right** thing
to reuse: it carries two receipts through the real confirm → verify → finalize →
`evaluate_receipt_campaigns()` path rather than inserting reward rows, so every
figure the Flutter screens display was produced by the deployed engine. Both
clients read the same six contracts from the same local database.

It refuses to run against anything but the local stack — it checks that
`supabase status` reports a loopback API URL, and every write goes through
`docker exec` into the local container. There is no network path to a hosted
database in it.

### 1 · Start local Supabase, from the Web repository

```bash
cd /Users/mananhussain/Projects/salesreward-admin
npx supabase start
npx supabase migration up --local
npx supabase status          # note API URL and anon key
```

### 2 · Run the existing fixture

```bash
node scripts/sales-staff-campaigns-earnings-manual-fixture.mjs
```

It prints the generated Sales Staff email, a per-run password, a colleague
account at the same Retailer, and exactly what the database returns for that
seller. Copy the credentials from the terminal — never into a file.

### 3 · Point the Flutter debug build at local Supabase

`AppConfig.validateValues` accepts a plain-`http` URL **only** when the build is
debug *and* the host is exactly `localhost`, `127.0.0.1` or `::1`. Every other
host still requires HTTPS, and a profile or release build requires it for every
host including these three — `validate()` always passes `kDebugMode`, which the
build mode fixes, so no input can reach the branch in a shipped binary. No tunnel
is needed.

Create a **separate, untracked** defines file. `dart_defines.local.json` is
covered by `.gitignore`, and the hosted `dart_defines.json` is left alone:

```bash
cd /Users/mananhussain/Projects/sale_reward
cat > dart_defines.local.json <<'JSON'
{
  "SUPABASE_URL": "http://127.0.0.1:54321",
  "SUPABASE_PUBLISHABLE_KEY": "<local anon key from `npx supabase status`>"
}
JSON
```

The local anon key is a development key printed by `supabase status`. It is not
a secret, it belongs to a throwaway local database, and it is never committed.
**No service-role key is used at any point**, and none exists anywhere in this
application.

Run against it:

```bash
flutter run -d chrome --dart-define-from-file=dart_defines.local.json
```

On **Android**, `127.0.0.1` means the handset, not the workstation. Forward the
port first, which keeps the URL loopback and needs no change to the defines
file:

```bash
adb reverse tcp:54321 tcp:54321
flutter run -d <android-device> --dart-define-from-file=dart_defines.local.json
```

`10.0.2.2` — the emulator's host alias — is deliberately **not** accepted: it is
not a loopback address, and a build carrying it is one that cannot reach anything
from a physical device.

### 4 · Sign in

Use the Sales Staff email and password the fixture printed.

### 5 · Verify

**Campaigns tab**

* *SSE Next Month Launch* under **Starting soon** with a Scheduled badge; every
  other campaign under **Running now**.
* *SSE Everyday Coins*, *SSE Capped Boost* and *SSE Shampoo Snapshot* show **no**
  progress bar.
* *SSE Personal Target* shows **Your progress** 5 of 3 and says the bonus was
  awarded to you.
* *SSE Stretch Target* shows **Your progress** 5 of 50 and *Target not reached
  yet*.
* *SSE Team Target* shows **Team progress** 9 of 8, *Target reached*, and *Your
  team reached this target. The bonus for crossing it was awarded to another team
  member.* It must **not** say you earned it.

**A campaign detail**

* *SSE Shampoo Snapshot* → **Published campaign product selection**, one product.
* *SSE Everyday Coins* → **Eligibility checked at sale time**, three products.
* No `coins coins`, no `units units`, the maximum reward stated once.

**Earnings tab**

* Total campaign coins earned **155**; coins earned this month **155**; rewarded
  sales **1**; rewarded campaigns **4**; a latest reward date.
* *SSE Capped Boost* shows 12 coins, 25 before the campaign maximum, and *Reduced
  by the campaign maximum.*
* *SSE Personal Target* shows 100 coins as a target bonus.
* The wallet notice is present; nothing says balance, redeemable or payout.
* The colleague's 150-coin *SSE Team Target* reward does **not** appear.
* With fewer than 20 rewards there is no **Load older rewards** button — the
  history is complete. To exercise pagination, sign in as the colleague and
  compare, or temporarily lower `campaignRewardPageSize` in a scratch build.

**Then sign in as the colleague** and confirm the seller's rewards are absent
from their screen.

### 6 · Clean up

```bash
cd /Users/mananhussain/Projects/salesreward-admin
node scripts/sales-staff-campaigns-earnings-manual-fixture.mjs --cleanup
```

### 7 · Restore hosted configuration

`dart_defines.json` was never touched, so there is nothing to restore — only the
local file to remove:

```bash
cd /Users/mananhussain/Projects/sale_reward
rm dart_defines.local.json
adb reverse --remove tcp:54321          # if the port was forwarded
flutter run --dart-define-from-file=dart_defines.json
```

Optionally `npx supabase stop` in the Web repository.

No secret is printed to a file, committed, or written into a tracked
configuration at any point in this procedure.
