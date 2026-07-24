import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/auth/domain/entities/app_role.dart';
import '../base/role_shell_scaffold.dart';
import 'bloc/vendor_shell_bloc.dart';

/// The Vendor Super Admin application shell.
///
/// Owns its own [VendorShellBloc] and its own navigation model. It shares chrome
/// with the other three shells through [RoleShellScaffold], and shares nothing
/// else with them — no destinations, no BLoC instance, no conditional branches.
///
/// This role uses a drawer rather than a bottom bar because its web counterpart
/// carries six active modules; see `VendorNavigation` for the reasoning.
class VendorShell extends StatelessWidget {
  const VendorShell({
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
    return BlocProvider<VendorShellBloc>(
      create: (_) => VendorShellBloc(),
      child: RoleShellScaffold<VendorShellBloc>(
        location: location,
        resolved: resolved,
        child: child,
      ),
    );
  }
}
