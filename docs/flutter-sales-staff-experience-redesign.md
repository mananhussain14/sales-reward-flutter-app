# Sales Staff Experience Redesign

A **presentation-only** milestone. No contract, permission, repository, parser,
cubit boundary or write path changed. Every figure on every screen still comes
from the six deployed reads the previous two milestones wired, and every refusal
still arrives as the same non-leaking discriminant it did before.

What changed is what a seller sees when they open the application.

---

## 1. The problem, in the words of the screenshots

The shipped Sales Staff experience was correct and flat:

- weak visual hierarchy — a name, a status pill and four grey chips, repeated;
- no landing experience at all: the app opened on a file picker;
- no progress visualisation, despite `get_my_campaign_target_progress()` having
  shipped;
- the primary action — submitting a receipt — was a mid-page button;
- earnings read as an administrative report rather than a record of what
  somebody earned;
- almost no motion, and no motion system to add any consistently.

---

## 2. What was NOT allowed to change, and did not

| Rule | How it is held |
| --- | --- |
| No new contract, no new argument | `sales_staff_experience_boundary_test.dart` scans the new feature for every RPC name |
| No Supabase from presentation | same file scans for the client, `.rpc(`, `.from(`, `.select(` |
| No calculation in Dart | scans for arithmetic on a coin field, `.fold(`, `.reduce(` |
| No wallet, payout or redemption | scans for the vocabulary; the one notice is *referenced*, never restated |
| No fabricated motivation | scans for streak, leaderboard, ranking, countdown, guaranteed |
| No device clock | scans for `DateTime.now` and the comparison forms |
| No new dependency | scans `pubspec.yaml` for the animation and charting packages this could have reached for |
| No migration, no Edge Function, no Web file | unchanged assertions, re-stated |

The redesign added **zero** packages. The progress ring, the count-up, the
stagger, the press feedback and the hero panel are all hand-written against
`SrMotion`.

---

## 3. One recorded deviation: the landing route

The shell landed on `/sales-staff/submit`, and the milestone asks for two things
that cannot share one screen:

1. a landing screen that answers *"what should I do next?"*, and
2. a prominent call to action that **opens** the submission flow.

A call to action cannot open the screen it is on. So a fifth destination was
added **in front of** the existing four:

**Home · Submit · History · Campaigns · Earnings**

`/sales-staff/submit` keeps its route, its cubits, its duplicate-tap guard, its
tests and its place in the bar. Nothing moved; one destination was added, and the
landing path now points at it. The primary write action is still one tap away —
it is a tab *and* the pinned call to action on the landing screen.

### The consequence for reads, stated plainly

The previous milestone deliberately left the campaign, progress and earnings
cubits unloaded on shell entry, on the grounds that *"eagerly refetching a screen
nobody is looking at would issue a request for nothing."*

Somebody is looking at them now. The Home screen renders all three, so it calls
`loadOnce` on all three from its own `initState`, and the shell's session
isolation reloads them when a new Sales Staff session settles — because the Home
element survives a user switch inside one microtask drain, and nothing else would
re-read them. Entering the shell therefore issues exactly one read of each, and
opening the Campaigns or Earnings tab afterwards issues none.

---

## 4. The motion system

Four primitives and a ring, in `lib/core/widgets/`:

| Widget | What it does | Reduced motion |
| --- | --- | --- |
| `SrEnter` | 220 ms fade + 8px rise, once on mount, optional capped stagger | renders the child directly |
| `SrCountUp` | a whole number counting to its stored value | first frame is the real number |
| `SrPressScale` | 150 ms 2% press settle, on a raw `Listener` so it never enters the gesture arena | no scale at all |
| `SrSuccessMark` | one 280 ms scale-in | the disc is simply there |
| `SrProgressRing` | one 700 ms sweep from zero, continuous or segmented | painted at its value immediately |

Two properties are asserted in `motion_system_test.dart`:

- **reduced motion removes the movement, never the state** — every primitive is
  at its settled end on the first frame;
- **nothing replays** — `SrCountUp` restarts on a *value* change and not on a
  build, so an equal Bloc state, a rotation or a theme change leaves the figure
  where it is.

Nothing loops. The only repeating animation in the product is still the skeleton
shimmer, which is removed entirely under reduced motion.

---

## 5. The progress ring, and what it refuses to claim

`SrProgressRing` takes a **display fraction** the caller has already clamped. It
performs no comparison, reads no target and decides nothing — a ring that filled
itself from two numbers would be a second definition of "reached" living in a
painter. The boundary test asserts the painter names neither `targetUnits`,
`progressUnits`, `targetReached` nor `bonusAwarded`.

`CampaignTargetProgressView` keeps every claim on the stored booleans:

- `12 of 25 units` and `48%` sit **beside** the ring, never replaced by it;
- at 30 units against a target of 25 the ring rests at full and the text still
  reads `30 of 25 units` — the drawing saturates, the facts do not;
- `Your progress` / `Team progress` decides the whole vocabulary;
- `bonus_awarded_to_me` decides the one sentence that makes a claim about money,
  and the required team wording is verbatim.

Two derived display values were added to `CampaignTargetProgress`:
`completionPercent` (the clamped ratio, rounded) and `unitsRemaining` (a
subtraction of two stored counts, floored at zero). Neither decides anything;
`targetReached` remains the database's answer and the only one.

