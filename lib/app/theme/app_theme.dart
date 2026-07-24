import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/design.dart';

/// The application's two themes, both assembled from one [SrColorScheme].
///
/// ## One builder, two schemes
///
/// [light] and [dark] call the same private builder with a different
/// [SrColorScheme]. Nothing about the *structure* of the theme — radii,
/// typography, component shapes, motion — differs between them, which is what
/// makes the dark theme a counterpart rather than a second design. Only colour
/// resolves differently, and it resolves in exactly one place.
///
/// ## A documented deviation
///
/// § 0 and the § 7 checklist of `docs/mobile-ui-design-handoff.md` instruct the
/// Flutter client to ship **light only** and to pin `ThemeMode.light`, on the
/// grounds that the web has no dark palette to copy and any dark theme would
/// therefore be invented.
///
/// The mobile product requirement is the opposite: light, dark and system.
/// Both themes ship here, and the deviation is deliberate and recorded in
/// `docs/flutter-application-foundation.md`. The handoff's underlying concern —
/// that an invented dark theme becomes a second visual identity — is answered
/// by construction: every dark value is another step of the *same* Tailwind v4
/// family as its light counterpart, no new hue is introduced, and the contrast
/// of every text pair is audited. See [SrColorScheme.dark].
abstract final class AppTheme {
  static ThemeData get light => _build(SrColorScheme.light);

  static ThemeData get dark => _build(SrColorScheme.dark);

  /// Resolves the [SrColorScheme] for a [Brightness], for callers that need the
  /// tokens without a [BuildContext].
  static SrColorScheme schemeFor(Brightness brightness) =>
      brightness == Brightness.dark ? SrColorScheme.dark : SrColorScheme.light;

  static ThemeData _build(SrColorScheme sr) {
    final ColorScheme colorScheme = _materialScheme(sr);

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: sr.brightness,
      colorScheme: colorScheme,
      fontFamily: SrTypography.fontFamily,
      scaffoldBackgroundColor: sr.background,
      canvasColor: sr.background,
      textTheme: SrTypography.textTheme(
        foreground: sr.foreground,
        secondary: sr.textSecondary,
      ),
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[sr],

      // Mirrors the `::selection` rule in globals.css.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: sr.brand,
        selectionColor: sr.selectionBackground,
        selectionHandleColor: sr.brand,
      ),

