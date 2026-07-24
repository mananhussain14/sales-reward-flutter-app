# Flutter Application Foundation — SalesReward

The mobile application's shared foundation and its four role experiences.

This milestone builds **no business feature**. It establishes the design tokens,
the light and dark themes, the design system, the four role shells, the
role-isolated route groups, the shared state widgets, and the tests that hold all
of it in place.

---

## 1. Authoritative web source

| | |
| --- | --- |
| **Repository** | `salesreward-admin` (Next.js 16.2.10 + Supabase) |
| **Branch** | `main` |
| **Commit** | `3326cc4a78abc6b0d72c31f1e6771f82468fcf94` |
| **Short** | `3326cc4` — *docs: add Flutter design and role flow handoff* |
| **Working tree** | Clean at time of reading |
| **Read on** | 2026-07-24 |

### Documents consulted — all five present

| Document | Lines |
| --- | --- |
| `docs/mobile-backend-contract.md` | 1310 |
| `docs/mobile-feature-matrix.md` | 184 |
| `docs/mobile-architecture-recommendation.md` | 635 |
| `docs/mobile-ui-design-handoff.md` | 1163 |
| `docs/mobile-role-flow-map.md` | 580 |

The two design documents each record their own *backend* audit commit as
`510331e` — the commit whose source they read. They were committed at `3326cc4`,
which is the version this repository is written against.

Nothing in the web repository was modified, committed, pulled, merged or pushed.

---

## 2. Deviations from the handoff

Three places where this repository knowingly differs from the authoritative
documents. Each is a product instruction that post-dates the handoff, and each is
recorded here rather than left to be discovered.

### 2.1 Dark mode ships — the handoff says light only

§ 0 and the § 7 checklist of the design handoff are unambiguous:

> **Flutter: ship light theme only for this milestone.** Set `ThemeMode.light`
> explicitly rather than `ThemeMode.system`. Do not author a dark `ColorScheme`
> "for later" — the web has no dark palette to copy, so any dark theme would be
> invented, which is exactly what this handoff exists to prevent.

The mobile product requirement is light, dark **and** system, with
`ThemeMode.system` as the default. That requirement wins, and both themes ship.

The handoff's underlying concern is legitimate: an invented dark theme becomes a
second visual identity. It is answered by construction rather than by assertion —
see § 6.2. In short: every dark value is another step of the *same* Tailwind v4
family as its light counterpart, no new hue is introduced, and every text pair is
contrast-audited by a test.

**This should be reconciled with the web team.** If the web ever grows a dark
palette, `SrColorScheme.dark` is the one file to align.

### 2.2 Material icons — the handoff says port the 38-icon set

§ 2.10 says *"do not use Material Icons"* and asks for the web's 38 stroked paths
at weight 1.75. The product instruction for this milestone is to use Flutter's
built-in Material icons and add no icon package or asset.

Material icons ship. The full requirement, the 38 names, and the exact
substitution table are recorded in
[`docs/required-design-assets.md`](./required-design-assets.md) so the swap is
mechanical later. Accepted cost: icon-dense surfaces read slightly bolder than
the web.

### 2.3 Sales Staff gets two tabs — the handoff says no navigation chrome

§ 4.1 of the handoff and § 6 of the role-flow map both count Sales Staff as
**one** destination and recommend no navigation chrome at all, because a
single-tab bar is noise. The product instruction is a concise bottom navigation
with the receipt action immediately visible.

This ships **Submit · History**, for two reasons:

1. The web's single Receipts page is already two things — § 5.11 describes a
   "Submit a receipt" card stacked above a "Your submissions" history card.
   Splitting one long scroll into two tabs is the ordinary mobile transformation
   of that page, and `mobile-architecture-recommendation.md` § 4.2 independently
   proposed exactly that.
2. It keeps the primary write action one tap away, never scrolled out of reach
   behind a history list.

Two entries is the same count the role-flow map already accepts as a bottom bar
for the Retailer Manager. This resolves decision **D-4** for this role.

---

## 3. Clean Architecture structure

