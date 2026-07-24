import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/auth/domain/repositories/portal_context_repository.dart';
import '../features/auth/presentation/bloc/session_bloc.dart';
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
/// [authRepository] and [portalContextRepository] override the injected graph.
/// A real build resolves both from [getIt]; a test supplies fakes and never
/// touches Supabase.
class SaleRewardApp extends StatefulWidget {
  const SaleRewardApp({
    super.key,
    this.authRepository,
    this.portalContextRepository,
    this.initialThemeMode = ThemeMode.system,
  });

  final AuthRepository? authRepository;
  final PortalContextRepository? portalContextRepository;
  final ThemeMode initialThemeMode;

  @override
  State<SaleRewardApp> createState() => _SaleRewardAppState();
}

class _SaleRewardAppState extends State<SaleRewardApp> {
  late final AuthRepository _authRepository;
  late final SessionBloc _sessionBloc;
  late final ThemeCubit _themeCubit;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    _authRepository = widget.authRepository ?? getIt<AuthRepository>();

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
