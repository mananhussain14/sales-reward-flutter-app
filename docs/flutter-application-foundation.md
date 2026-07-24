# Flutter Application Foundation — SalesReward

The mobile application's shared foundation and its four role experiences. This
milestone builds **no business feature**: it establishes the theme, the design
system, the four role shells, the role-isolated route groups, the shared state
widgets, and the tests that hold all of it in place.

---

## 1. Backend contract source

Everything in this document is derived from the authoritative Next.js and
Supabase repository, `salesreward-admin`.

| | |
| --- | --- |
| **Source repository** | `salesreward-admin` |
| **Commit** | `3ba3799eebecd0b93c2ddb7bd4fe4695bd426caa` |
| **Short** | `3ba3799` — *Merge pull request #25 from mananhussain14/perf/navigation-loading-feedback* |
| **Dated** | 2026-07-24 |
| **Read on** | 2026-07-24 |

### Documents consulted

| Document | Status |
| --- | --- |
| `docs/mobile-backend-contract.md` | Present |
| `docs/mobile-feature-matrix.md` | Present |
| `docs/mobile-architecture-recommendation.md` | Present |
| `docs/mobile-ui-design-handoff.md` | **Does not exist** |
| `docs/mobile-role-flow-map.md` | **Does not exist** |

Two of the five named documents are absent from the repository at that commit.
Their content was reconstructed from the authoritative source instead:

- **Visual identity** — read directly from `app/globals.css` (the design-token
  block, the shadow scale, the motion helpers) and from the component class
  strings in `components/ui/*` (`button.tsx`, `card.tsx`, `field.tsx`,
  `badge.tsx`, `page-header.tsx`, `empty-state.tsx`, `status-card.tsx`,
  `skeleton.tsx`, `brand.tsx`, `access-denied-card.tsx`) and
  `components/admin/stat-card.tsx`. Those files *are* the design system — the
  CSS comment states there is deliberately no bespoke color layer — so this is
  the primary source rather than a substitute for one.
- **Role flow** — taken from § 4 of the architecture recommendation (the shell
  and landing table), `lib/auth/landing-decision.ts` (vendor-first precedence and
  the `LANDING_ROUTES` map), `lib/staff/portal-access-decision.ts` (the
  owner / reader / submitter selection), and the two navigation files
  `components/admin/nav-items.tsx` and
  `components/retailer-portal/retailer-nav-items.tsx`.

> **Note.** At the read commit the `docs/` directory is **untracked** in
> `salesreward-admin` (`git status` reports `?? docs/`). The three documents were
> read from the working tree. If they are committed later under a different
> commit, this reference should be updated to that commit.

---

## 2. Shared versus role-specific architecture

The organising rule: **domain and data are organised by business feature and
shared; presentation is organised by role and separated.**

### Shared foundation

Everything here is role-neutral. None of it branches on a role.

| Concern | Location |
| --- | --- |
| Supabase initialization | `lib/app/bootstrap.dart` |
| Application configuration | `lib/app/config/app_config.dart` |
| Dependency graph | `lib/app/di/injector.dart` |
| Failure contract and error mapping | `lib/core/errors/` |
| Design tokens | `lib/core/design/` |
| Design system widgets | `lib/core/widgets/` |
| Theme assembly | `lib/app/theme/app_theme.dart` |
| Role entity and provenance | `lib/features/auth/domain/entities/app_role.dart` |
| Role resolution contract | `lib/features/auth/domain/repositories/` |
| Role session BLoC | `lib/features/auth/presentation/bloc/` |
| Shell chrome | `lib/app/shells/base/` |
| Router and guard | `lib/app/router/` |

### Role-specific

Each role owns all of the following, and shares none of it with another role:

| Concern | Vendor Super Admin | Retailer Owner | Retailer Manager | Sales Staff |
| --- | --- | --- | --- | --- |
| Route prefix | `/vendor` | `/retailer-owner` | `/retailer-manager` | `/sales-staff` |
| Navigation model | `shells/vendor/vendor_navigation.dart` | `shells/retailer_owner/…` | `shells/retailer_manager/…` | `shells/sales_staff/…` |
| Shell widget | `VendorShell` | `RetailerOwnerShell` | `RetailerManagerShell` | `SalesStaffShell` |
| Shell BLoC | `VendorShellBloc` | `RetailerOwnerShellBloc` | `RetailerManagerShellBloc` | `SalesStaffShellBloc` |
| Chrome | Drawer | Bottom bar / rail | Bottom bar / rail | Bottom bar / rail |
| Landing | `/vendor/dashboard` | `/retailer-owner/overview` | `/retailer-manager/staff` | `/sales-staff/submit` |
| Landing screen | `features/dashboard/presentation/vendor/` | `features/dashboard/presentation/retailer_owner/` | `features/staff/presentation/retailer_manager/` | `features/receipts/presentation/sales_staff/` |