      // § 3.19: sticky, 64 tall, surface at 85% behind a blur, 1px bottom
      // hairline, elevation 0. The blur itself is applied by the shell, since
      // AppBarTheme cannot carry a BackdropFilter.
      appBarTheme: AppBarTheme(
        backgroundColor: sr.surfaceAppBar,
        foregroundColor: sr.foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: SrSpacing.appBarHeight,
        centerTitle: false,
        titleTextStyle: SrTypography.cardTitle.copyWith(color: sr.foreground),
        iconTheme: IconThemeData(color: sr.textBody, size: 20),
        shape: Border(bottom: BorderSide(color: sr.border)),
        systemOverlayStyle: sr.isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
              ),
      ),

      // § 3.5: 16-radius, 1px hairline, surface fill. The two-stop slate-tinted
      // shadow is painted by SrCard, because Material elevation would replace
      // the layered recipe with a single tinted blur.
      cardTheme: CardThemeData(
        color: sr.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.surface),
          side: BorderSide(color: sr.border),
        ),
      ),

      dividerTheme: DividerThemeData(color: sr.border, thickness: 1, space: 1),

      // § 3.2: h-11, 12-radius, strong border, brand focus.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sr.inputFill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SrSpacing.mdPlus,
          vertical: SrSpacing.md,
        ),
        hintStyle: SrTypography.body.copyWith(color: sr.textMuted),
        labelStyle: SrTypography.label.copyWith(color: sr.textLabel),
        helperStyle: SrTypography.caption.copyWith(color: sr.textSecondary),
        errorStyle: SrTypography.fieldError.copyWith(color: sr.fieldError),
        border: _inputBorder(sr.inputBorder),
        enabledBorder: _inputBorder(sr.inputBorder),
        focusedBorder: _inputBorder(sr.inputFocusBorder, width: 2),
        errorBorder: _inputBorder(sr.inputErrorBorder),
        focusedErrorBorder: _inputBorder(sr.inputErrorFocusBorder, width: 2),
        disabledBorder: _inputBorder(sr.border),
      ),

      // § 3.1. SrButton owns the full variant system; these keep any stock
      // Material button on-brand rather than on Material defaults.
      filledButtonTheme: FilledButtonThemeData(
        style: _buttonStyle(
          background: sr.brand,
          pressed: sr.brandHover,
          foreground: sr.onBrand,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            _buttonStyle(
              background: sr.outlineFill,
              pressed: sr.outlineHover,
              foreground: sr.onOutline,
            ).copyWith(
              side: WidgetStatePropertyAll<BorderSide>(
                BorderSide(color: sr.borderStrong),
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _buttonStyle(
          background: Colors.transparent,
          pressed: sr.ghostHover,
          foreground: sr.onGhost,
        ),
      ),

      // § 4.1: bottom bar — surface fill, hairline top border (drawn by the
      // shell), 20px icons, 12px/500 labels, and a selected indicator that is a
      // *shape* as well as a colour.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: sr.surfaceNav,
        surfaceTintColor: Colors.transparent,
        indicatorColor: sr.navActiveFill,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.control),
        ),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return SrTypography.caption.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? sr.navActiveLabel : sr.navLabel,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 20,
            color: selected ? sr.navActiveLabel : sr.navLabel,
          );
        }),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: sr.surfaceNav,
        indicatorColor: sr.navActiveFill,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.control),
        ),
        elevation: 0,
        selectedLabelTextStyle: SrTypography.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: sr.navActiveLabel,
        ),
        unselectedLabelTextStyle: SrTypography.caption.copyWith(
          fontWeight: FontWeight.w500,
          color: sr.navLabel,
        ),
        selectedIconTheme: IconThemeData(size: 20, color: sr.navActiveLabel),
        unselectedIconTheme: IconThemeData(size: 20, color: sr.navLabel),
      ),

      // § 3.19: the drawer is the mobile form of the sidebar — 256 wide, on the
      // same surface the sidebar uses, with a slate scrim. It is NOT dark: the
      // `--surface-nav` custom property is declared but never applied on the
      // web, and the handoff says not to build a dark drawer from it.
      drawerTheme: DrawerThemeData(
        backgroundColor: sr.surfaceNav,
        surfaceTintColor: Colors.transparent,
        scrimColor: sr.scrim,
        elevation: 0,
        width: SrSpacing.navWidth,
        shape: const RoundedRectangleBorder(),
      ),

      // § 3.7: the web has no dialog component, so this is the one place mobile
      // must invent — kept to the card radius and the modal shadow weight.
      dialogTheme: DialogThemeData(
        backgroundColor: sr.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.surface),
        ),
        titleTextStyle: SrTypography.cardTitle.copyWith(color: sr.foreground),
        contentTextStyle: SrTypography.body.copyWith(color: sr.textSecondary),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sr.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: sr.scrim,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: sr.borderStrong,
        dragHandleSize: const Size(32, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SrRadii.surface),
          ),
        ),
      ),

      // § 3.8: the product has no snackbars — feedback is inline. This exists
      // only so a transient background result cannot fall back to Material's
      // default dark pill.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: sr.surface,
        contentTextStyle: SrTypography.body.copyWith(color: sr.foreground),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.control),
          side: BorderSide(color: sr.border),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: sr.slate.fill,
        labelStyle: SrTypography.badge.copyWith(color: sr.slate.foreground),
        side: BorderSide(color: sr.slate.ring),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: SrSpacing.smPlus,
          vertical: SrSpacing.xxs,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: sr.brand,
        linearTrackColor: sr.border,
        circularTrackColor: sr.border,
        linearMinHeight: 2,
      ),

      listTileTheme: ListTileThemeData(
        titleTextStyle: SrTypography.body.copyWith(color: sr.foreground),
        subtitleTextStyle: SrTypography.caption.copyWith(
          color: sr.textSecondary,
        ),
        iconColor: sr.textSecondary,
      ),

      iconTheme: IconThemeData(color: sr.textBody, size: 20),

      splashFactory: NoSplash.splashFactory,
    );
  }

  /// The Material [ColorScheme], derived from the SalesReward tokens.
  ///
  /// Stated exactly rather than seeded: `ColorScheme.fromSeed` would generate
  /// tones that appear nowhere in the web product.
  static ColorScheme _materialScheme(SrColorScheme sr) {
    return ColorScheme(
      brightness: sr.brightness,
      primary: sr.brand,
      onPrimary: sr.onBrand,
      primaryContainer: sr.brandSoft,
      onPrimaryContainer: sr.onBrandSoft,
      secondary: sr.secondaryFill,
      onSecondary: sr.onSecondary,
      secondaryContainer: sr.backgroundSecondary,
      onSecondaryContainer: sr.foreground,
      tertiary: sr.emerald.foreground,
      onTertiary: sr.onBrand,
      tertiaryContainer: sr.emerald.fill,
      onTertiaryContainer: sr.emerald.alertText,
      error: sr.dangerFill,
      onError: sr.onBrand,
      errorContainer: sr.red.fill,
      onErrorContainer: sr.red.alertText,
      surface: sr.surface,
      onSurface: sr.foreground,
      surfaceContainerLowest: sr.surface,
      surfaceContainerLow: sr.background,
      surfaceContainer: sr.backgroundSecondary,
      surfaceContainerHigh: sr.surfaceMuted,
      surfaceContainerHighest: sr.surfaceMuted,
      onSurfaceVariant: sr.textSecondary,
      outline: sr.borderStrong,
      outlineVariant: sr.border,
      inverseSurface: sr.foreground,
      onInverseSurface: sr.background,
      inversePrimary: sr.brandSoft,
      shadow: sr.isDark ? SrPalette.black : SrPalette.slate900,
      scrim: sr.scrim,
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(SrRadii.control),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// The shared button geometry: `md` (h-11 / px-4), 12-radius, 14/600 label.
  static ButtonStyle _buttonStyle({
    required Color background,
    required Color pressed,
    required Color foreground,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.hovered)) {
          return pressed;
        }
        return background;
      }),
      foregroundColor: WidgetStatePropertyAll<Color>(foreground),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      elevation: const WidgetStatePropertyAll<double>(0),
      shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      textStyle: const WidgetStatePropertyAll<TextStyle>(SrTypography.button),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 44)),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: SrSpacing.lg),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.control),
        ),
      ),
      animationDuration: SrMotion.fast,
    );
  }
}