```
lib/
├── main.dart
├── app/                                  composition root
│   ├── app.dart                          owns RoleSessionBloc, ThemeCubit, router
│   ├── bootstrap.dart                    Supabase.initialize + DI + runApp
│   ├── config/app_config.dart            the ONLY reader of a --dart-define
│   ├── di/injector.dart                  get_it registration
│   ├── theme/
│   │   ├── app_theme.dart                one builder → AppTheme.light / .dark
│   │   └── cubit/theme_cubit.dart        system | light | dark
│   ├── navigation/
│   │   ├── role_destination.dart         RoleDestination, RoleShellChrome, RoleNavigation
│   │   └── role_navigation_registry.dart role → model lookup (never a filter)
│   ├── router/
│   │   ├── app_routes.dart               the two role-neutral routes
│   │   ├── app_router.dart               four route groups + the pure guard
│   │   └── router_refresh.dart           BLoC stream → GoRouter.refreshListenable
│   └── shells/
│       ├── base/
│       │   ├── role_shell_bloc.dart      shared navigation mechanics (abstract)
│       │   ├── role_shell_scaffold.dart  shared chrome: drawer / bar / rail
│       │   ├── account_sheet.dart        D-5 account sheet + theme selector
│       │   └── placeholder_destination_page.dart
│       ├── vendor/            {navigation, shell}.dart + bloc/
│       ├── retailer_owner/    …
│       ├── retailer_manager/  …
│       └── sales_staff/       …
│
├── core/                                 shared, role-neutral
│   ├── design/
│   │   ├── sr_palette.dart               raw Tailwind v4 steps + brand literals
│   │   ├── sr_color_scheme.dart          semantic layer, ThemeExtension, light + dark
│   │   ├── sr_typography.dart            the type scale — colour-free
│   │   ├── sr_spacing.dart               SrSpacing + SrRadii
│   │   ├── sr_motion.dart                durations, curves, reduced-motion check
│   │   └── design.dart                   barrel
│   ├── errors/
│   │   ├── sql_state.dart                42501 / 23505 / 23514 / 55000
│   │   ├── failure.dart                  the sealed Failure union
│   │   ├── failure_mapper.dart           the ONLY inspector of a backend error
│   │   └── errors.dart                   barrel
│   └── widgets/                          the design system (13 files)
│
└── features/                             organised by business feature
    ├── auth/
    │   ├── domain/entities/app_role.dart
    │   ├── domain/repositories/portal_context_repository.dart
    │   ├── data/repositories/unimplemented_portal_context_repository.dart
    │   └── presentation/{bloc,pages}/
    ├── dashboard/presentation/{vendor,retailer_owner}/pages/
    ├── staff/presentation/retailer_manager/pages/
    └── receipts/presentation/sales_staff/pages/
```

64 Dart files in `lib`, 12 test files.

---

## 4. Shared versus role-specific

The rule, from § 0 of the role-flow map:

| Layer | Sharing rule |
| --- | --- |
| Domain entities | Shared when they represent the same business data |
| Repository contracts | Shared when they represent the same business data |
| Data sources | Shared when they call the same backend contract |
| **Presentation** | **Separate** when role behaviour differs |
| **Navigation** | **Separate** when role behaviour differs |
| **BLoCs / state** | **Separate** when role behaviour differs |

### Shared

Supabase initialization · configuration · DI · the `Failure` union and
`mapSupabaseError` · all design tokens · the design system · both themes ·
`AppRole` and `ResolvedRole` · the role-resolution contract · `RoleSessionBloc` ·
the shell chrome widget · the route guard · the access-denied surface.

### Role-specific — sharing nothing

| | Vendor Super Admin | Retailer Owner | Retailer Manager | Sales Staff |
| --- | --- | --- | --- | --- |
| Prefix | `/vendor` | `/retailer-owner` | `/retailer-manager` | `/sales-staff` |
| Portal name | Vendor Admin | Retailer Portal | Retailer Portal | Retailer Portal |
| Navigation | `vendor_navigation.dart` | `retailer_owner_…` | `retailer_manager_…` | `sales_staff_…` |
| Shell | `VendorShell` | `RetailerOwnerShell` | `RetailerManagerShell` | `SalesStaffShell` |
| Shell BLoC | `VendorShellBloc` | `RetailerOwnerShellBloc` | `RetailerManagerShellBloc` | `SalesStaffShellBloc` |
| Chrome | Drawer | Bottom bar / rail | Bottom bar / rail | Bottom bar / rail |
| Landing | `/vendor/dashboard` | `/retailer-owner/overview` | `/retailer-manager/staff` | `/sales-staff/submit` |

### What is deliberately not done

- **No dashboard with role checks.** There is no `if (role == …)` in any shell,
  page or chrome widget — asserted by a test.
