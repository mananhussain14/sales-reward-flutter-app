import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/core/design/design.dart';

/// Theme construction.
///
/// These assertions are the guard against the mobile app quietly drifting away
/// from the web product's visual identity. Each one pins a value that is
/// documented in `app/globals.css` or in a `components/ui/*` class string in the
/// `salesreward-admin` repository — so changing the look becomes a deliberate
/// edit to a test, not an accident.
void main() {
  group('AppTheme.light', () {
    late ThemeData theme;

    setUp(() => theme = AppTheme.light);

    test('constructs without throwing and uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('is light-only, matching the web product', () {
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('uses the brand indigo as the primary, not a derived seed tone', () {
      // ColorScheme.fromSeed would produce a tone that appears nowhere on the
      // web. The palette is stated exactly instead.
      expect(theme.colorScheme.primary, SrColors.brand);
      expect(theme.colorScheme.primary, const Color(0xFF4F46E5));
      expect(theme.colorScheme.onPrimary, SrColors.white);
    });

    test('paints the page background with --app-background (slate-50)', () {
      expect(theme.scaffoldBackgroundColor, SrColors.appBackground);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
    });

    test('keeps the surface white and the hairline at slate-200', () {
      expect(theme.colorScheme.surface, SrColors.surface);
      expect(theme.colorScheme.outlineVariant, SrColors.border);
      expect(theme.colorScheme.outlineVariant, const Color(0xFFE2E8F0));
    });

    test('cards carry the rounded-2xl radius and a slate hairline', () {
      final RoundedRectangleBorder shape =
          theme.cardTheme.shape! as RoundedRectangleBorder;

      expect(shape.borderRadius, BorderRadius.circular(SrRadii.xl));
      expect(shape.side.color, SrColors.border);
      expect(
        theme.cardTheme.elevation,
        0,
        reason: 'the layered --shadow-card recipe is painted by SrCard',
      );
    });

    test('form controls take the rounded-xl radius and slate-300 border', () {
      final OutlineInputBorder border =
          theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;

      expect(border.borderRadius, BorderRadius.circular(SrRadii.lg));
      expect(border.borderSide.color, SrColors.borderStrong);
    });

    test('a focused form control turns indigo with a thicker edge', () {
      final OutlineInputBorder focused =
          theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;

      expect(focused.borderSide.color, SrColors.indigo500);
      expect(focused.borderSide.width, 2);
    });

    test('an errored form control turns red', () {
      final OutlineInputBorder errored =
          theme.inputDecorationTheme.errorBorder! as OutlineInputBorder;

      expect(errored.borderSide.color, SrColors.red400);
    });

    test('the drawer keeps the dark --surface-nav sidebar surface', () {
      expect(theme.drawerTheme.backgroundColor, SrColors.surfaceNav);
      expect(theme.drawerTheme.backgroundColor, const Color(0xFF0F172A));
    });

    test('navigation marks the active destination with brand-soft', () {
      expect(theme.navigationBarTheme.indicatorColor, SrColors.brandSoft);
      expect(theme.navigationRailTheme.indicatorColor, SrColors.brandSoft);
    });

    test('dialogs and bottom sheets keep the 16px card radius', () {
      final RoundedRectangleBorder dialog =
          theme.dialogTheme.shape! as RoundedRectangleBorder;
      final RoundedRectangleBorder sheet =
          theme.bottomSheetTheme.shape! as RoundedRectangleBorder;

      expect(dialog.borderRadius, BorderRadius.circular(SrRadii.xl));
      expect(
        sheet.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(SrRadii.xl)),
      );
    });

    test('text selection matches the ::selection rule', () {
      expect(
        theme.textSelectionTheme.selectionColor,
        SrColors.selectionBackground,
      );
      expect(theme.textSelectionTheme.cursorColor, SrColors.brand);
    });
  });

  group('typography', () {
    test('the page title mirrors text-2xl font-semibold tracking-tight', () {
      expect(SrTypography.pageTitle.fontSize, 24);
      expect(SrTypography.pageTitle.fontWeight, FontWeight.w600);
      expect(SrTypography.pageTitle.letterSpacing, lessThan(0));
    });

    test('the body step is text-sm, the product default', () {
      expect(SrTypography.body.fontSize, 14);
      expect(SrTypography.body.height, 20 / 14);
    });

    test('the eyebrow is the brand color with positive tracking', () {
      expect(SrTypography.eyebrow.color, SrColors.brand);
      expect(SrTypography.eyebrow.fontSize, 12);
      expect(SrTypography.eyebrow.letterSpacing, greaterThan(0));
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
        expect(
          sizes[i],
          lessThan(sizes[i - 1]),
          reason: 'step $i must be smaller than step ${i - 1}',
        );
      }
    });

    test('every Material text slot resolves to a documented style', () {
      const TextTheme textTheme = SrTypography.textTheme;

      expect(textTheme.bodyMedium, SrTypography.body);
      expect(textTheme.titleMedium, SrTypography.cardTitle);
      expect(textTheme.labelLarge, SrTypography.button);
    });
  });

  group('design tokens', () {
    test('shadows are slate-tinted rather than black', () {
      for (final BoxShadow shadow in SrShadows.card) {
        expect(
          shadow.color.r,
          SrColors.slate900.r,
          reason: '--shadow-card is built from slate-900, not black',
        );
      }
    });

    test('--shadow-card is the documented two-stop recipe', () {
      expect(SrShadows.card, hasLength(2));
      expect(SrShadows.card.first.offset, const Offset(0, 1));
      expect(SrShadows.card.first.blurRadius, 2);
      expect(SrShadows.card.last.blurRadius, 3);
    });

    test('radii follow the Tailwind rounded-* steps the web uses', () {
      expect(SrRadii.md, 8); // rounded-lg
      expect(SrRadii.lg, 12); // rounded-xl — buttons, inputs
      expect(SrRadii.xl, 16); // rounded-2xl — cards
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
      ]) {
        expect(step % 4, 0, reason: '$step is off the 4px scale');
      }
    });

    test('every status tone has a distinct background and foreground', () {
      for (final SrTone tone in SrTone.values) {
        expect(tone.background, isNot(tone.foreground));
      }
    });
  });
}
