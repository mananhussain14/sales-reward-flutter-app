import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/design.dart';

/// The single [ThemeData] for the application, assembled from [SrColors],
/// [SrTypography], [SrSpacing] and [SrRadii].
///
/// Nothing here invents a value. Every color, radius and size is a token, which
/// is what makes "does mobile still look like the web product?" a question about
/// one file rather than about every widget.
///
/// The product is LIGHT-ONLY for this milestone, mirroring
/// `html { color-scheme: light }` in the web application's `globals.css`. There
/// is deliberately no dark theme: shipping one would create a second visual
/// identity with no web counterpart to keep it honest.
abstract final class AppTheme {
  /// The seed-free color scheme. Material's `fromSeed` would derive tones that
  /// do not exist in the web palette, so the brand colors are stated exactly.
  static const ColorScheme _colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: SrColors.brand,
    onPrimary: SrColors.white,
    primaryContainer: SrColors.brandSoft,
    onPrimaryContainer: SrColors.indigo700,
    secondary: SrColors.slate900,
    onSecondary: SrColors.white,
    secondaryContainer: SrColors.slate100,
    onSecondaryContainer: SrColors.slate800,
    tertiary: SrColors.emerald600,
    onTertiary: SrColors.white,
    tertiaryContainer: SrColors.emerald50,
    onTertiaryContainer: SrColors.emerald700,
    error: SrColors.red600,
    onError: SrColors.white,
    errorContainer: SrColors.red50,
    onErrorContainer: SrColors.red700,
    surface: SrColors.surface,
    onSurface: SrColors.foreground,
    surfaceContainerLowest: SrColors.white,
    surfaceContainerLow: SrColors.appBackground,
    surfaceContainer: SrColors.appBackgroundSecondary,
    surfaceContainerHigh: SrColors.slate200,
    surfaceContainerHighest: SrColors.slate200,
    onSurfaceVariant: SrColors.textSecondary,
    outline: SrColors.borderStrong,
    outlineVariant: SrColors.border,
    inverseSurface: SrColors.slate900,
    onInverseSurface: SrColors.slate100,
    inversePrimary: SrColors.indigo300,
    shadow: SrColors.slate900,
    scrim: SrColors.slate900,
  );

  static ThemeData get light {
    final ThemeData base = ThemeData(
      useMaterial3: true,
      colorScheme: _colorScheme,
      textTheme: SrTypography.textTheme,
      fontFamily: SrTypography.fontFamily,
      scaffoldBackgroundColor: SrColors.appBackground,
      canvasColor: SrColors.appBackground,
    );

    return base.copyWith(
      // Mirrors `::selection` in globals.css.
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: SrColors.brand,
        selectionColor: SrColors.selectionBackground,
        selectionHandleColor: SrColors.brand,
      ),

      // The web has no app bar; mobile needs one, so it is styled as the page
      // surface with the title at the section-header step. It reads as part of
      // the page rather than as a separate Material band.
      appBarTheme: const AppBarTheme(
        backgroundColor: SrColors.appBackground,
        foregroundColor: SrColors.foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: SrTypography.sectionTitle,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),

      // `cardClasses("standard")`: rounded-2xl, white, slate-200 hairline.
      // The shadow is drawn by SrCard rather than by Material elevation, so
      // that the two-stop `--shadow-card` recipe survives intact.
      cardTheme: CardThemeData(
        color: SrColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.xl),
          side: const BorderSide(color: SrColors.border),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: SrColors.border,
        thickness: 1,
        space: 1,
      ),

      // `inputClasses()`: h-11, rounded-xl, slate-300 border, indigo focus.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SrColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SrSpacing.mdPlus,
          vertical: SrSpacing.md,
        ),
        hintStyle: SrTypography.body.copyWith(color: SrColors.slate400),
        labelStyle: SrTypography.label,
        helperStyle: SrTypography.caption,
        errorStyle: SrTypography.fieldError,
        border: _inputBorder(SrColors.borderStrong),
        enabledBorder: _inputBorder(SrColors.borderStrong),
        focusedBorder: _inputBorder(SrColors.indigo500, width: 2),
        errorBorder: _inputBorder(SrColors.red400),
        focusedErrorBorder: _inputBorder(SrColors.red600, width: 2),
        disabledBorder: _inputBorder(SrColors.border),
      ),

      // `VARIANTS.primary` in button.tsx.
      filledButtonTheme: FilledButtonThemeData(
        style: _buttonStyle(
          background: SrColors.brand,
          pressedBackground: SrColors.brandHover,
          foreground: SrColors.white,
        ),
      ),

      // `VARIANTS.outline`.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            _buttonStyle(
              background: SrColors.surface,
              pressedBackground: SrColors.slate50,
              foreground: SrColors.slate700,
            ).copyWith(
              side: const WidgetStatePropertyAll<BorderSide>(
                BorderSide(color: SrColors.borderStrong),
              ),
            ),
      ),

      // `VARIANTS.ghost`.
      textButtonTheme: TextButtonThemeData(
        style: _buttonStyle(
          background: Colors.transparent,
          pressedBackground: SrColors.slate100,
          foreground: SrColors.textSecondary,
        ),
      ),

      // Bottom navigation is the mobile translation of the web sidebar: the
      // active item takes the brand color over a `brand-soft` indicator, which
      // is how the web sidebar marks its active link.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SrColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: SrColors.brandSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.lg),
        ),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return SrTypography.caption.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? SrColors.brand : SrColors.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? SrColors.brand : SrColors.textMuted,
          );
        }),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: SrColors.surface,
        indicatorColor: SrColors.brandSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.lg),
        ),
        elevation: 0,
        selectedLabelTextStyle: SrTypography.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: SrColors.brand,
        ),
        unselectedLabelTextStyle: SrTypography.caption.copyWith(
          fontWeight: FontWeight.w500,
        ),
        selectedIconTheme: const IconThemeData(size: 22, color: SrColors.brand),
        unselectedIconTheme: const IconThemeData(
          size: 22,
          color: SrColors.textMuted,
        ),
      ),

      // The drawer is the mobile translation of the web's dark `--surface-nav`
      // sidebar, so it keeps that surface rather than turning white.
      drawerTheme: const DrawerThemeData(
        backgroundColor: SrColors.surfaceNav,
        surfaceTintColor: Colors.transparent,
        scrimColor: Color(0x800F172A),
        elevation: 0,
        width: 288,
      ),

      // Desktop dialogs become mobile dialogs and bottom sheets; both keep the
      // 16px card radius and the `--shadow-modal` weight.
      dialogTheme: DialogThemeData(
        backgroundColor: SrColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.xl),
        ),
        titleTextStyle: SrTypography.cardTitle,
        contentTextStyle: SrTypography.bodyMuted,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SrColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: SrColors.slate300,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(SrRadii.xl)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: SrColors.slate900,
        contentTextStyle: SrTypography.body.copyWith(color: SrColors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SrRadii.lg),
        ),
      ),

      // `Badge` in badge.tsx — a full-radius pill at the `text-xs` step.
      chipTheme: ChipThemeData(
        backgroundColor: SrColors.slate100,
        labelStyle: SrTypography.badge,
        side: BorderSide(color: SrColors.slate500.withValues(alpha: 0.2)),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: SrSpacing.smPlus,
          vertical: SrSpacing.xxs,
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SrColors.brand,
        linearTrackColor: SrColors.slate200,
        circularTrackColor: SrColors.slate200,
      ),

      listTileTheme: const ListTileThemeData(
        titleTextStyle: SrTypography.body,
        subtitleTextStyle: SrTypography.caption,
        iconColor: SrColors.textMuted,
      ),

      iconTheme: const IconThemeData(color: SrColors.textSecondary, size: 20),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(SrRadii.lg),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// The shared button geometry: `SIZES.md` (h-11 / px-4) with the `rounded-xl`
  /// radius and the `text-sm font-semibold` label from `button.tsx`.
  static ButtonStyle _buttonStyle({
    required Color background,
    required Color pressedBackground,
    required Color foreground,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return background.withValues(alpha: 0.6);
        }
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.hovered)) {
          return pressedBackground;
        }
        return background;
      }),
      foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return foreground.withValues(alpha: 0.6);
        }
        return foreground;
      }),
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
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(SrRadii.lg)),
      ),
      animationDuration: SrMotion.fast,
    );
  }
}
