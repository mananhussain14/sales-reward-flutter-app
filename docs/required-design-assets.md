# Required Design Assets — SalesReward Mobile

Assets the mobile app does **not** ship today, why, and what would be needed to
add them.

**Nothing here blocks the foundation milestone.** Every item has a working
substitute in place, and each row states what the substitute costs.

Source of truth: `docs/mobile-ui-design-handoff.md` in `salesreward-admin` at
commit `3326cc4`.

---

## 1. Icon set

### Current state

The app uses **Flutter's built-in Material icons**. No icon package and no icon
asset is bundled.

### What the handoff asks for

§ 2.10 of the design handoff asks for the opposite:

> Flutter: **do not use Material Icons.** The stroke weight (1.75 on a 24 grid)
> and the round caps are a large part of the product's look, and Material's
> filled/outlined set will read as a different app. Port the 38 paths from
> `components/ui/icons.tsx` and render them with a stroking painter, or use
> `flutter_svg` over inlined strings.

This milestone deliberately defers that. Material icons keep the app dependency-
free and shipping today; the visual cost is real but bounded, and it is a
mechanical, self-contained substitution later.

### What would be required

| | |
| --- | --- |
| **Filename** | `assets/icons/sr_icons.dart` (inlined path data, no asset file) |
| **Format** | SVG path strings, transcribed from `components/ui/icons.tsx` |
| **Grid** | 24 × 24 viewBox |
| **Style** | `fill="none"`, `stroke="currentColor"`, `stroke-width="1.75"`, round cap **and** join |
| **Count** | 38 |
| **Rendered sizes** | 12 (in a badge), 14 (timeline node), 16 (in a button/alert), 20 (nav item, 40px disc), 24 (56px disc), 28 (access-denied shield) |
| **Light variant** | None needed — the icons inherit `currentColor` |
| **Dark variant** | None needed — same reason |
| **Colouring** | Always the caller's text colour. No icon carries its own hue. |

The 38 names, from the handoff:

> dashboard, retailers/shop, users/staff, roles, products, receipt, audit,
> settings, plus, search, upload, check, check-circle, alert-triangle, info, x,
> chevron-left, chevron-right, menu, mail, location, calendar, clock, sign-out,
> shield, reward, trending-up, arrow-up-right, building, inbox, document, key,
> user-plus, send, store, spinner

### Current Material substitutions

Where the mapping is not obvious, the choice is recorded here so a later swap is
mechanical:

| SalesReward icon | Material stand-in |
| --- | --- |
| dashboard | `dashboard_outlined` / `dashboard_rounded` |
| shop / store | `storefront_outlined` / `storefront_rounded` |
| users / staff | `group_outlined` / `group_rounded` |
| roles / key | `vpn_key_outlined` / `vpn_key_rounded` |
| products | `inventory_2_outlined` / `inventory_2_rounded` |
| receipt / audit | `receipt_long_outlined` / `receipt_long_rounded` |
| shield | `shield_outlined` |
| upload | `file_upload_outlined` |
| camera *(no web counterpart — mobile-only)* | `photo_camera_outlined` |
| alert-triangle | `warning_amber_rounded` |
| info | `info_outline_rounded` |
| check / check-circle | `check_rounded` / `check_circle_outline_rounded` |
| clock | `schedule_rounded` |
| arrow-up-right | `arrow_outward_rounded` |
| menu | `menu_rounded` |
| chevron-down (select) | `keyboard_arrow_down_rounded` |

**Accepted deviation:** Material's stroke weight is heavier than 1.75 and its
corners are less round, so icon-dense surfaces read slightly bolder than the web.

---

## 2. Geist typeface

### Current state

The app renders the **platform sans-serif** — Roboto on Android, SF on iOS, the
system UI font on the web.

### Why that is defensible

The web declares this fallback chain in `globals.css`:

```
var(--font-geist-sans), ui-sans-serif, system-ui, -apple-system,
"Segoe UI", Roboto, Arial, sans-serif
```

