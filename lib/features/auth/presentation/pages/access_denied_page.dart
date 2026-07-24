import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/widgets/widgets.dart';
import '../bloc/role_session_bloc.dart';

/// The route that renders the shared, role-neutral access-denied screen.
///
/// Reached in two ways, and it must look identical for both — otherwise the
/// difference itself becomes information:
///
/// * The backend answered `kind = 'none'`: a verified identity that qualifies
///   for no supported experience.
/// * The route guard caught an attempt to enter a role group the current role
///   does not own.
///
/// The sign-out control currently clears the local role and returns to the gate.
/// Authentication is not implemented in this milestone, so there is no session
/// to end; when `supabase.auth.signOut(scope: 'local')` is wired in, it belongs
/// here — along with purging the secure-storage session, any cached portal
/// context, and any queued receipts, per § 7.3 of the architecture
/// recommendation.
class AccessDeniedPage extends StatelessWidget {
  const AccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SrAccessDeniedView(
      onSignOut: () {
        // Drop the role in effect, then ask again from scratch. Re-resolving
        // rather than leaving the session empty is what § 4.3 of the
        // architecture recommendation requires — the role is never cached, it
        // is re-derived.
        context.read<RoleSessionBloc>()
          ..add(const RoleSessionCleared())
          ..add(const RoleSessionResolveRequested());
        context.go(AppRoutes.roleGate);
      },
    );
  }
}
