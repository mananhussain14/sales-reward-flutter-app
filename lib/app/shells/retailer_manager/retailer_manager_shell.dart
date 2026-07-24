import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/auth/domain/entities/app_role.dart';
import '../base/role_shell_scaffold.dart';
import 'bloc/retailer_manager_shell_bloc.dart';

/// The Retailer Manager application shell.
///
/// A separate shell from the Retailer Owner's, not a narrowed copy of it. The
/// two roles share a design system and a chrome widget; they share no navigation
/// data and no BLoC.
class RetailerManagerShell extends StatelessWidget {
  const RetailerManagerShell({
    super.key,
    required this.child,
    required this.location,
    required this.resolved,
  });

  final Widget child;
  final String location;
  final ResolvedRole resolved;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RetailerManagerShellBloc>(
      create: (_) => RetailerManagerShellBloc(),
      child: RoleShellScaffold<RetailerManagerShellBloc>(
        location: location,
        resolved: resolved,
        child: child,
      ),
    );
  }
}
