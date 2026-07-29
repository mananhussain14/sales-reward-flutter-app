import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/audit/domain/repositories/vendor_audit_log_repository.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/auth/domain/repositories/portal_context_repository.dart';
import '../features/auth/presentation/bloc/session_bloc.dart';
import '../features/dashboard/domain/repositories/retailer_owner_overview_repository.dart';
import '../features/products/domain/repositories/retailer_product_repository.dart';
import '../features/dashboard/domain/repositories/vendor_dashboard_repository.dart';
import '../features/products/domain/repositories/vendor_product_repository.dart';
import '../features/profile/domain/repositories/vendor_profile_repository.dart';
import '../features/receipts/domain/repositories/receipt_repository.dart';
import '../features/receipts/domain/services/receipt_image_source.dart';
import '../features/retailers/domain/repositories/vendor_retailer_lifecycle_repository.dart';
import '../features/retailers/domain/repositories/vendor_retailer_repository.dart';
import '../features/roles/domain/repositories/vendor_role_repository.dart';
import '../features/shops/domain/repositories/retailer_shop_repository.dart';
import '../features/staff/domain/repositories/retailer_staff_invitation_repository.dart';
import '../features/staff/domain/repositories/retailer_staff_repository.dart';
import '../features/staff/domain/repositories/retailer_staff_shop_assignment_repository.dart';
import '../features/users/domain/repositories/vendor_user_repository.dart';
import 'di/injector.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/cubit/theme_cubit.dart';

/// The application root.
///
/// Owns everything that must exist before any route is built: the shared
/// [AuthRepository] (exposed to the tree so screens and sheets can reach
/// sign-in and sign-out), the [SessionBloc] that coordinates authentication and
/// portal resolution, the [ThemeCubit], and the router whose guard reads the
/// session. All are created here and disposed here, so a test can pump a whole
/// app without leaking any of them.
///
/// Every repository argument overrides the injected graph. A real build resolves
/// each from [getIt]; a test supplies fakes and never touches Supabase.
///
/// The receipt and Vendor Retailer dependencies are provided here rather than
/// resolved inside their shells for the same reason [AuthRepository] is: a
/// widget test must be able to stand the whole app up over fakes, and a shell
/// that reached into [getIt] itself would make that impossible without a global
/// registration.
class SaleRewardApp extends StatefulWidget {
  const SaleRewardApp({
    super.key,
    this.authRepository,
    this.portalContextRepository,
    this.receiptRepository,
    this.receiptImageSource,
    this.vendorRetailerRepository,
    this.vendorRetailerLifecycleRepository,
    this.vendorUserRepository,
    this.vendorRoleRepository,
    this.vendorProductRepository,
    this.vendorAuditLogRepository,
    this.vendorDashboardRepository,
    this.vendorProfileRepository,
    this.retailerOwnerOverviewRepository,
    this.retailerShopRepository,
    this.retailerStaffRepository,
    this.retailerStaffInvitationRepository,
    this.retailerStaffShopAssignmentRepository,
    this.retailerProductRepository,
    this.initialThemeMode = ThemeMode.system,
  });

  final AuthRepository? authRepository;
  final PortalContextRepository? portalContextRepository;
  final ReceiptRepository? receiptRepository;
  final ReceiptImageSource? receiptImageSource;
  final VendorRetailerRepository? vendorRetailerRepository;
  final VendorRetailerLifecycleRepository? vendorRetailerLifecycleRepository;
  final VendorUserRepository? vendorUserRepository;
  final VendorRoleRepository? vendorRoleRepository;
  final VendorProductRepository? vendorProductRepository;
  final VendorAuditLogRepository? vendorAuditLogRepository;
  final VendorDashboardRepository? vendorDashboardRepository;
  final VendorProfileRepository? vendorProfileRepository;
  final RetailerOwnerOverviewRepository? retailerOwnerOverviewRepository;
  final RetailerShopRepository? retailerShopRepository;
  final RetailerStaffRepository? retailerStaffRepository;
  final RetailerStaffInvitationRepository? retailerStaffInvitationRepository;
  final RetailerStaffShopAssignmentRepository?
  retailerStaffShopAssignmentRepository;
  final RetailerProductRepository? retailerProductRepository;
  final ThemeMode initialThemeMode;

