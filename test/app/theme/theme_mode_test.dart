import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/app.dart';
import 'package:sale_reward/app/theme/cubit/theme_cubit.dart';
import 'package:sale_reward/core/design/design.dart';
import 'package:sale_reward/features/auth/data/repositories/unimplemented_portal_context_repository.dart';

import '../../support/pump_app.dart';

void main() {
  group('ThemeCubit', () {
    test('defaults to following the device', () {
      final ThemeCubit cubit = ThemeCubit();
      expect(cubit.state, ThemeMode.system);
      cubit.close();
    });

    blocTest<ThemeCubit, ThemeMode>(
      'moves between all three modes',
      build: ThemeCubit.new,
      act: (ThemeCubit c) => c
        ..useLight()
        ..useDark()
        ..useSystem(),
      expect: () => <ThemeMode>[
        ThemeMode.light,
        ThemeMode.dark,
        ThemeMode.system,
      ],
    );

    blocTest<ThemeCubit, ThemeMode>(
      'select() is equivalent to the named helpers',
      build: ThemeCubit.new,
      act: (ThemeCubit c) => c.select(ThemeMode.dark),
      expect: () => <ThemeMode>[ThemeMode.dark],
    );
  });

  group('MaterialApp wiring', () {
    MaterialApp appOf(WidgetTester tester) =>
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    testWidgets('provides theme, darkTheme and themeMode', (tester) async {
      await pumpApp(tester);

      final MaterialApp app = appOf(tester);
      expect(app.theme, isNotNull);
      expect(app.darkTheme, isNotNull);
      expect(app.themeMode, ThemeMode.system);
      expect(app.theme!.brightness, Brightness.light);
      expect(app.darkTheme!.brightness, Brightness.dark);
    });

    testWidgets('system mode follows a light device', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await pumpApp(tester);

      expect(_activeScheme(tester).isDark, isFalse);
    });

    testWidgets('system mode follows a dark device', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await pumpApp(tester);

      expect(_activeScheme(tester).isDark, isTrue);
    });

    testWidgets('an explicit light override ignores a dark device', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      useSurface(tester, phoneSurface);
      await tester.pumpWidget(
        const SaleRewardApp(
          portalContextRepository: UnimplementedPortalContextRepository(),
          initialThemeMode: ThemeMode.light,
        ),
      );
      await tester.pumpAndSettle();

      expect(appOf(tester).themeMode, ThemeMode.light);
      expect(_activeScheme(tester).isDark, isFalse);
    });

    testWidgets('an explicit dark override ignores a light device', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      useSurface(tester, phoneSurface);
      await tester.pumpWidget(
        const SaleRewardApp(
          portalContextRepository: UnimplementedPortalContextRepository(),
          initialThemeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(appOf(tester).themeMode, ThemeMode.dark);
      expect(_activeScheme(tester).isDark, isTrue);
    });

    testWidgets('the app renders without error in dark mode', (tester) async {
      useSurface(tester, phoneSurface);
      await tester.pumpWidget(
        const SaleRewardApp(
          portalContextRepository: UnimplementedPortalContextRepository(),
          initialThemeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Role resolution is not connected'), findsOneWidget);
    });
  });

  group('the theme selector', () {
    testWidgets('is reachable from the account sheet and changes the theme', (
      tester,
    ) async {
      await pumpAppInRole(tester, salesStaffRole);

      // The avatar in the app bar opens the account sheet.
      await tester.tap(find.bySemanticsLabel('Account'));
      await tester.pumpAndSettle();

      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not invent an identity it cannot know', (tester) async {
      await pumpAppInRole(tester, salesStaffRole);

      await tester.tap(find.bySemanticsLabel('Account'));
      await tester.pumpAndSettle();

      // Authentication is not implemented, so the sheet says so rather than
      // showing a placeholder name.
      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.textContaining('Sign-in is not built yet'), findsOneWidget);
    });
  });
}

/// The SalesReward colour layer currently in effect, read from a widget below
/// the MaterialApp so it reflects the resolved brightness.
SrColorScheme _activeScheme(WidgetTester tester) {
  final BuildContext context = tester.element(find.byType(Scaffold).first);
  return Theme.of(context).extension<SrColorScheme>()!;
}
