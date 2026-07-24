import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/app.dart';
import 'package:sale_reward/app/di/injector.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/features/auth/domain/entities/app_role.dart';

/// A convenience alias, so a test that only needs *some* role does not have to
/// pick one arbitrarily at each call site.
const AppRole salesStaffRole = AppRole.salesStaff;

/// A phone-sized surface, so shells that adapt on width render their
/// narrow-screen chrome (bottom navigation, modal drawer).
const Size phoneSurface = Size(390, 844);

/// A tablet-sized surface, for asserting the rail promotion.
const Size tabletSurface = Size(900, 1000);

/// A desktop-sized surface, for asserting the permanent side panel.
const Size desktopSurface = Size(1280, 900);

/// Sets the test surface and restores it afterwards.
void useSurface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the real application and settles it on the role gate.
///
/// Uses the real dependency graph, so this also exercises the startup wiring
/// [configureDependencies] performs.
Future<void> pumpApp(WidgetTester tester, {Size surface = phoneSurface}) async {
  await configureDependencies();
  addTearDown(resetDependencies);

  useSurface(tester, surface);
  await tester.pumpWidget(const SaleRewardApp());
  await tester.pumpAndSettle();
}

/// Pumps the app and enters [role]'s shell through the gate's preview control.
///
/// Deliberately goes through the real UI rather than seeding BLoC state: the
/// preview path is the only way into a shell in this build, and a test that
/// bypassed it would stop noticing if that path broke.
Future<void> pumpAppInRole(
  WidgetTester tester,
  AppRole role, {
  Size surface = phoneSurface,
}) async {
  await pumpApp(tester, surface: surface);

  final Finder control = find.widgetWithText(TextButton, role.displayName);

  // The gate scrolls on a phone; the later roles sit below the fold.
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();

  await tester.tap(control);
  await tester.pumpAndSettle();
}

/// Pumps a single design-system widget inside a real app theme.
///
/// [brightness] selects which theme, so every widget can be asserted in both.
///
/// Deliberately **pumps a single frame rather than settling**: the button
/// spinner and the skeleton shimmer both animate indefinitely by design, so
/// `pumpAndSettle` would time out on them. One frame is enough to build and lay
/// out, which is all a finder needs.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  Size surface = phoneSurface,
}) async {
  useSurface(tester, surface);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

/// Runs [body] once per theme, so a widget test covers light and dark without
/// being written twice.
void forEachBrightness(void Function(Brightness brightness) body) {
  for (final Brightness brightness in Brightness.values) {
    body(brightness);
  }
}
