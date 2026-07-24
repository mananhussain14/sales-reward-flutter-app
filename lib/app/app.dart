import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/auth/domain/repositories/portal_context_repository.dart';
import '../features/auth/presentation/bloc/session_bloc.dart';
import '../features/receipts/domain/repositories/receipt_repository.dart';
import '../features/receipts/domain/services/receipt_image_source.dart';
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
/// The receipt dependencies are provided here rather than resolved inside the
/// Sales Staff shell for the same reason [AuthRepository] is: a widget test must
/// be able to stand the whole app up over fakes, and a shell that reached into
/// [getIt] itself would make that impossible without a global registration.
class SaleRewardApp extends StatefulWidget {
  const SaleRewardApp({
    super.key,
    this.authRepository,
    this.portalContextRepository,
    this.receiptRepository,
    this.receiptImageSource,
    this.initialThemeMode = ThemeMode.system,
  });

  final AuthRepository? authRepository;
  final PortalContextRepository? portalContextRepository;
  final ReceiptRepository? receiptRepository;
  final ReceiptImageSource? receiptImageSource;
  final ThemeMode initialThemeMode;

  @override
  State<SaleRewardApp> createState() => _SaleRewardAppState();
}

class _SaleRewardAppState extends State<SaleRewardApp> {
  late final AuthRepository _authRepository;
  late final ReceiptRepository _receiptRepository;
  late final ReceiptImageSource _receiptImageSource;
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