### What is deliberately not done

- **No dashboard that hides buttons per role.** There is no `if (role == …)`
  anywhere in a shell or a page. Four shells, four navigation lists, four BLoCs.
- **No single BLoC holding every role's behaviour.** `RoleSessionBloc` is shared
  because the question it answers is role-*neutral* — "which experience is this
  caller in?" — not because sharing was convenient.
- **No filtered master navigation list.** Each role's destinations are declared
  in full, in their own file. The Retailer Manager's menu is *not*
  `ownerDestinations.where(...)`. The web repository states the reason plainly
  in `retailer-nav-items.tsx`: *two lists that share nothing cannot leak into
  each other.* A filtered list is one rendering bug away from showing a Vendor
  entry inside a Sales Staff shell.
- **No duplicated domain entities.** `AppRole` and the failure union are declared
  once and used by every role.

---

## 3. Folder layout

```
lib/
├── main.dart
├── app/
│   ├── app.dart                     root widget; owns RoleSessionBloc + router
│   ├── bootstrap.dart               Supabase.initialize + DI + runApp
│   ├── config/app_config.dart       dart-define reads (the ONLY place)
│   ├── di/injector.dart             get_it registration
│   ├── theme/app_theme.dart         ThemeData assembled from tokens
│   ├── navigation/
│   │   ├── role_destination.dart    RoleDestination, RoleShellChrome, RoleNavigation
│   │   └── role_navigation_registry.dart   role → model lookup (not a filter)
│   ├── router/
│   │   ├── app_routes.dart          the two role-neutral routes
│   │   ├── app_router.dart          four route groups + the guard
│   │   └── router_refresh.dart      BLoC stream → GoRouter.refreshListenable
│   └── shells/
│       ├── base/
│       │   ├── role_shell_bloc.dart            shared navigation mechanics
│       │   ├── role_shell_scaffold.dart        shared chrome (drawer/bar/rail)
│       │   └── placeholder_destination_page.dart
│       ├── vendor/{vendor_navigation,vendor_shell}.dart + bloc/
│       ├── retailer_owner/…
│       ├── retailer_manager/…
│       └── sales_staff/…
│
├── core/
│   ├── design/
│   │   ├── sr_colors.dart           :root custom properties + Tailwind steps
│   │   ├── sr_typography.dart       the type scale
│   │   ├── sr_spacing.dart          SrSpacing + SrRadii
│   │   ├── sr_shadows.dart          SrShadows + SrMotion
│   │   ├── sr_status_tones.dart     the six badge tones
│   │   └── design.dart              barrel
│   ├── errors/
│   │   ├── sql_state.dart           42501 / 23505 / 23514 / 55000
│   │   ├── failure.dart             the sealed Failure union
│   │   ├── failure_mapper.dart      the ONLY place a backend error is inspected
│   │   └── errors.dart              barrel
│   └── widgets/
│       ├── sr_brand_mark.dart       BrandMark + BrandLockup (CustomPainter)
│       ├── sr_card.dart             SrCard, SrSectionCard, SrIconDisc
│       ├── sr_button.dart           5 variants × 3 sizes, built-in busy state
│       ├── sr_text_field.dart       SrTextField, SrField
│       ├── sr_badge.dart            SrBadge, SrStatusBadge
│       ├── sr_stat_card.dart        metric card; null ≠ zero
│       ├── sr_page_header.dart      SrPageHeader, SrSectionHeader, SrPageBody
│       ├── sr_loading_view.dart     SrSkeleton, SrSkeletonCard/List, SrLoadingView
│       ├── sr_empty_state.dart      dashed-outline empty state
│       ├── sr_failure_view.dart     Failure → copy, tone, retry
│       ├── sr_access_denied_view.dart
│       └── widgets.dart             barrel
│
└── features/
    ├── auth/
    │   ├── domain/entities/app_role.dart
    │   ├── domain/repositories/portal_context_repository.dart
    │   ├── data/repositories/unimplemented_portal_context_repository.dart
    │   └── presentation/{bloc,pages}/
    ├── dashboard/presentation/{vendor,retailer_owner}/pages/
    ├── staff/presentation/retailer_manager/pages/
    └── receipts/presentation/sales_staff/pages/
```