- **No single BLoC holding four workflows.** `RoleSessionBloc` is shared because
  the question it answers is role-*neutral*, not because sharing was convenient.
- **No filtered master navigation list.** Each role's destinations are declared
  in full in their own file. Tests assert that no two roles share a
  `RoleDestination` *instance* or a list instance. The web's own reason, from
  `retailer-nav-items.tsx`: *two lists that share nothing cannot leak into each
  other.*
- **No duplicated domain entities.** `AppRole` and the failure union are declared
  once.

---

## 5. BLoC ownership

| BLoC / Cubit | Scope | Owns | Provided by |
| --- | --- | --- | --- |
| `RoleSessionBloc` | Application | Role resolution, provenance, preview selection, clearing | `SaleRewardApp` |
| `ThemeCubit` | Application | light / dark / system | `SaleRewardApp` |
| `VendorShellBloc` | Vendor shell | Active Vendor destination | `VendorShell` |
| `RetailerOwnerShellBloc` | Owner shell | Active Owner destination | `RetailerOwnerShell` |
| `RetailerManagerShellBloc` | Manager shell | Active Manager destination | `RetailerManagerShell` |
| `SalesStaffShellBloc` | Sales Staff shell | Active Sales Staff destination | `SalesStaffShell` |

**Why one shared session BLoC.** "Which experience is this caller in?" is
role-neutral, asked once per session, and re-asked on resume. Every role needs
the same answer.

**Why four shell BLoCs and not one parameterised instance.** The mechanics are
written once in the abstract `RoleShellBloc`; the four concrete subclasses exist
so the *type system* prevents one role's shell from receiving another role's
state object. Each is also the obvious home for behaviour that diverges later — a
Sales Staff offline-queue badge, a Vendor pending-approval count — without any of
them growing a `switch (role)`.

**Why `ThemeCubit` is a Cubit.** Its entire state is one enum with three values
and one transition. A Bloc would add an event class and a handler for no
additional clarity. Every state holder with meaningful events stays a Bloc.

**States are unions, not nullables.** `RoleSessionState` is six-way — initial,
resolving, active, no-access, failed. Collapsing "resolving", "no role",
"refused" and "backend unreachable" into one falsy value is the mistake the web
layer avoids, and the role-flow map is explicit that an outage must never render
as a denial.

---

## 6. Themes

### 6.1 Structure

`AppTheme.light` and `AppTheme.dark` call **one private builder** with a
different `SrColorScheme`. Nothing structural differs between them — radii,
typography, component shapes and motion are identical, asserted by a test. Only
colour resolves differently, and it resolves in one place.

Colour reaches widgets through a `ThemeExtension`:

```dart
final SrColorScheme sr = context.sr;   // falls back to light, never throws
```

Material's own `ColorScheme` cannot express this product — it has no slot for the
hairline every card shares, the nav active rail, the skeleton shimmer, or six
status tones each with a fill, foreground, ring, border and disc.

`SrTypography` carries **no colour at all** (asserted by a test): a baked-in
colour makes a style un-themeable.

### 6.2 The palette is Tailwind v4, and that is a correction

The previous iteration of this repository used Tailwind **v3** hexes throughout.
§ 2.1 of the handoff records that the web is on Tailwind v4, whose palette is
defined in OKLCH and resolves to different sRGB values:

| Token | v3 (was wrong) | v4 (ships) |
| --- | --- | --- |
| `slate-300` | `#CBD5E1` | `#CAD5E2` |
| `slate-400` | `#94A3B8` | `#90A1B9` |
| `slate-500` | `#64748B` | `#62748E` |
| `slate-600` | `#475569` | `#45556C` |
| `slate-900` | `#0F172A` | `#0F172B` |
| `indigo-600` | `#4F46E5` | `#4F39F6` |
| `indigo-700` | `#4338CA` | `#432DD7` |
| `violet-600` | `#7C3AED` | `#7F22FE` |
| `emerald-700` | `#047857` | `#007A55` |
| `amber-700` | `#B45309` | `#BB4D00` |
| `red-700` | `#B91C1C` | `#C10007` |

One documented exception, decision **D-1**: the brand mark's inline SVG carries
v3-era literals that the web never migrated. They live in `SrBrandLiterals`, are
used by the mark alone, and are theme-independent — so the mark is pixel-identical
to the web while the interface uses the steps that actually ship.

### 6.3 Other corrections from the handoff

