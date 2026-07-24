import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/core/design/design.dart';

import '../../support/contrast.dart';

/// Theme construction, light and dark.
///
/// These assertions are the guard against the mobile app drifting away from the
/// web product's visual identity. Each pins a value documented in
/// `docs/mobile-ui-design-handoff.md`, so changing the look becomes a deliberate
/// edit to a test rather than an accident.
void main() {
  group('AppTheme.light', () {
    late ThemeData theme;

    setUp(() => theme = AppTheme.light);

    test('constructs without throwing and uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
    });

    test('carries the SalesReward colour layer as a theme extension', () {
      expect(theme.extension<SrColorScheme>(), same(SrColorScheme.light));
    });

    test('uses the Tailwind v4 indigo, not the v3 hex', () {
      // § 2.1: `indigo-600` renders #4F39F6 in Tailwind v4. #4F46E5 is the
      // v3-era literal, which survives only inside the brand mark (D-1).
      expect(SrColorScheme.light.brand, const Color(0xFF4F39F6));
      expect(SrColorScheme.light.brand, isNot(const Color(0xFF4F46E5)));
      expect(theme.colorScheme.primary, SrColorScheme.light.brand);
    });

    test('keeps the brand mark on its own v3-era literals', () {
      // The one documented exception, isolated so it cannot spread.
      expect(SrBrandLiterals.gradientStart, const Color(0xFF4F46E5));
      expect(SrBrandLiterals.gradientEnd, const Color(0xFF7C3AED));
      expect(SrBrandLiterals.spark, const Color(0xFFF59E0B));
    });

    test('paints the page on slate-50 and surfaces on white', () {
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
      expect(SrColorScheme.light.surface, const Color(0xFFFFFFFF));
    });

    test('the hairline is slate-200 and the strong border slate-300', () {
      expect(SrColorScheme.light.border, const Color(0xFFE2E8F0));
      expect(SrColorScheme.light.borderStrong, const Color(0xFFCAD5E2));
    });

    test('the navigation surface is WHITE, not the unused --surface-nav', () {
      // § 2.3: `--surface-nav` (#0F172A) is declared but never applied — the
      // shipped sidebar is white — and the handoff says not to build a dark
      // drawer from it.
      expect(SrColorScheme.light.surfaceNav, const Color(0xFFFFFFFF));
      expect(theme.drawerTheme.backgroundColor, const Color(0xFFFFFFFF));
    });

    test('the drawer is 256 wide, matching the sidebar', () {
      expect(theme.drawerTheme.width, 256);
    });

    test('cards take the 16 radius and the hairline', () {
      final RoundedRectangleBorder shape =
          theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(SrRadii.surface));
      expect(shape.side.color, SrColorScheme.light.border);
      expect(
        theme.cardTheme.elevation,
        0,
        reason: 'the layered shadow recipe is painted by SrCard',
      );
    });

    test('form controls take the 12 radius and the strong border', () {
      final OutlineInputBorder border =
          theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(SrRadii.control));
      expect(border.borderSide.color, SrColorScheme.light.borderStrong);
    });

    test('a focused control turns brand-indigo with a thicker edge', () {
      final OutlineInputBorder focused =
          theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, SrColorScheme.light.inputFocusBorder);
      expect(focused.borderSide.width, 2);
    });

    test('navigation marks the active destination with the brand tint', () {
      expect(
        theme.navigationBarTheme.indicatorColor,
        SrColorScheme.light.navActiveFill,
      );
      expect(
        theme.navigationRailTheme.indicatorColor,
        SrColorScheme.light.navActiveFill,
      );
    });

    test('the app bar is 64 tall with no elevation', () {
      expect(theme.appBarTheme.toolbarHeight, SrSpacing.appBarHeight);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
    });

    test('dialogs and sheets keep the surface radius', () {
      final RoundedRectangleBorder dialog =
          theme.dialogTheme.shape! as RoundedRectangleBorder;
      expect(dialog.borderRadius, BorderRadius.circular(SrRadii.surface));
    });
  });

  group('AppTheme.dark', () {
    late ThemeData theme;

    setUp(() => theme = AppTheme.dark);

    test('constructs without throwing', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('carries the dark colour layer as a theme extension', () {
      expect(theme.extension<SrColorScheme>(), same(SrColorScheme.dark));
      expect(theme.extension<SrColorScheme>()!.isDark, isTrue);
    });

    test('descends the surface ramp instead of inverting it', () {
      final SrColorScheme dark = SrColorScheme.dark;
      expect(dark.background, SrPalette.slate950);
      expect(dark.surface, SrPalette.slate900);
      // A card must be lighter than the page behind it, in both themes.
      expect(
        relativeLuminance(dark.surface),
        greaterThan(relativeLuminance(dark.background)),
      );
      expect(
        relativeLuminance(SrColorScheme.light.surface),
        greaterThan(relativeLuminance(SrColorScheme.light.background)),
      );
    });

    test('keeps the brand in the indigo family', () {
      // Not an inversion: a literal inversion of indigo is yellow-green.
      final SrColorScheme dark = SrColorScheme.dark;
      expect(dark.brand, SrPalette.indigo500);
      expect(dark.brand.b, greaterThan(dark.brand.r));
      expect(dark.brand.b, greaterThan(dark.brand.g));
    });

    test('every status tone stays in its own hue family', () {
      final SrColorScheme light = SrColorScheme.light;
      final SrColorScheme dark = SrColorScheme.dark;

      // Success stays green-dominant, error stays red-dominant, in both.
      for (final SrColorScheme scheme in <SrColorScheme>[light, dark]) {
        final Color success = scheme.tone(SrTone.emerald).foreground;
        expect(success.g, greaterThan(success.r));

        final Color error = scheme.tone(SrTone.red).foreground;
        expect(error.r, greaterThan(error.g));
      }
    });

    test('the structure is identical to light — only colour differs', () {
      final ThemeData light = AppTheme.light;

      expect(
        (theme.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
        (light.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
      );
      expect(theme.appBarTheme.toolbarHeight, light.appBarTheme.toolbarHeight);
      expect(theme.drawerTheme.width, light.drawerTheme.width);
      expect(theme.navigationBarTheme.height, light.navigationBarTheme.height);
      expect(
        theme.textTheme.bodyMedium!.fontSize,
        light.textTheme.bodyMedium!.fontSize,
      );
    });

    test('shadows re-tint to black so they remain visible', () {
      expect(
        SrColorScheme.light.cardShadow.first.color.r,
        SrPalette.slate900.r,
      );
      expect(SrColorScheme.dark.cardShadow.first.color.r, 0);
      // Same geometry, different tint — the elevation language is unchanged.
      expect(
        SrColorScheme.dark.cardShadow.first.blurRadius,
        SrColorScheme.light.cardShadow.first.blurRadius,
      );
    });
  });

  group('dark-theme contrast audit', () {
    final SrColorScheme dark = SrColorScheme.dark;

    test('body and heading text clear AA on both dark surfaces', () {
      for (final Color background in <Color>[dark.background, dark.surface]) {
        for (final (String name, Color color) in <(String, Color)>[
          ('foreground', dark.foreground),
          ('textLabel', dark.textLabel),
          ('textBody', dark.textBody),
          ('textSecondary', dark.textSecondary),
          ('textMuted', dark.textMuted),
        ]) {
          expect(
            contrastRatio(color, background),
            greaterThanOrEqualTo(aaNormalText),
            reason: '$name on ${background.toARGB32().toRadixString(16)}',
          );
        }
      }
    });

    test('every status tone clears AA on its own fill', () {
      for (final SrTone tone in SrTone.values) {
        final SrToneColors colors = dark.tone(tone);
        expect(
          contrastRatio(colors.foreground, colors.fill),
          greaterThanOrEqualTo(aaNormalText),
          reason: '${tone.name} foreground on its own fill',
        );
        expect(
          contrastRatio(colors.alertText, colors.fill),
          greaterThanOrEqualTo(aaNormalText),
          reason: '${tone.name} alert text on its own fill',
        );
      }
    });

    test('button labels clear AA on their fills', () {
      expect(
        contrastRatio(dark.onBrand, dark.brand),
        greaterThanOrEqualTo(aaNormalText),
      );
      expect(
        contrastRatio(dark.onSecondary, dark.secondaryFill),
        greaterThanOrEqualTo(aaNormalText),
      );
      expect(
        contrastRatio(dark.onOutline, dark.outlineFill),
        greaterThanOrEqualTo(aaNormalText),
      );
      expect(
        contrastRatio(dark.onBrand, dark.dangerFill),
        greaterThanOrEqualTo(aaNormalText),
      );
    });

    test('the active navigation label clears AA on its tinted fill', () {
      expect(
        contrastRatio(dark.navActiveLabel, dark.navActiveFill),
        greaterThanOrEqualTo(aaNormalText),
      );
      expect(
        contrastRatio(dark.navLabel, dark.surfaceNav),
        greaterThanOrEqualTo(aaNormalText),
      );
    });

    test('borders are distinguishable from the surfaces they sit on', () {
      expect(
        contrastRatio(dark.border, dark.surface),
        greaterThan(1.0),
        reason: 'a hairline that matches its surface is not a hairline',
      );
      expect(
        contrastRatio(dark.borderStrong, dark.inputFill),
        greaterThan(1.2),
      );
    });
  });

  group('typography', () {
    test('carries no colour — colour is applied per theme', () {
      for (final TextStyle style in <TextStyle>[
        SrTypography.pageTitle,
        SrTypography.sectionTitle,
        SrTypography.cardTitle,
        SrTypography.body,
        SrTypography.label,
        SrTypography.caption,
        SrTypography.badge,
        SrTypography.eyebrow,
      ]) {
        expect(
          style.color,
          isNull,
          reason: 'a baked-in colour makes the style un-themeable',
        );
      }
    });

    test('matches the documented Tailwind steps', () {
      expect(SrTypography.pageTitle.fontSize, 24);
      expect(SrTypography.pageTitle.fontWeight, FontWeight.w600);
      expect(SrTypography.screenTitle.fontSize, 20);
      expect(SrTypography.sectionTitle.fontSize, 18);
      expect(SrTypography.cardTitle.fontSize, 16);
      expect(SrTypography.body.fontSize, 14);
      expect(SrTypography.caption.fontSize, 12);
      expect(SrTypography.statValue.fontSize, 30);
      expect(SrTypography.statUnavailable.fontSize, 18);
    });

    test('uses the Tailwind default line heights', () {
      expect(SrTypography.body.height, closeTo(1.4286, 0.001));
      expect(SrTypography.caption.height, closeTo(1.3333, 0.001));
      expect(SrTypography.cardTitle.height, closeTo(1.5, 0.001));
      expect(SrTypography.statValue.height, closeTo(1.2, 0.001));
    });

    test('the hierarchy descends without ties', () {
      final List<double> sizes = <double>[
        SrTypography.pageTitle.fontSize!,
        SrTypography.screenTitle.fontSize!,
        SrTypography.sectionTitle.fontSize!,
        SrTypography.cardTitle.fontSize!,
        SrTypography.body.fontSize!,
        SrTypography.caption.fontSize!,
      ];
      for (int i = 1; i < sizes.length; i++) {
        expect(sizes[i], lessThan(sizes[i - 1]));
      }
    });

    test('the stat value uses tabular figures', () {
      expect(
        SrTypography.statValue.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    test('both themes resolve every Material text slot', () {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.light,
        AppTheme.dark,
      ]) {
        expect(theme.textTheme.bodyMedium?.color, isNotNull);
        expect(theme.textTheme.titleMedium?.color, isNotNull);
        expect(theme.textTheme.labelLarge?.color, isNotNull);
      }
    });
  });

  group('geometry tokens', () {
    test('only the three documented radii are used for real surfaces', () {
      expect(SrRadii.sm, 8);
      expect(SrRadii.control, 12);
      expect(SrRadii.surface, 16);
      // "Nothing in the product uses 4 or 24."
      for (final double radius in <double>[
        SrRadii.sm,
        SrRadii.control,
        SrRadii.surface,
      ]) {
        expect(radius, isNot(4));
        expect(radius, isNot(24));
      }
    });

    test('spacing follows the 4px scale', () {
      for (final double step in <double>[
        SrSpacing.xs,
        SrSpacing.sm,
        SrSpacing.md,
        SrSpacing.lg,
        SrSpacing.xl,
        SrSpacing.xxl,
        SrSpacing.xxxl,
        SrSpacing.huge,
      ]) {
        expect(step % 4, 0, reason: '$step is off the 4px scale');
      }
    });

    test('the documented widths and heights are exact', () {
      expect(SrSpacing.navWidth, 256);
      expect(SrSpacing.appBarHeight, 64);
      expect(SrSpacing.contentMaxWidth, 1152);
      expect(SrSpacing.compactMaxWidth, 448);
    });

    test('status rings derive from the palette rather than restating it', () {
      // The rings were hardcoded hex literals that duplicated palette steps —
      // two places to change, one of which would eventually be missed.
      expect(
        SrColorScheme.light.tone(SrTone.emerald).ring,
        SrPalette.emerald600.withValues(alpha: 0.2),
      );
      expect(
        SrColorScheme.light.tone(SrTone.red).ring,
        SrPalette.red600.withValues(alpha: 0.2),
      );
      expect(
        SrColorScheme.dark.tone(SrTone.amber).ring,
        SrPalette.amber400.withValues(alpha: 0.3),
      );
    });

    test('every tone ring is translucent, so the inset reads as a ring', () {
      for (final SrColorScheme scheme in <SrColorScheme>[
        SrColorScheme.light,
        SrColorScheme.dark,
      ]) {
        for (final SrTone tone in SrTone.values) {
          expect(scheme.tone(tone).ring.a, lessThan(1.0));
        }
      }
    });

    test('shadow-card is the documented two-stop recipe', () {
      final List<BoxShadow> card = SrColorScheme.light.cardShadow;
      expect(card, hasLength(2));
      expect(card.first.offset, const Offset(0, 1));
      expect(card.first.blurRadius, 2);
      expect(card.last.blurRadius, 3);
    });
  });
}
