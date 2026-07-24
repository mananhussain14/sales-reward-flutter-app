import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/repositories/portal_context_repository.dart';
import '../features/auth/presentation/bloc/role_session_bloc.dart';
import 'di/injector.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/cubit/theme_cubit.dart';

/// The application root.
///
/// Owns the three things that must exist before any route is built: the shared
/// [RoleSessionBloc], the [ThemeCubit], and the router whose guard reads the
/// session. All three are created here and disposed here, so a test can pump a
/// whole app without leaking any of them.
///
/// [portalContextRepository] and [initialThemeMode] exist for tests. A real
/// build resolves the repository from [getIt] — the only place the concrete
/// implementation is named — and starts on [ThemeMode.system].
class SaleRewardApp extends StatefulWidget {
  const SaleRewardApp({
    super.key,
    this.portalContextRepository,
    this.initialThemeMode = ThemeMode.system,
  });

  final PortalContextRepository? portalContextRepository;
  final ThemeMode initialThemeMode;

  @override
  State<SaleRewardApp> createState() => _SaleRewardAppState();
}

class _SaleRewardAppState extends State<SaleRewardApp> {
  late final RoleSessionBloc _roleSessionBloc;
  late final ThemeCubit _themeCubit;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    _roleSessionBloc = RoleSessionBloc(
      repository:
          widget.portalContextRepository ?? getIt<PortalContextRepository>(),
    )..add(const RoleSessionResolveRequested());

    _themeCubit = ThemeCubit(initialMode: widget.initialThemeMode);
    _router = buildAppRouter(roleSessionBloc: _roleSessionBloc);
  }

  @override
  void dispose() {
    _router.dispose();
    _themeCubit.close();
    _roleSessionBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<RoleSessionBloc>.value(value: _roleSessionBloc),
        BlocProvider<ThemeCubit>.value(value: _themeCubit),
      ],
      // Only the MaterialApp rebuilds when the mode changes — the router, the
      // session and every route stay put.
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
    );
  }
}