| Was | Now | Source |
| --- | --- | --- |
| Dark drawer on `--surface-nav` | **White** drawer, 256 wide, hairline border | § 2.3 — the property is declared but never applied; *"do not build a dark drawer from it"* |
| `shadow-sm` at v3 values | v4: `0 1px 3px rgb(0 0 0/.1), 0 1px 2px -1px rgb(0 0 0/.1)` | § 2.7 |
| Content max width 720 | `max-w-6xl` = 1152 | § 2.9 |
| Spinner as the loading state | **Skeletons** | § 3.11 — *"skeletons, not spinners, are the product's loading language"* |
| No inline alert component | `SrAlert`, four tones | § 3.8–3.9 — the product has no snackbars |
| Disabled colours muted per-property | Whole-control `Opacity(0.6)` / `0.7` + muted fill | § 2.6 |
| Vendor nav without "Soon" entries | Six active + six "Soon" pills | § 4.1, role-flow § 3 |
| Empty-state disc→title gap 16 | 24 | § 3.12 |
| App bar carrying the brand lockup | Portal title + identity avatar; lockup moves to the drawer header | § 3.19 |

### 6.4 How dark was derived

Three rules, all enforced by tests:

1. **Same hue families.** Every dark value is another step of the same Tailwind
   v4 family its light counterpart came from. No new hue is introduced.
2. **Lightness is re-mapped, not flipped.** Surfaces descend (white → slate-900,
   page → slate-950) while type ascends (slate-900 → slate-50). Saturated brand
   and status hues move to the lighter 300/400 steps so they stay legible on a
   dark field. A literal inversion would turn indigo into a muddy yellow-green
   and destroy the brand.
3. **Contrast is verified.** `test/support/contrast.dart` implements the WCAG
   relative-luminance and contrast-ratio formulas, and the theme test asserts
   AA (≥ 4.5:1) for every text pair.

Selected pairs:

| Pair | Ratio |
| --- | --- |
| `foreground` on `background` | ~18.4 : 1 |
| `textBody` on `surface` | ~12.1 : 1 |
| `textMuted` on `surface` | ~6.9 : 1 |
| `onBrand` on `brand` (indigo-500) | ~4.7 : 1 |
| emerald-300 on emerald-950 | ~9.9 : 1 |
| amber-300 on amber-950 | ~10.4 : 1 |
| red-300 on red-950 | ~8.5 : 1 |
| `navActiveLabel` on `navActiveFill` | ~8.0 : 1 |

Two deliberate re-mappings rather than step-for-step ports:

- **`secondary`** is a near-black solid in light (`slate-900`). On dark it becomes
  a near-white solid (`slate-100`) — the same role at the opposite end of the same
  slate ramp, because a near-black button on a near-black page is invisible.
- **`brand`** is `indigo-600` in light and `indigo-500` in dark: a brand fill needs
  to separate from a very dark field, and white on indigo-500 still clears AA.

**Known inherited issue.** In *light*, `textMuted` (slate-400) on white is
≈2.6:1, below AA. That is what the web ships today for placeholders, stat hints
and footers. Fidelity was chosen over a unilateral fix; it is worth raising with
the web team, and the dark theme does not repeat it.

### 6.5 Theme mode

`ThemeCubit` holds `system` (default) / `light` / `dark`, surfaced as a
three-option control in the account sheet.

**The selection is not persisted, on purpose.** `ThemeMode.system` is the default,
so a fresh install already follows the device — which is what most users want and
never configure. Storing an override would mean adding a persistence package for
a single enum, and this milestone is meant to stay lightweight. The honest
consequence: an explicit override lasts the session and resets to system on
relaunch. When a preferences store arrives for something that genuinely needs
one, the Cubit is one `emit` away from reading and writing through it.

---

## 7. Design-system mapping

Nothing was ported from React or Tailwind as code. Every value was read from the
handoff and re-expressed in Dart, with the source section recorded in the file.

