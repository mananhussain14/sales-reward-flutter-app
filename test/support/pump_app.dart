import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/app.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';

import 'fakes.dart';
import 'receipt_fakes.dart';
import 'vendor_retailer_fakes.dart';
import 'vendor_user_fakes.dart';

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

/// Everything a pumped application exposes back to a test.
typedef PumpedApp = ({
  FakeAuthRepository auth,
  FakePortalContextRepository portal,
  FakeReceiptRepository receipts,
  FakeReceiptImageSource images,
  FakeVendorRetailerRepository retailers,
  FakeVendorUserRepository vendorUsers,
});

/// Pumps the real application over supplied fakes, never Supabase.
///
/// Returns the fakes so a test can drive the auth stream and inspect calls.
/// [initialUser] seeds a restored session; leave it null for a cold start with
/// no session.
///
/// The receipt and Vendor Retailer fakes are always supplied, even for tests
/// that never open the shell that uses them — those shells build their cubits
/// from them, and a test that forgot to pass one would fall through to the
/// service locator, which is exactly the accident the injected graph exists to
/// prevent.
Future<PumpedApp> pumpApp(
  WidgetTester tester, {
  AuthUser? initialUser,
  PortalContextResult portalResult = deniedResult,
  Size surface = phoneSurface,
  ThemeMode themeMode = ThemeMode.system,
  bool settle = true,
  FakeReceiptRepository? receipts,
  FakeReceiptImageSource? images,
  FakeVendorRetailerRepository? retailers,
  FakeVendorUserRepository? vendorUsers,
}) async {
  final FakeAuthRepository auth = FakeAuthRepository(initialUser: initialUser);
  final FakePortalContextRepository portal = FakePortalContextRepository(
    portalResult,
  );
  final FakeReceiptRepository receiptRepository =
      receipts ?? FakeReceiptRepository();
  final FakeReceiptImageSource imageSource = images ?? FakeReceiptImageSource();
  final FakeVendorRetailerRepository retailerRepository =
      retailers ?? FakeVendorRetailerRepository();
  final FakeVendorUserRepository userRepository =
      vendorUsers ?? FakeVendorUserRepository();
  addTearDown(auth.dispose);

  useSurface(tester, surface);
  await tester.pumpWidget(
    SaleRewardApp(
      authRepository: auth,
      portalContextRepository: portal,
      receiptRepository: receiptRepository,
      receiptImageSource: imageSource,
      vendorRetailerRepository: retailerRepository,
      vendorUserRepository: userRepository,
      initialThemeMode: themeMode,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
  return (
    auth: auth,
    portal: portal,
    receipts: receiptRepository,
    images: imageSource,
    retailers: retailerRepository,
    vendorUsers: userRepository,
  );
}

/// Pumps the app already signed in and resolved into [kind]'s shell.
Future<PumpedApp> pumpAppInRole(
  WidgetTester tester,
  PortalKind kind, {
  Size surface = phoneSurface,
  FakeReceiptRepository? receipts,
  FakeReceiptImageSource? images,
  FakeVendorRetailerRepository? retailers,
  FakeVendorUserRepository? vendorUsers,
}) {
  return pumpApp(
    tester,
    initialUser: testUser,
    portalResult: resolvedResult(kind),
    surface: surface,
    receipts: receipts,
    images: images,
    retailers: retailers,
    vendorUsers: vendorUsers,
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