So the platform sans-serif is what the web itself renders before Geist loads.
Every size, weight, line height and letter-spacing value is reproduced exactly in
`SrTypography`; only the letterforms differ.

The handoff does ask for Geist to be bundled (§ 2.11), and notes that falling
back *"will visibly change the product"*. That is accepted for this milestone
rather than adding a font that downloads at runtime.

### What would be required

| | |
| --- | --- |
| **Filenames** | `assets/fonts/Geist-Regular.ttf`, `-Medium`, `-SemiBold` |
| **Weights** | 400, 500, 600 — the only three the product uses |
| **Format** | TTF or OTF, statically bundled. **Not** `google_fonts`, which fetches at runtime. |
| **Approx. size** | ~90 KB per weight subset to Latin |
| **Light variant** | N/A |
| **Dark variant** | N/A |
| **Licence** | Geist is OFL; the licence file must ship alongside |

Geist **Mono** is deliberately excluded: the handoff records that it is loaded on
the web but never actually applied to any element.

### To adopt

1. Add the three files under `assets/fonts/`.
2. Declare the family in `pubspec.yaml`.
3. Set `SrTypography.fontFamily = 'Geist'`.

Nothing else changes — no widget references a family name.

---

## 3. Brand mark

### Current state

**Already implemented, no asset needed.** `SrBrandMark` reproduces the mark with
a `CustomPainter` from the § 1 geometry table — the rounded indigo→violet tile,
the two chart bars, the arrow, and the amber reward spark.

This matches the web, which draws it as inline SVG: there is no PNG, no SVG file,
and `public/` contains no logo.

Its colours come from `SrBrandLiterals` and are theme-independent, so the mark is
identical in light and dark. That is deliberate — a logo should not re-tint.

**No action required.**

---

## 4. Login artwork

### Current state

Not implemented. Authentication is not built in this milestone.

### What would be required, if desktop/tablet login comes into scope

The web's `AuthBrandPanel` is an indigo→violet gradient panel with a faded grid
overlay, three blurred ambient glows, a drawn sales-line SVG, a headline, three
benefit rows, and a trust pill.

The handoff is explicit that it is **desktop-only and should not be ported to a
phone** — it is already hidden below `lg`. It is a reasonable tablet-landscape
asset if that form factor is ever in scope (decision **D-6**).

| | |
| --- | --- |
| **Filename** | `assets/illustrations/auth_panel_artwork.svg` |
| **Format** | SVG (the line is animated by a one-shot dash draw) |
| **Dimensions** | Fluid; the web panel is half of a ≥1024px viewport |
| **Light variant** | The gradient is dark by design; white foreground |
| **Dark variant** | None needed — the panel is already dark in light mode |

**Not required for the MVP.**

---

## 5. App icon and splash

### Current state

The Flutter template defaults are still in place.

### What would be required before any store submission

| | |
| --- | --- |
| **Filename** | `assets/branding/app_icon.png` |
| **Format** | PNG, no transparency for iOS |
| **Dimensions** | 1024 × 1024 master; platform sizes generated from it |
| **Light variant** | The brand tile on its own gradient |
| **Dark variant** | Same tile — the mark does not re-tint |
| **Adaptive (Android)** | Foreground: the chart-and-spark glyph on transparency. Background: the indigo→violet gradient, or flat `#4F46E5`. |
| **Splash** | The mark centred on `#F8FAFC` (light) / `#020618` (dark) |

The master can be exported from the same geometry `SrBrandMark` already paints,
so it needs no new design work — only a render.

**Not required for this milestone**, which produces no store build.

---

## 6. Summary

| Asset | Status | Blocks this milestone |
| --- | --- | --- |
| Brand mark | ✅ Implemented as a painter | No |
| Icon set (38, stroke 1.75) | ⚠️ Material substitutes in use | No |
| Geist typeface | ⚠️ Platform font in use | No |
| Login artwork | ⛔ Not started, desktop-only | No |
| App icon / splash | ⛔ Flutter defaults | No — needed before a store build |