| Web component | Dart widget | § |
| --- | --- | --- |
| `button.tsx` | `SrButton` — 5 variants × 3 sizes, built-in spinner + label swap | 3.1 |
| `field.tsx` | `SrTextField`, `SrField` — label above, message **below** the control | 3.2 |
| `card.tsx` | `SrCard`, `SrSectionCard`, `SrIconDisc` — 4 variants | 3.5 |
| `badge.tsx` | `SrBadge`, `SrStatusBadge` — the full enum map + `Unknown` | 3.6 |
| `alert.tsx` | `SrAlert` — 4 tones, icon + text, never colour alone | 3.9 |
| `skeleton.tsx` | `SrSkeleton`, `…PageHeader`, `…Card`, `…StatGrid`, `…List`, `SrSkeletonScreen` | 3.11 |
| `empty-state.tsx` | `SrEmptyState` — dashed border, tinted disc | 3.12 |
| `page-header.tsx` | `SrPageHeader`, `SrSectionHeader`, `SrPageBody` | 3.16 |
| `access-denied-card.tsx` | `SrAccessDeniedView` — fixed, role-neutral copy | 3.17 |
| `admin/stat-card.tsx` | `SrStatCard` — `null` → "Unavailable", never `0` | 3.5 |
| `brand.tsx` | `SrBrandMark`, `SrBrandLockup`, `SrInitialsAvatar` | 1, 3.19 |
| Vendor dashboard grids | `SrCardGrid`, `SrShortcutCard` | 4.5 |
| Route progress bar | `SrRouteProgressBar` — static under reduced motion | 3.10 |

### Type scale

| Web | Dart | Size / line-height / weight |
| --- | --- | --- |
| `text-2xl` semibold tracking-tight | `pageTitle` | 24 / 1.333 / 600, ls −0.6 |
| `text-xl` | `screenTitle` | 20 / 1.4 / 600 |
| `text-lg` | `sectionTitle` | 18 / 1.556 / 600 |
| `text-base` semibold | `cardTitle` | 16 / 1.5 / 600 |
| `text-3xl` tabular | `statValue` | 30 / 1.2 / 600 |
| `text-lg` medium | `statUnavailable` | 18 / 1.556 / 500 |
| `text-sm` | `body` | 14 / 1.4286 / 400 |
| `text-sm` medium | `label` | 14 / 1.4286 / 500 |
| `text-xs` | `caption` | 12 / 1.333 / 400 |
| `text-xs` semibold uppercase | `eyebrow` | 12 / 1.333 / 600, ls +0.3 |

### Honesty rules preserved

These are security and accessibility decisions the web made deliberately, and the
handoff warns they are cheap to lose in a port. Each is asserted by a test:

- An unknown count renders **"Unavailable"**, never `0` or `—`.
- An unrecognised status enum renders **"Unknown"**, never the raw value — and a
  `NULL` `derived_state` falls into the same branch rather than crashing.
- "Could not load" copy is **reason-free**: no exception text, no Postgres code.
- A denial never reads as "not found"; an outage never reads as a denial.
- The access-denied screen names no role, organization or failing condition.
- Meaning is never carried by colour alone — every status pairs a hue with a
  label, and the active nav item gets a rail as well as a tint.
- A loading label is generic and names no record.

### Desktop → mobile

| Desktop | Mobile |
| --- | --- |
| White 256px sidebar, 12 entries | Drawer on the same surface, same items, same "Soon" pills; permanent panel ≥1024 |
| White sidebar, 2–4 entries | Bottom bar <640; navigation rail ≥640 |
| Data tables | Card lists — nothing scrolls horizontally |
| Two-column forms | Vertical stacks; label→control→message order unchanged |
| No dialogs (one `window.confirm`) | Material dialog at the surface radius; bottom sheets for pickers |
| Dashboard grids | One column on a phone, two from 520px — cards never shrunk |
| Hover lift | Press state at 150ms |
| Sticky 85%-blur app bar | Opaque 64px bar with a hairline (see § 9) |

---

## 8. Responsive navigation

| Role | Phone | ≥ 640 | ≥ 1024 |
| --- | --- | --- | --- |
| **Vendor Super Admin** (6 + 6 Soon) | Drawer behind a hamburger | Drawer | Permanent side panel |
| **Retailer Owner** (4) | Bottom bar | Navigation rail | Rail |
| **Retailer Manager** (2) | Bottom bar | Navigation rail | Rail |
| **Sales Staff** (2) | Bottom bar, Submit first | Navigation rail | Rail |

Destination sets, matching the role-flow map:

| Role | Destinations |
| --- | --- |
| Vendor | Dashboard · Retailers · Users · Roles · Products · Audit Logs, then Campaigns · Claims · Coins · Payouts · Reports · Settings as inert "Soon" entries |
| Retailer Owner | Overview · Shops · Staff · Products |
| Retailer Manager | Staff · Products |
| Sales Staff | Submit · History |