  @override
  State<SaleRewardApp> createState() => _SaleRewardAppState();
}

class _SaleRewardAppState extends State<SaleRewardApp> {
  late final AuthRepository _authRepository;
  late final ReceiptRepository _receiptRepository;
  late final ReceiptImageSource _receiptImageSource;
  late final VendorRetailerRepository _vendorRetailerRepository;
  late final VendorRetailerLifecycleRepository
  _vendorRetailerLifecycleRepository;
  late final VendorUserRepository _vendorUserRepository;
  late final VendorRoleRepository _vendorRoleRepository;
  late final VendorProductRepository _vendorProductRepository;
  late final VendorAuditLogRepository _vendorAuditLogRepository;
  late final VendorDashboardRepository _vendorDashboardRepository;
  late final VendorProfileRepository _vendorProfileRepository;
  late final RetailerOwnerOverviewRepository _retailerOwnerOverviewRepository;
  late final RetailerShopRepository _retailerShopRepository;
  late final RetailerStaffRepository _retailerStaffRepository;
  late final RetailerStaffInvitationRepository
  _retailerStaffInvitationRepository;
  late final RetailerStaffShopAssignmentRepository
  _retailerStaffShopAssignmentRepository;
  late final RetailerProductRepository _retailerProductRepository;
  late final SessionBloc _sessionBloc;
  late final ThemeCubit _themeCubit;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    _authRepository = widget.authRepository ?? getIt<AuthRepository>();
    _receiptRepository = widget.receiptRepository ?? getIt<ReceiptRepository>();
    _receiptImageSource =
        widget.receiptImageSource ?? getIt<ReceiptImageSource>();
    _vendorRetailerRepository =
        widget.vendorRetailerRepository ?? getIt<VendorRetailerRepository>();
    _vendorRetailerLifecycleRepository =
        widget.vendorRetailerLifecycleRepository ??
        getIt<VendorRetailerLifecycleRepository>();
    _vendorUserRepository =
        widget.vendorUserRepository ?? getIt<VendorUserRepository>();
    _vendorRoleRepository =
        widget.vendorRoleRepository ?? getIt<VendorRoleRepository>();
    _vendorProductRepository =
        widget.vendorProductRepository ?? getIt<VendorProductRepository>();
    _vendorAuditLogRepository =
        widget.vendorAuditLogRepository ?? getIt<VendorAuditLogRepository>();
    _vendorDashboardRepository =
        widget.vendorDashboardRepository ?? getIt<VendorDashboardRepository>();
    _vendorProfileRepository =
        widget.vendorProfileRepository ?? getIt<VendorProfileRepository>();
    _retailerOwnerOverviewRepository =
        widget.retailerOwnerOverviewRepository ??
        getIt<RetailerOwnerOverviewRepository>();
    _retailerShopRepository =
        widget.retailerShopRepository ?? getIt<RetailerShopRepository>();
    _retailerStaffRepository =
        widget.retailerStaffRepository ?? getIt<RetailerStaffRepository>();
    _retailerStaffInvitationRepository =
        widget.retailerStaffInvitationRepository ??
        getIt<RetailerStaffInvitationRepository>();
    _retailerStaffShopAssignmentRepository =
        widget.retailerStaffShopAssignmentRepository ??
        getIt<RetailerStaffShopAssignmentRepository>();
    _retailerProductRepository =
        widget.retailerProductRepository ?? getIt<RetailerProductRepository>();

    _sessionBloc = SessionBloc(
      authRepository: _authRepository,
      portalContextRepository:
          widget.portalContextRepository ?? getIt<PortalContextRepository>(),
    )..add(const SessionStarted());

