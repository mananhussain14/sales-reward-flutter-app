import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/widgets.dart';
import '../../domain/repositories/auth_repository.dart';
import '../cubit/logout_cubit.dart';

/// The route that renders the shared, role-neutral access-denied screen.
///
/// Reached two ways, and it must look identical for both — otherwise the
/// difference itself is information a hostile account could read:
///
/// * the backend answered `portal_kind: NONE` — a verified identity that
///   qualifies for no supported experience;
/// * the route guard caught an attempt to enter a role group the caller's
///   resolved role does not own.
///
/// Sign-out is the only affordance, matching § 3.17. It runs the real sign-out;
/// the resulting auth change flows through [SessionBloc], which clears the
/// context, and the router replaces this screen with the login page. This widget
/// does not route itself — routing from here would be a second opinion about
/// where a signed-out user belongs.
class AccessDeniedPage extends StatelessWidget {
  const AccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LogoutCubit>(
      create: (BuildContext context) =>
          LogoutCubit(authRepository: context.read<AuthRepository>()),
      child: const _AccessDeniedView(),
    );
  }
}

class _AccessDeniedView extends StatelessWidget {
  const _AccessDeniedView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LogoutCubit, LogoutStatus>(
      builder: (BuildContext context, LogoutStatus status) {
        return SrAccessDeniedView(
          signingOut: status == LogoutStatus.inProgress,
          signOutFailed: status == LogoutStatus.failed,
          onSignOut: status == LogoutStatus.inProgress
              ? null
              : () => context.read<LogoutCubit>().signOut(),
        );
      },
    );
  }
}