**Receipts never appears for the Owner or the Manager** — asserted by a test.
Receipt submission is mapped to Sales Staff alone, so every receipt RPC would
refuse them, and offering the entry would advertise a capability the database
will not grant.

**The Retailer portal advertises no unbuilt modules** — also asserted. "Soon"
placeholders sketch a roadmap to an *internal* audience; a Retailer is an external
customer.

**There is no Profile destination.** The web has no profile screen and no RPC
returns a user their own profile. Following decision **D-5**, the account surface
is a **bottom sheet from the app-bar avatar** containing what the app bar already
knows plus sign-out — and the theme selector, which is a device-local preference
needing no backend.

### Route isolation

Four `ShellRoute` groups on four non-overlapping prefixes. `redirectFor` is a
**pure function** of (session state, location), so it is tested against a table:

| Situation | Result |
| --- | --- |
| In a role group, no role resolved | → `/` |
| In a role group, a **different** role resolved | → `/access-denied` |
| In a role group, the owning role resolved | allowed |
| At `/` with a role resolved | → that role's landing |
| At `/` with `kind = 'none'` | → `/access-denied` |
| At `/` still resolving | stay |
| At `/access-denied` | always allowed |

`ShellRoute.builder` re-checks the role and renders access-denied if it does not
match, so a guard failure degrades to a refusal rather than a mis-rendered shell.

The web serves Owner, Manager and Sales Staff from one `/retailer/*` tree and
separates them server-side. Splitting them here does not weaken that — it adds a
second, purely presentational boundary on top.

> **This guard is presentation, not security.** Supabase re-decides every
> operation in SQL. If the guard were deleted, a user who typed another role's URL
> would reach a shell whose every query returned `42501`.

---

## 9. Performance strategy

The app must stay fast on ordinary Android phones, iPhones and the web.

**Not added:** any icon package, any UI framework, runtime-downloaded fonts, any
animation library, any code generation, any background service, any image asset.
Dependencies are unchanged from the previous milestone: `flutter_bloc`,
`go_router`, `get_it`, `equatable`, `supabase_flutter`.

**Done:**

- **Lazy routes.** Every page is built in a closure; nothing is constructed at
  router-build time.
- **Narrow rebuild scopes.** `BlocBuilder<ThemeCubit, ThemeMode>` wraps only
  `MaterialApp` — the router, session and routes do not rebuild on a theme
  change. Each shell's `BlocBuilder` covers only its own chrome.
- **`const` everywhere it is legal**, including every navigation model and
  destination list, which are compile-time constants.
- **No state mutation during build.** The shell syncs its selected index from
  `initState`/`didUpdateWidget`, never from `build`.
- **Painters over assets.** The brand mark is a `CustomPainter` with
  `shouldRepaint => false`.
- **Two indefinite animations only**, both justified and both suppressed under
  reduced motion: the skeleton shimmer and the button spinner.
- **`NoSplash.splashFactory`** — the web has no ripple, and skipping it removes a
  per-tap animation.
- **Responsive by `LayoutBuilder`/`MediaQuery.sizeOf`**, not by rebuilding trees.

**Deliberate deviation:** the web app bar is `bg-white/85` with a
`backdrop-blur-md`. A `BackdropFilter` is comparatively expensive — especially on
the web — and it only reads correctly when content scrolls beneath the bar, which
requires `extendBodyBehindAppBar`. The bar ships opaque with the correct height,
hairline and typography; the blur is a polish item for when a screen has enough
content to scroll under it.

**Accessibility:** `SrMotion.respects(context)` checks both `disableAnimations`
and `accessibleNavigation`. Under reduced motion the skeleton keeps its block and
drops the sweep, and the route progress bar becomes a static full-width bar
rather than disappearing — feedback preserved, movement dropped, exactly as the
web does.

---

## 10. Backend honesty

`public.get_my_portal_context()` **does not exist**. The role-flow map calls
shipping it *"the single most important thing to fix before Flutter ships"* and
the feature matrix lists it as the #1 phase-1 item.

Therefore:

- `UnimplementedPortalContextRepository` is the only implementation and always
  reports `NotImplementedFailure` — not a denial, not an outage.
- **No production role is hardcoded**, and no role is used as a fallback. A
  dedicated test file (`test/security/no_hardcoded_role_test.dart`) asserts this
  at runtime *and* at source level: no `?? AppRole.x`, no `RoleTrust.serverResolved`
  constructed outside the entity, and no `AppRole` reference anywhere under
  `data/` or `domain/`.
