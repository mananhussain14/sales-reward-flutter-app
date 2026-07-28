import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/app.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/features/audit/domain/repositories/vendor_audit_log_repository.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/dashboard/domain/repositories/retailer_owner_overview_repository.dart';
import 'package:sale_reward/features/products/domain/repositories/retailer_product_repository.dart';
import 'package:sale_reward/features/dashboard/domain/repositories/vendor_dashboard_repository.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_repository.dart';
import 'package:sale_reward/features/profile/domain/repositories/vendor_profile_repository.dart';
import 'package:sale_reward/features/roles/domain/repositories/vendor_role_repository.dart';
import 'package:sale_reward/features/shops/domain/repositories/retailer_shop_repository.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_invitation_repository.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_repository.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_shop_assignment_repository.dart';
import 'package:sale_reward/features/users/domain/repositories/vendor_user_repository.dart';

import 'fakes.dart';
import 'receipt_fakes.dart';
import 'retailer_owner_overview_fakes.dart';
import 'retailer_invite_staff_fakes.dart';
import 'retailer_manage_staff_shops_fakes.dart';
import 'retailer_read_fakes.dart';
import 'vendor_audit_log_fakes.dart';
import 'vendor_dashboard_fakes.dart';
import 'vendor_product_fakes.dart';
import 'vendor_profile_fakes.dart';
import 'vendor_retailer_fakes.dart';
import 'vendor_role_fakes.dart';
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
  FakeVendorRoleRepository vendorRoles,
  FakeVendorProductRepository vendorProducts,
  FakeVendorAuditLogRepository vendorAuditLogs,
  FakeVendorDashboardRepository vendorDashboard,
  FakeVendorProfileRepository vendorProfile,
  FakeRetailerOwnerOverviewRepository retailerOverview,
  FakeRetailerShopRepository retailerShops,
  FakeRetailerStaffRepository retailerStaff,
  FakeRetailerStaffInvitationRepository retailerStaffInvitations,
  FakeRetailerStaffShopAssignmentRepository retailerStaffShopAssignments,
  FakeRetailerProductRepository retailerProducts,
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
  VendorUserRepository? vendorUserRepository,
  FakeVendorRoleRepository? vendorRoles,
  VendorRoleRepository? vendorRoleRepository,
  FakeVendorProductRepository? vendorProducts,
  VendorProductRepository? vendorProductRepository,
  FakeVendorAuditLogRepository? vendorAuditLogs,
  VendorAuditLogRepository? vendorAuditLogRepository,
  FakeVendorDashboardRepository? vendorDashboard,
  VendorDashboardRepository? vendorDashboardRepository,
  FakeVendorProfileRepository? vendorProfile,
  VendorProfileRepository? vendorProfileRepository,
  FakeRetailerOwnerOverviewRepository? retailerOverview,
  RetailerOwnerOverviewRepository? retailerOverviewRepository,
  FakeRetailerShopRepository? retailerShops,
  RetailerShopRepository? retailerShopRepository,
  FakeRetailerStaffRepository? retailerStaff,
  RetailerStaffRepository? retailerStaffRepository,
  FakeRetailerStaffInvitationRepository? retailerStaffInvitations,
  RetailerStaffInvitationRepository? retailerStaffInvitationRepository,
  FakeRetailerStaffShopAssignmentRepository? retailerStaffShopAssignments,
  RetailerStaffShopAssignmentRepository? retailerStaffShopAssignmentRepository,
  FakeRetailerProductRepository? retailerProducts,
  RetailerProductRepository? retailerProductRepository,
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
  // A test that needs the *real* repository — to exercise its id-shape guard
  // over a counting data source, say — supplies it here and takes precedence.
  // The fake is still returned so the record shape stays uniform.
  final VendorUserRepository providedUsers =
      vendorUserRepository ?? userRepository;
  final FakeVendorRoleRepository roleRepository =
      vendorRoles ?? FakeVendorRoleRepository();
  final VendorRoleRepository providedRoles =
      vendorRoleRepository ?? roleRepository;
  final FakeVendorProductRepository productRepository =
      vendorProducts ?? FakeVendorProductRepository();
  final VendorProductRepository providedProducts =
      vendorProductRepository ?? productRepository;
  final FakeVendorAuditLogRepository auditLogRepository =
      vendorAuditLogs ?? FakeVendorAuditLogRepository();
  final VendorAuditLogRepository providedAuditLogs =
      vendorAuditLogRepository ?? auditLogRepository;
  final FakeVendorDashboardRepository dashboardRepository =
      vendorDashboard ?? FakeVendorDashboardRepository();
  final VendorDashboardRepository providedDashboard =
      vendorDashboardRepository ?? dashboardRepository;
  final FakeVendorProfileRepository profileRepository =
      vendorProfile ?? FakeVendorProfileRepository();
  final VendorProfileRepository providedProfile =
      vendorProfileRepository ?? profileRepository;
  final FakeRetailerOwnerOverviewRepository overviewRepository =
      retailerOverview ?? FakeRetailerOwnerOverviewRepository();
  final RetailerOwnerOverviewRepository providedOverview =
      retailerOverviewRepository ?? overviewRepository;
  final FakeRetailerShopRepository shopRepository =
      retailerShops ?? FakeRetailerShopRepository();
  final RetailerShopRepository providedShops =
      retailerShopRepository ?? shopRepository;
  final FakeRetailerStaffRepository staffRepository =
      retailerStaff ?? FakeRetailerStaffRepository();
  final RetailerStaffRepository providedStaff =
      retailerStaffRepository ?? staffRepository;
  final FakeRetailerStaffInvitationRepository invitationRepository =
      retailerStaffInvitations ?? FakeRetailerStaffInvitationRepository();
  final RetailerStaffInvitationRepository providedInvitations =
      retailerStaffInvitationRepository ?? invitationRepository;
  final FakeRetailerStaffShopAssignmentRepository shopAssignmentRepository =
      retailerStaffShopAssignments ??
      FakeRetailerStaffShopAssignmentRepository();
  final RetailerStaffShopAssignmentRepository providedShopAssignments =
      retailerStaffShopAssignmentRepository ?? shopAssignmentRepository;
  final FakeRetailerProductRepository productsRepository =
      retailerProducts ?? FakeRetailerProductRepository();
  final RetailerProductRepository providedRetailerProducts =
      retailerProductRepository ?? productsRepository;
  addTearDown(auth.dispose);

  useSurface(tester, surface);
  await tester.pumpWidget(
    SaleRewardApp(
      authRepository: auth,
      portalContextRepository: portal,
      receiptRepository: receiptRepository,
      receiptImageSource: imageSource,
      vendorRetailerRepository: retailerRepository,
      vendorUserRepository: providedUsers,
      vendorRoleRepository: providedRoles,
      vendorProductRepository: providedProducts,
      vendorAuditLogRepository: providedAuditLogs,
      vendorDashboardRepository: providedDashboard,
      vendorProfileRepository: providedProfile,
      retailerOwnerOverviewRepository: providedOverview,
      retailerShopRepository: providedShops,
      retailerStaffRepository: providedStaff,
      retailerStaffInvitationRepository: providedInvitations,
      retailerStaffShopAssignmentRepository: providedShopAssignments,
      retailerProductRepository: providedRetailerProducts,
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
    vendorRoles: roleRepository,
    vendorProducts: productRepository,
    vendorAuditLogs: auditLogRepository,
    vendorDashboard: dashboardRepository,
    vendorProfile: profileRepository,
    retailerOverview: overviewRepository,
    retailerShops: shopRepository,
    retailerStaff: staffRepository,
    retailerStaffInvitations: invitationRepository,
    retailerStaffShopAssignments: shopAssignmentRepository,
    retailerProducts: productsRepository,
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
  VendorUserRepository? vendorUserRepository,
  FakeVendorRoleRepository? vendorRoles,
  VendorRoleRepository? vendorRoleRepository,
  FakeVendorProductRepository? vendorProducts,
  VendorProductRepository? vendorProductRepository,
  FakeVendorAuditLogRepository? vendorAuditLogs,
  VendorAuditLogRepository? vendorAuditLogRepository,
  FakeVendorDashboardRepository? vendorDashboard,
  VendorDashboardRepository? vendorDashboardRepository,
  FakeVendorProfileRepository? vendorProfile,
  VendorProfileRepository? vendorProfileRepository,
  FakeRetailerOwnerOverviewRepository? retailerOverview,
  RetailerOwnerOverviewRepository? retailerOverviewRepository,
  FakeRetailerShopRepository? retailerShops,
  RetailerShopRepository? retailerShopRepository,
  FakeRetailerStaffRepository? retailerStaff,
  RetailerStaffRepository? retailerStaffRepository,
  FakeRetailerStaffInvitationRepository? retailerStaffInvitations,
  RetailerStaffInvitationRepository? retailerStaffInvitationRepository,
  FakeRetailerStaffShopAssignmentRepository? retailerStaffShopAssignments,
  RetailerStaffShopAssignmentRepository? retailerStaffShopAssignmentRepository,
  FakeRetailerProductRepository? retailerProducts,
  RetailerProductRepository? retailerProductRepository,
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
    vendorUserRepository: vendorUserRepository,
    vendorRoles: vendorRoles,
    vendorRoleRepository: vendorRoleRepository,
    vendorProducts: vendorProducts,
    vendorProductRepository: vendorProductRepository,
    vendorAuditLogs: vendorAuditLogs,
    vendorAuditLogRepository: vendorAuditLogRepository,
    vendorDashboard: vendorDashboard,
    vendorDashboardRepository: vendorDashboardRepository,
    vendorProfile: vendorProfile,
    vendorProfileRepository: vendorProfileRepository,
    retailerOverview: retailerOverview,
    retailerOverviewRepository: retailerOverviewRepository,
    retailerShops: retailerShops,
    retailerShopRepository: retailerShopRepository,
    retailerStaff: retailerStaff,
    retailerStaffRepository: retailerStaffRepository,
    retailerStaffInvitations: retailerStaffInvitations,
    retailerStaffInvitationRepository: retailerStaffInvitationRepository,
    retailerStaffShopAssignments: retailerStaffShopAssignments,
    retailerStaffShopAssignmentRepository:
        retailerStaffShopAssignmentRepository,
    retailerProducts: retailerProducts,
    retailerProductRepository: retailerProductRepository,
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