The announcement is one utterance in visual order:

> *Your progress: 2 of 3 units, 67 percent. Target not reached yet. 1 more
> eligible unit to reach your target. …*

---

## 6. Screen by screen

### Home (new)

Composes four cubits the shell already provides and issues no request of its own.

- **Welcome** — greeting, the organization name from the **trusted session
  context**, and one encouraging line that switches to a truthful alternative
  when there is no running campaign.
- **Campaign coins** — the one brand-filled panel on the screen, the total
  counting up to its stored value, this month / rewarded sales / rewarded
  campaigns beside it, and the same wallet notice the earnings screen carries.
- **Running now** — up to three campaigns in the **backend's order**, each with
  its progress ring where the contract returned one, plus a stated cap
  ("Showing 3 of 5") so truncation never reads as the whole list.
- **Recent receipts** — two rows and a way to the rest.
- **Add receipt** — pinned above the bottom bar on a phone, in the header from
  640px up where the shell has already promoted to a rail.

There is no recommendation, no ranking and no score. `_highlight` prefers
*running* over *starting soon* and preserves the order within each; the boundary
test asserts the page names no `.sort(`, `compareTo` or `recommend`.

### Campaign list

Sections now lead with the **same tinted disc and tone** their cards' status
pills carry, a count, and a line saying what belonging to the group means for a
sale — three channels, and the tone is never a necessary one. Cards stagger in;
the grid, the skeleton, the stale banner and the partial-failure banner are
unchanged in behaviour.

### Campaign card

Identity → offer → facts. A rule-type disc (indigo bolt for per-unit, blue flag
for a target — deliberately **not** emerald, which means "target reached" on the
indicator directly below), the name, two pills, the reward sentence on its own
recessed surface, then five fact chips. The campaign maximum chip appears **only**
when `max_reward_coins` is non-null; there is no "uncapped" chip, because absence
of a cap is the ordinary case.

### Campaign detail

A hero that re-recognises the campaign from the list, the cap as its own fact, the
progress ring, a numbered **"What you need to do"** that restates the eligibility,
reward and scope rules in the order they happen on a shop floor, product rows that
lead on the name, and — for a seller only — a route to *My campaign earnings*.
The Retailer Owner passes no callback and gets no link, because
`STAFF_EARNINGS_VIEW` is mapped to `SALES_STAFF` alone.

### Submit

A four-step readout — **Choose receipt · Review image · Submit securely · Review
extracted details** — derived from the submission phase, never stored. It is a
strip and not a `Stepper`: nothing on it navigates. The closing note promises a
screen to check, not a result, so it cannot be read as "the text has been read
automatically".

### Earnings

One hero for the total (counting up, wallet notice on the panel itself), three
supporting tiles that count up, and the latest-reward date as a date. The empty
state keeps the required sentence verbatim, adds what actually has to happen —
*"Rewards appear here after an eligible sale is verified and the campaign is
evaluated. Not every receipt qualifies."* — and offers **Add receipt**. It never
promises the next receipt will earn anything.

### History

Status-toned leading disc read from the badge's single definition, staggered
entry, and an **Add receipt** action on the empty state.

---

## 7. Accessibility

- Every card is still one semantics node in visual order; the ring is a sibling
  so it keeps its own announcement.
- The ring itself is `ExcludeSemantics` — the block around it speaks.
- Status is never colour alone: a glyph, a word and a tone, everywhere.
- Section headings are marked `header: true`.
- Verified at 360×640, 390×844, 900×1000 and 1280×900, and at 200% text scale on
  the narrowest surface.
- Two shared widgets were fixed rather than worked around: `SrSectionCard`'s
  header action and `ReceiptStepsStrip`'s labels now flex instead of overflowing
  at a large text scale.

---

## 8. Tests

| File | Covers |
| --- | --- |
| `test/features/home/sales_staff_home_flow_test.dart` | 39 tests: landing, greeting, coins panel, opportunity section, every progress case, the CTA, campaign types, layout at four widths, 200% text scale, reduced motion, dark mode |
| `test/core/widgets/motion_system_test.dart` | 19 tests: the four primitives and the ring, each under reduced motion |
| `test/security/sales_staff_experience_boundary_test.dart` | 17 source-safety assertions (§ 2) |

Updated: the landing-path assertions across nine flow suites, the earnings
summary/empty-state expectations, and the campaign section-heading finder.

Full suite: **5070 passing**.

---

## 9. Known limitations

- **The count-up rebuilds its own subtree per frame** for ~650 ms after a value
  changes. It is a `Text` inside a `Semantics`, so the cost is negligible, but it
  is a rebuild rather than a repaint.
- **The stagger is capped at six items.** The seventh card in a section arrives
  with the sixth. That is deliberate — twenty campaigns at 45 ms each reads as a
  slow screen — but it is a cap, not a curve.
- **No golden tests.** The milestone forbids introducing a visual-regression
  framework without approval, so layout is defended by overflow and text-scale
  assertions rather than by pixels.
- **The receipt illustration is an icon**, not artwork. This application ships no
  asset directory and a remote illustration would be a network dependency on a
  screen that has to work on a shop floor.