---

## 4. Design-system mapping

Nothing was ported from React or Tailwind as code. Every token below is a value
read from the web source and re-expressed in Dart, with the origin recorded in
the Dart file's doc comment.

### Color

| Web | Dart | Value |
| --- | --- | --- |
| `--app-background` (slate-50) | `SrColors.appBackground` | `#F8FAFC` |
| `--app-background-secondary` | `SrColors.appBackgroundSecondary` | `#F1F5F9` |
| `--surface` | `SrColors.surface` | `#FFFFFF` |
| `--surface-nav` (slate-900) | `SrColors.surfaceNav` | `#0F172A` |
| `--border` (slate-200) | `SrColors.border` | `#E2E8F0` |
| `--border-strong` (slate-300) | `SrColors.borderStrong` | `#CBD5E1` |
| `--brand` (indigo-600) | `SrColors.brand` | `#4F46E5` |
| `--brand-hover` (indigo-700) | `SrColors.brandHover` | `#4338CA` |
| `--brand-soft` (indigo-50) | `SrColors.brandSoft` | `#EEF2FF` |
| `--foreground` (slate-900) | `SrColors.foreground` | `#0F172A` |
| `--text-secondary` (slate-600) | `SrColors.textSecondary` | `#475569` |
| `--text-muted` (slate-500) | `SrColors.textMuted` | `#64748B` |
| `::selection` | `SrColors.selectionBackground` | `#C7D2FE` |

`ColorScheme.fromSeed` is deliberately **not** used: it would derive tones that
appear nowhere in the web product. The scheme is stated exactly.

The app is **light-only**, mirroring `html { color-scheme: light }`. Shipping a
dark theme would create a second visual identity with no web counterpart to keep
it honest.

### Elevation

Flutter's `BoxShadow.blurRadius` matches the CSS blur radius, so each stop is a
direct translation of the `@theme inline` block.

| Web | Dart |
| --- | --- |
| `--shadow-card` | `SrShadows.card` (2 stops) |
| `--shadow-elevated` | `SrShadows.elevated` (2 stops) |
| `--shadow-modal` | `SrShadows.modal` (2 stops) |
| `--shadow-brand` | `SrShadows.brand` |
| Tailwind `shadow-sm` | `SrShadows.subtle` |

Every stop is tinted with slate-900 at low alpha rather than black. Card shadows
are painted by `SrCard`, not by Material elevation, because Material's single
tinted shadow would lose the layered recipe.

### Typography

The web loads **Geist Sans** through `next/font/google`, with this documented
fallback stack in `globals.css`:

```
var(--font-geist-sans), ui-sans-serif, system-ui, -apple-system,
"Segoe UI", Roboto, Arial, sans-serif
```

**This milestone ships no bundled font asset and no network font fetch**, so the
app renders the platform sans-serif — which is exactly the fallback the web app
itself uses when Geist has not loaded. The *hierarchy* is carried by size, weight
and letter-spacing, and those are reproduced exactly:

| Web class | Dart | Size / line-height / weight |
| --- | --- | --- |
| `text-2xl font-semibold tracking-tight` | `SrTypography.pageTitle` | 24 / 32 / 600, ls −0.6 |
| `text-xl font-semibold tracking-tight` | `screenTitle` | 20 / 28 / 600, ls −0.5 |
| `text-lg font-semibold tracking-tight` | `sectionTitle` | 18 / 28 / 600, ls −0.45 |
| `text-base font-semibold` | `cardTitle` | 16 / 24 / 600 |
| `text-sm` | `body` | 14 / 20 / 400 |
| `text-sm text-slate-500` | `bodyMuted` | 14 / 20 / 400 |
| `text-sm font-medium text-slate-800` | `label` | 14 / 20 / 500 |
| `text-xs text-slate-500` | `caption` | 12 / 16 / 400 |
| `text-xs font-semibold uppercase tracking-wide text-indigo-600` | `eyebrow` | 12 / 16 / 600, ls +0.6 |
| `text-sm font-medium text-red-700` | `fieldError` | 14 / 20 / 500 |

**To bundle Geist later:** add the asset to `pubspec.yaml` and set
`SrTypography.fontFamily`. Nothing else changes.

### Geometry

