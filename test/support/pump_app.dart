import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/app.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';

import 'fakes.dart';

/// A phone-sized surface, so shells that adapt on width render their
/// narrow-screen chrome (bottom navigation, modal drawer).
const Size phoneSurface = Size(390, 844);

/// A small-but-common phone, to catch overflow the taller default hides.
const Size smallPhoneSurface = Size(360, 640);

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

/// Pumps the real application over supplied fakes, never Supabase.
///
/// Returns the fakes so a test can drive the auth stream and inspect calls.
/// [initialUser] seeds a restored session; leave it null for a cold start with
/// no session.
Future<({FakeAuthRepository auth, FakePortalContextRepository portal})> pumpApp(
  WidgetTester tester, {
  AuthUser? initialUser,
  PortalContextResult portalResult = deniedResult,
  Size surface = phoneSurface,
  ThemeMode themeMode = ThemeMode.system,
  bool settle = true,
}) async {
  final FakeAuthRepository auth = FakeAuthRepository(initialUser: initialUser);
  final FakePortalContextRepository portal = FakePortalContextRepository(
    portalResult,
  );
  addTearDown(auth.dispose);

  useSurface(tester, surface);
  await tester.pumpWidget(
    SaleRewardApp(
      authRepository: auth,
      portalContextRepository: portal,
      initialThemeMode: themeMode,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
  return (auth: auth, portal: portal);
}

/// Pumps the app already signed in and resolved into [kind]'s shell.
Future<({FakeAuthRepository auth, FakePortalContextRepository portal})>
pumpAppInRole(
  WidgetTester tester,
  PortalKind kind, {
  Size surface = phoneSurface,
}) {
  return pumpApp(
    tester,
    initialUser: testUser,
    portalResult: resolvedResult(kind),
    surface: surface,
  );
}

/// Pumps a single design-system widget inside a real app theme.
///
/// Pumps one frame rather than settling: the button spinner and the skeleton
/// shimmer animate indefinitely by design, so `pumpAndSettle` would time out.
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