    _themeCubit = ThemeCubit(initialMode: widget.initialThemeMode);
    _router = buildAppRouter(sessionBloc: _sessionBloc);
  }

  @override
  void dispose() {
    _router.dispose();
    _themeCubit.close();
    _sessionBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: <RepositoryProvider<dynamic>>[
        // Provided as a value so login, the account sheet and the access-denied
        // screen can build their own short-lived cubits over it without
        // threading it through constructors.
        RepositoryProvider<AuthRepository>.value(value: _authRepository),
        // Read by the Sales Staff shell when it constructs its receipt cubits.
        // Providing them here — rather than letting the shell reach into the
        // service locator — is what lets a widget test drive the whole flow over
        // fakes with no Supabase client and no platform channel.
        RepositoryProvider<ReceiptRepository>.value(value: _receiptRepository),
        RepositoryProvider<ReceiptImageSource>.value(
          value: _receiptImageSource,
        ),
        // Read by the Vendor shell when it constructs its Retailer cubits, for
        // the same reason: a widget test drives the whole directory and detail
        // flow over a fake with no Supabase client.
        RepositoryProvider<VendorRetailerRepository>.value(
          value: _vendorRetailerRepository,
        ),
        // The Retailer lifecycle write and its capability probe, kept behind
        // their own interface for the same reason the staff invitation and
        // shop-assignment contracts are kept apart from the staff read: the
        // read repository's documentation guarantees it holds no write, and its
        // boundary test asserts it.
        RepositoryProvider<VendorRetailerLifecycleRepository>.value(
          value: _vendorRetailerLifecycleRepository,
        ),
        RepositoryProvider<VendorUserRepository>.value(
          value: _vendorUserRepository,
        ),
        RepositoryProvider<VendorRoleRepository>.value(
          value: _vendorRoleRepository,
        ),
        RepositoryProvider<VendorProductRepository>.value(
          value: _vendorProductRepository,
        ),
        RepositoryProvider<VendorAuditLogRepository>.value(
          value: _vendorAuditLogRepository,
        ),
        RepositoryProvider<VendorDashboardRepository>.value(
          value: _vendorDashboardRepository,
        ),
        RepositoryProvider<VendorProfileRepository>.value(
          value: _vendorProfileRepository,
        ),
        // Read by the Retailer Owner shell when it constructs its overview
        // cubit, for the same reason as every repository above: a widget test
        // drives the whole Overview flow over a fake with no Supabase client.
        RepositoryProvider<RetailerOwnerOverviewRepository>.value(
          value: _retailerOwnerOverviewRepository,
        ),
        // The three Retailer read-portal repositories, provided here for the
        // same reason as every repository above: the two Retailer shells build
        // their cubits from them, and a widget test drives the whole Shops,
        // Staff and Products flow over fakes with no Supabase client.
        RepositoryProvider<RetailerShopRepository>.value(
          value: _retailerShopRepository,
        ),
        RepositoryProvider<RetailerStaffRepository>.value(
          value: _retailerStaffRepository,
        ),
        // The staff *invitation* contracts, kept separate from the read above
        // for the same reason their repositories are: that one's documentation
        // guarantees it holds no write, and both of its methods are nullary
        // reads of STABLE functions. Only the Retailer Owner shell reads this
        // one.
        RepositoryProvider<RetailerStaffInvitationRepository>.value(
          value: _retailerStaffInvitationRepository,
        ),
        // The post-acceptance shop-assignment write, kept separate again: the
        // invitation repository is about invitations, and this operation changes
        // an already accepted membership on a different permission with no
        // email, token or expiry anywhere near it. Only the Retailer Owner shell
        // reads this one.
        RepositoryProvider<RetailerStaffShopAssignmentRepository>.value(
          value: _retailerStaffShopAssignmentRepository,
        ),
        RepositoryProvider<RetailerProductRepository>.value(
          value: _retailerProductRepository,
        ),
      ],
      child: MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<SessionBloc>.value(value: _sessionBloc),
          BlocProvider<ThemeCubit>.value(value: _themeCubit),
        ],
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (BuildContext context, ThemeMode themeMode) {
            return MaterialApp.router(
              title: 'SalesReward',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: themeMode,
              routerConfig: _router,
            );
          },
        ),
      ),
    );
  }
}
