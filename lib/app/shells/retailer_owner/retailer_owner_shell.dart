import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/auth/domain/entities/portal_context.dart';
import '../base/role_shell_scaffold.dart';
import 'bloc/retailer_owner_shell_bloc.dart';

/// The Retailer Owner application shell.
///
/// Five destinations, so it uses bottom navigation — promoted to a rail on a
/// tablet or on Flutter web. Owns its own [RetailerOwnerShellBloc].
class RetailerOwnerShell extends StatelessWidget {
  const RetailerOwnerShell({
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
    return BlocProvider<RetailerOwnerShellBloc>(
      create: (_) => RetailerOwnerShellBloc(),
      child: RoleShellScaffold<RetailerOwnerShellBloc>(
        location: location,
        portalContext: portalContext,
        child: child,
      ),
    );
  }
}
