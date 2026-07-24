import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/app.dart';
import 'package:sale_reward/app/di/injector.dart';
import 'package:sale_reward/features/auth/domain/entities/app_role.dart';

/// A phone-sized surface, so shells that adapt on width render their
/// narrow-screen chrome (bottom navigation, modal drawer) in tests.
const Size phoneSurface = Size(390, 844);

/// A tablet-sized surface, for asserting the rail promotion.
const Size tabletSurface = Size(900, 1000);

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
/// that [configureDependencies] performs.
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
