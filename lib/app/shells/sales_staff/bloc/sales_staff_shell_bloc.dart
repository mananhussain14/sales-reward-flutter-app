import '../../base/role_shell_bloc.dart';
import '../sales_staff_navigation.dart';

/// The Sales Staff shell's navigation state.
///
/// Bound to [SalesStaffNavigation.model] at construction. This is the shell most
/// likely to grow role-specific behaviour first — an offline-queue badge on
/// Submit, once the queue exists — and having its own type means that arrives
/// here rather than as a condition inside a shared BLoC.
final class SalesStaffShellBloc extends RoleShellBloc {
  SalesStaffShellBloc() : super(SalesStaffNavigation.model);
}