| Web | Dart | Value |
| --- | --- | --- |
| `rounded-md` | `SrRadii.sm` | 6 |
| `rounded-lg` | `SrRadii.md` | 8 |
| `rounded-xl` (buttons, inputs) | `SrRadii.lg` | 12 |
| `rounded-2xl` (cards, discs) | `SrRadii.xl` | 16 |
| `rounded-full` | `SrRadii.full` | 9999 |

Spacing follows Tailwind's 4px scale via `SrSpacing`; a test asserts every step
is a multiple of 4.

### Components

| Web component | Dart widget | Notes |
| --- | --- | --- |
| `button.tsx` | `SrButton` | 5 variants × 3 sizes (h-9/11/12), built-in spinner + disable |
| `card.tsx` | `SrCard`, `SrSectionCard` | 4 variants; `interactive` lifts on press instead of hover |
| `field.tsx` | `SrTextField`, `SrField` | Label above, message **below** the control |
| `badge.tsx` | `SrBadge`, `SrStatusBadge` | The full `STATUS_MAP`; unknown → "Unknown" |
| `page-header.tsx` | `SrPageHeader`, `SrSectionHeader` | Actions wrap below the title on mobile |
| `empty-state.tsx` | `SrEmptyState` | Dashed 16px outline drawn by a custom `OutlinedBorder` |
| `skeleton.tsx` | `SrSkeleton`, `SrSkeletonCard`, `SrSkeletonList` | Shimmer honours reduced-motion |
| `access-denied-card.tsx` | `SrAccessDeniedView` | Copy fixed and role-neutral |
| `admin/stat-card.tsx` | `SrStatCard` | `null` renders "Unavailable", never `0` |
| `brand.tsx` | `SrBrandMark`, `SrBrandLockup` | SVG re-drawn as a `CustomPainter` |

### Desktop → mobile adaptations