- **Roles are not inferred by probing RPCs.** The web's three-probe fallback is
  deliberately not reproduced.
- The gate screen states plainly that resolution is not connected and names the
  missing function.

### The development-only role showcase

The gate offers preview entry into each shell so the four can be reviewed. It is
isolated from production routing by construction:

- It renders **only** in the `NotImplementedFailure` branch, so a real resolution
  never reaches it — the showcase disappears on its own once the RPC lands.
- Choosing a role marks it `RoleTrust.localPreview`, never `serverResolved`.
- Every shell built from one carries a permanent, non-dismissible banner.
- Nothing that talks to Supabase reads the choice.
- A test asserts the event is referenced in exactly three files: its declaration,
  its BLoC handler, and the gate screen.

**To remove it:** delete `_PreviewSection` and `RoleSessionPreviewSelected`.

### Security posture

- Supabase is the only authorization authority; no Dart code decides permission.
- Only the publishable key ships. `AppConfig` is the sole reader of a
  `--dart-define`, asserted by a test.
- `dart_defines.json` is git-ignored and a test asserts `git ls-files` does not
  track it.
- No raw backend message reaches the UI; `mapSupabaseError` discriminates on
  SQLSTATE, never on message text.
- No migrations, no reward calculations, no schema live in this repository.

---

## 11. Tests

`flutter test` — **237 passing**, 12 files.

| File | Covers |
| --- | --- |
| `app/app_startup_test.dart` | Startup, brand render, honest unresolved-role screen, DI wiring, repository override |
| `app/theme/app_theme_test.dart` | **Light** and **dark** construction, v4 palette, radii, shadows, type scale, spacing, **WCAG AA contrast audit** |
| `app/theme/theme_mode_test.dart` | `ThemeCubit`, `theme`/`darkTheme`/`themeMode` wiring, **system mode** following the device, explicit overrides, the theme selector |
| `core/widgets/design_system_test.dart` | Every shared widget **in both themes**: brand, button, badge, card, stat card, text field, alert, **loading**, **empty**, **failure**, access-denied |
| `app/navigation/role_navigation_test.dart` | **Separate navigation models** — no shared list or destination instance; destination sets; chrome; landing paths |
| `app/shells/role_shells_test.dart` | **All four shells**, landings, portal captions, no cross-role leakage, chrome by viewport, "Soon" inertness, drawer behaviour, dark mode |
| `app/router/route_isolation_test.dart` | Prefix disjointness, the guard as a pure function, all 12 wrong-role deep links through the real router |
| `app/router/access_denied_test.dart` | Neutral copy, names no role, leaks no reason, both entry paths identical, sign-out |
| `features/auth/role_session_bloc_test.dart` | `AppRole` parsing and fail-closed behaviour, provenance, every BLoC transition |
| `core/errors/failure_mapper_test.dart` | SQLSTATE mapping, fail-closed default, no message leakage |
| `security/no_hardcoded_role_test.dart` | **No production hardcoded role** — runtime and source level |
| `security/no_secrets_test.dart` | No service-role key, no Resend key, no direct Storage write, one dart-define reader, `dart_defines.json` untracked |

---

## 12. What remains unimplemented

### Backend prerequisites (owned by `salesreward-admin`)

| Needed | Blocks | Priority |
| --- | --- | --- |
| `get_my_portal_context()` | **All real role resolution** | High — phase 1 |
| `submit-receipt` Edge Function | Receipt capture (SS-02) | Critical — phase 1 |
| `staff-invitation-context` Edge Function | Staff onboarding | Critical — phase 1 |
| `activate-staff-account` Edge Function | Staff onboarding | Critical — phase 1 |
| `get-receipt-image-url` Edge Function | Viewing a receipt (SS-06, Q1) | High — phase 2 |
| `send-staff-invitation` Edge Function | Owner staff management (RO-07) | High — phase 2 |
| `shop_id` on `list_retailer_owner_portal_shops()` | Any shops list (RO-02) | Contract fix #1 |
| `ELSE` on `derived_state` | A documented enum that can be `NULL` | Contract fix #2 |
| Distinct SQLSTATEs for duplicate code vs barcode | Two clients parsing English | Contract fix #3 |
| 5 Vendor RPCs + 2 Edge Functions | Vendor administration | Phase 3 |

