import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/auth/domain/entities/portal_context.dart';
import '../base/role_shell_scaffold.dart';
import 'bloc/sales_staff_shell_bloc.dart';

/// The Sales Staff application shell.
///
/// The narrowest shell in the product and the first milestone's target: three
/// destinations, bottom navigation, and nothing borrowed from any other role.
class SalesStaffShell extends StatelessWidget {
  const SalesStaffShell({
    super.key,
    required this.child,
    required this.location,
    required this.portalContext,
  });

  final Widget child;
  final String location;
  final PortalContext portalContext;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SalesStaffShellBloc>(
      create: (_) => SalesStaffShellBloc(),
      child: RoleShellScaffold<SalesStaffShellBloc>(
        location: location,
        portalContext: portalContext,
        child: child,
      ),
    );
  }
}