| Desktop | Mobile |
| --- | --- |
| Fixed dark sidebar, 6+ links | Navigation **drawer** on the same `--surface-nav` (Vendor) |
| Fixed sidebar, 3–5 links | **Bottom bar** below 640px, **rail** at 640px and above |
| Data tables | Card lists (`SrSkeletonList` shows the shape) |
| Horizontal / two-column forms | Vertical stacks; `SrTextField` keeps the label-above rule |
| Desktop dialogs | Material dialogs and bottom sheets, both at the 16px card radius |
| Dashboard grids | `Wrap` that stacks on a phone and pairs up from 520px |
| Hover states | Press states (`SrMotion.fast`, 150ms — the web's `duration-150`) |

Content is capped at `SrSpacing.contentMaxWidth` (720) so a card does not stretch
to full width on a tablet or on Flutter web.

---

## 5. Navigation strategy

### The role-navigation model

`RoleNavigation` (in `lib/app/navigation/role_destination.dart`) holds, per role:
the owning `AppRole`, the route prefix, the landing path, the chrome, and the
destinations. Each role's model is declared in full in its own file beside its
shell. `RoleNavigationRegistry` is a **lookup**, not a filter.

| Role | Wire `kind` | Prefix | Chrome | Destinations |
| --- | --- | --- | --- | --- |
| Vendor Super Admin | `vendor` | `/vendor` | Drawer | Dashboard · Retailers · Users · Roles · Products · Audit logs · Profile |
| Retailer Owner | `owner` | `/retailer-owner` | Bottom bar / rail | Overview · Shops · Staff · Products · Profile |
| Retailer Manager | `reader` | `/retailer-manager` | Bottom bar / rail | Staff · Products · Profile |
| Sales Staff | `submitter` | `/sales-staff` | Bottom bar / rail | Submit · History · Profile |

These match § 4.2 of the architecture recommendation. Two deliberate shapes:

- **No Receipts tab for Owner or Manager.** Receipt submission belongs to Sales
  Staff alone, so those RPCs would refuse both. Offering the entry would
  advertise a capability the database will not grant.
- **Sales Staff splits the web's single Receipts page into Submit and History,**
  because capture is why this role opens the app and deserves to be one tap away.

### Route isolation

Four `ShellRoute` groups, one per role, on four non-overlapping prefixes. The
guard — `redirectFor(RoleSessionState, String)` in `app_router.dart` — is a pure
function, so it is tested against a table of cases rather than only through the
widget tree:

| Situation | Result |
| --- | --- |
| Inside a role group, no role resolved | → `/` (the gate) |
| Inside a role group, a **different** role resolved | → `/access-denied` |
| Inside a role group, the owning role resolved | allowed |
| At `/` with a role resolved | → that role's landing path |
| At `/` with `kind = 'none'` | → `/access-denied` |
| At `/` still resolving | stay |
| At `/access-denied` | always allowed (guarding it would loop) |

`ShellRoute.builder` re-checks the role and renders the access-denied screen if
it does not match, so a guard failure degrades to a refusal rather than to a
mis-rendered shell.

**This guard is presentation, not security.** Supabase remains the authorization
authority and re-decides every operation in SQL. If the guard were deleted, a
user who typed another role's URL would reach a shell whose every query returned
`42501`.

### Landing precedence

The web establishes **vendor-first precedence** in `lib/auth/landing-decision.ts`:
a user holding both a Vendor and a Retailer role lands on the Vendor experience.
Mobile inherits it — but the rule is applied by whatever *resolves* the role
(the proposed `get_my_portal_context()`, which folds it into one row), not by the
client. `RoleNavigationRegistry.ordered` records the intended order so the rule
has one written home on the mobile side.

---

## 6. BLoC ownership

| BLoC | Scope | Owns | Provided by |
| --- | --- | --- | --- |
| `RoleSessionBloc` | Application | Role resolution, provenance, preview selection, clearing | `SaleRewardApp` |
| `VendorShellBloc` | Vendor shell | Which Vendor destination is active | `VendorShell` |
| `RetailerOwnerShellBloc` | Owner shell | Which Owner destination is active | `RetailerOwnerShell` |
| `RetailerManagerShellBloc` | Manager shell | Which Manager destination is active | `RetailerManagerShell` |
| `SalesStaffShellBloc` | Sales Staff shell | Which Sales Staff destination is active | `SalesStaffShell` |

**Why one shared BLoC:** the question "which experience is this caller in?" is
role-neutral, is asked once per session, and must be re-asked on resume. Every
role needs the same answer.

**Why four shell BLoCs rather than one parameterised instance:** the mechanics
are shared once, in the abstract `RoleShellBloc`; the four concrete subclasses
exist so the *type system* prevents one role's shell from receiving another
role's state object. It also gives each role an obvious home for behaviour that
diverges later — a Sales Staff offline-queue badge, a Vendor pending-approval
count — without any of them growing a `switch (role)`.

**States.** `RoleSessionState` is a six-way union — initial, resolving, active,
no-access, failed — rather than "role or null". Collapsing "resolving", "no
role", "refused" and "backend unreachable" into one falsy value is exactly the
mistake the web layer avoids: an outage must never render as a denial.

---

## 7. Security posture

- **Supabase is the only authorization authority.** No Dart code decides whether
  an operation is permitted.
- **A role is never proof of permission.** `AppRole` gates layout only, and
  `AppRole.fromWireKind` fails closed on `'none'`, `null` and anything
  unrecognized.
- **A role is never trusted blindly.** `ResolvedRole` carries `RoleTrust`, so a
  locally chosen preview role cannot be mistaken for a resolved one anywhere in
  the app — and every shell built from one shows a permanent banner.
- **Only the publishable key ships.** `AppConfig` is the sole reader of a
  `--dart-define`, asserted by a source-safety test. No service-role key, no
  Resend key, no OCR credential.
- **`dart_defines.json` is git-ignored** (`.gitignore:53`) and a test asserts
  `git ls-files` does not track it.
- **No raw backend message reaches the UI.** `mapSupabaseError` is the only place
  a backend error is inspected, and it discriminates on SQLSTATE, never on
  message text.
- **A transport failure is never a denial**, and a denial carries no detail —
  preserving the deliberate overloading of `42501`, which makes "not authorized",
  "no such id" and "someone else's id" indistinguishable.
- **The access-denied screen names no role and gives no reason**, asserted by
  tests, so its two entry paths are indistinguishable.
- **No migrations, no reward calculations, no schema** live in this repository.

---

## 8. Tests

`flutter test` — **121 passing.**

| File | Covers |
| --- | --- |
| `test/app/app_startup_test.dart` | Startup, brand render, the honest unresolved-role screen, DI wiring, repository override |
| `test/app/theme/app_theme_test.dart` | Theme construction, palette, radii, shadows, type scale, spacing rhythm |
| `test/app/shells/role_shells_test.dart` | Each role builds its own shell and lands correctly; no shell exposes another role's destinations; chrome adapts by width; tab navigation |
| `test/app/router/route_isolation_test.dart` | Prefix disjointness, no shared path, the guard as a pure function, and all 12 wrong-role deep links driven through the real router |
| `test/app/router/access_denied_test.dart` | Neutral copy, names no role, leaks no reason, both entry paths identical, sign-out clears the role |
| `test/features/auth/role_session_bloc_test.dart` | `AppRole` parsing and fail-closed behaviour, provenance, the unimplemented repository, every BLoC transition |
| `test/core/errors/failure_mapper_test.dart` | SQLSTATE mapping, fail-closed default, no message leakage, denial carries no detail |
| `test/security/no_secrets_test.dart` | Source-safety: no service-role key, no Resend key, no direct Storage write, no hardcoded permission check, one dart-define reader, `dart_defines.json` untracked |

The source-safety file is the Dart counterpart of the web repository's
`*-source-safety.test.ts` suite, recommended as "Tier 4" in § 9.2 of the
architecture recommendation.

---

## 9. What remains unimplemented

### Backend prerequisites (owned by `salesreward-admin`)

| Needed | Blocks | Priority in the matrix |
| --- | --- | --- |
| `get_my_portal_context()` | **All real role resolution** | High — phase 1 |
| `submit-receipt` Edge Function | Receipt capture | Critical — phase 1 |
| `staff-invitation-context` Edge Function | Staff onboarding | Critical — phase 1 |
| `activate-staff-account` Edge Function | Staff onboarding | Critical — phase 1 |
| `get-receipt-image-url` Edge Function | Viewing a receipt (**Q1**) | High — phase 2 |
| `send-staff-invitation` Edge Function | Owner staff management | High — phase 2 |
| `shop_id` on `list_retailer_owner_portal_shops()` | Any shops list | Contract fix #1 |
| 5 Vendor RPCs + 2 Edge Functions | Vendor administration | Phase 3 |

### Not built in this repository

- **Authentication.** No sign-in, no session storage, no sign-out. When it lands
  it needs `flutter_secure_storage` (never `SharedPreferences`), and sign-out
  must purge the session, any cached portal context, and any queued receipts.
- **Real role resolution.** `UnimplementedPortalContextRepository` is the only
  implementation and always reports `NotImplementedFailure`.
- **The preview role selector** on the gate screen is a scaffold-only affordance.
  Delete it, along with `RoleSessionPreviewSelected` and the preview banner, when
  role resolution is wired.
- **Re-resolution on app resume** (§ 4.3) — the events exist; nothing dispatches
  them on a lifecycle change yet.
- **Every business screen.** Fourteen of the eighteen role destinations render
  `PlaceholderDestinationPage`, each naming the backend work it waits on. The
  other four are the role landing screens, which demonstrate the theme and read
  nothing.
- **Deep linking.** No universal links / app links, no token handling.
- **The Geist font asset.**
- **Repository, use-case and data-source layers** for every feature. The Clean
  Architecture folders exist; only `auth` has any contents.

### Unresolved product decisions

Carried forward from the contract documents; none is decided here.

| # | Question | Effect on mobile |
| --- | --- | --- |
| **Q1** | Should a Sales Staff member be able to view a submitted receipt image? | There is no read path anywhere in the backend. History can list but not show. |
| **Q2** | Can one person belong to more than one Retailer? | Both resolvers return `NULL` for a multi-Retailer user — total silent denial. Account switching cannot be designed until this is answered. |
| **Q3** | Should a Retailer Manager be able to read their own Retailer's name? | The Manager shell cannot caption itself with its organization. |
| **Q4** | Does Vendor administration belong on mobile at all? | The whole `/vendor` group is phase 3 and conditional. |
| **Q5** | Is offline receipt capture in scope? | Queued images are unencrypted customer data unless deliberately protected. |
| **Q6** | Which domain owns invitation deep links? | **Blocks phase 1.** Must be answered before invitation acceptance is built. |
| **Q8** | Should owner-invitation revocation be wired? | Granted and audited in SQL, called by nothing. |

### Decisions taken in this repository

| Decision | Rationale |
| --- | --- |
| Sales Staff gets **Submit** and **History** as separate tabs | Capture is the reason the role opens the app |
| Vendor gets a **drawer**, the other three a **bottom bar** | Six destinations do not fit a bottom bar |
| Bottom bar promotes to a **rail** at 640px | Tablets and Flutter web |
| **No dark theme** | The web product is light-only; a mobile dark theme would have no counterpart to stay honest against |
| **Platform font** rather than a bundled or fetched Geist | Matches the web's own documented fallback; adding the asset later changes one constant |
| The unresolved-role state is a **visible screen**, not a silent default | The alternative is a build that looks like role resolution works |

---

## 10. Running it

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