### Not built here

- **Authentication.** No sign-in, session storage or sign-out. When it lands it
  needs `flutter_secure_storage` (never `SharedPreferences`), and sign-out must
  purge the session, any cached portal context and any queued receipts.
- **Real role resolution**, and the preview showcase that stands in for it.
- **Re-resolution on app resume** — the events exist; nothing dispatches them on
  a lifecycle change yet.
- **Every business screen.** Ten of the fourteen role destinations render
  `PlaceholderDestinationPage`, each naming the backend work it waits on.
- **Deep linking** — no universal links / app links, no token handling.
- **Repository, use-case and data-source layers** for every feature. The folders
  exist; only `auth` has contents.
- **Geist, the 38-icon set, the login artwork, the app icon** — see
  [`docs/required-design-assets.md`](./required-design-assets.md).

### Unresolved product decisions

Design decisions (handoff § 6):

| # | Decision | Status here |
| --- | --- | --- |
| **D-1** | Which indigo — v4 utilities or the mark's v3 literals? | Following the recommendation: v4 for UI, literals for the mark. Needs aligning on both platforms at once. |
| **D-2** | Should mobile lists have search? | Not added. No web precedent, no backend filter parameter. |
| **D-3** | Initials: first-two-words or first-and-last? | Following the recommendation: first + last. The web shells still differ. |
| **D-4** | Drawer everywhere vs per-role bottom bars? | Resolved per-role. Sales Staff diverges from the recommendation — see § 2.3. |
| **D-5** | Is there a profile screen? | Account **sheet** only, inventing nothing. |
| **D-6** | Tablet / landscape support? | Rail and permanent-panel layouts are implemented; not a shipping target. |
| **D-7** | Who reviews receipts? | Nothing exists — no permission, no RPC, no screen. |

Backend decisions (role-flow § 8, matrix § 7):

| # | Question | Effect on mobile |
| --- | --- | --- |
| **Q1** | Can Sales Staff view a submitted receipt? | No read path exists anywhere. History can list but not open. |
| **Q2** | Can one person belong to more than one Retailer? | Both resolvers return `NULL` — a **total silent denial**. Account switching cannot be designed until this is answered. |
| **Q3** | Can a Manager read their own Retailer's name? | The Manager shell captions itself with the portal name instead. |
| **Q4** | Does Vendor administration belong on mobile? | The whole `/vendor` group is phase 3 and conditional. |
| **Q5** | Is offline capture in scope? | Queued bytes are unencrypted customer data unless protected. |
| **Q6** | Which domain owns invitation deep links? | **Blocks phase 1.** |
| **Q8** | Should owner-invitation revoke be wired? | Granted and audited in SQL, called by nothing. |

---

## 13. Next recommended milestone

**Sales Staff receipt submission, end to end** — the smallest slice that is
genuinely mobile-native and exercises the full authorization chain, per § 11 of
the architecture recommendation.

| Deliverable | Detail |
| --- | --- |
| **Backend — 1 RPC** | `get_my_portal_context()` |
| **Backend — 3 Edge Functions** | `submit-receipt`, `staff-invitation-context`, `activate-staff-account` |
| **Backend — refactor** | Point the matching Server Actions at those functions, so there is one implementation rather than two |
| **Backend — tests** | pgTAP / `supabase test db` for the receipt and staff-acceptance RPCs |
| **Mobile — auth** | Sign in, `flutter_secure_storage` session, sign-out with purge |
| **Mobile — role** | Implement `PortalContextRepository` against the RPC; delete the preview showcase |
| **Mobile — feature** | Assigned shops · camera capture · downscale → hash → submit · history |
| **Explicitly excluded** | Vendor administration, product management, invitation *sending*, receipt image viewing, offline queue, account switching |

**Prerequisite decision:** Q6 (deep-link domain) must be answered before
invitation acceptance is started. Q1, Q2 and Q3 can be deferred without blocking.

**Why not the Retailer Owner portal first?** It is almost entirely read-only
against RPCs that already work — easy, but it would not prove the hard parts
(Storage through an Edge Function, deep-link token handling, magic-byte parity).
Proving those first de-risks everything after.

---

## 14. Running it

```bash
flutter run --dart-define-from-file=dart_defines.json
```

`dart_defines.json` is git-ignored. Copy `dart_defines.example.json` and fill in
the Supabase URL and **publishable** key — those two values and nothing else.

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release
```
