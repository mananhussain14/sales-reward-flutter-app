import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/repositories/portal_context_repository.dart';
import '../features/auth/presentation/bloc/role_session_bloc.dart';
import 'di/injector.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// The application root.
///
/// Owns the two things that must exist before any route is built: the shared
/// [RoleSessionBloc], and the router whose guard reads it. Both are created here
/// and disposed here, so a test can pump a whole app without leaking either.
///
/// [portalContextRepository] overrides the injected repository. It exists for
/// tests — a real build resolves the repository from [getIt], which is the only
/// place the concrete implementation is named.
class SaleRewardApp extends StatefulWidget {
  const SaleRewardApp({super.key, this.portalContextRepository});

  final PortalContextRepository? portalContextRepository;

  @override
  State<SaleRewardApp> createState() => _SaleRewardAppState();
}

class _SaleRewardAppState extends State<SaleRewardApp> {
  late final RoleSessionBloc _roleSessionBloc;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    _roleSessionBloc = RoleSessionBloc(
      repository:
          widget.portalContextRepository ?? getIt<PortalContextRepository>(),
    )..add(const RoleSessionResolveRequested());

    _router = buildAppRouter(roleSessionBloc: _roleSessionBloc);
  }

  @override
  void dispose() {
    _router.dispose();
    _roleSessionBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RoleSessionBloc>.value(
      value: _roleSessionBloc,
      child: MaterialApp.router(
        title: 'SalesReward',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
