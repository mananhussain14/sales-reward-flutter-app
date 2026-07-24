import '../../base/role_shell_bloc.dart';
import '../retailer_manager_navigation.dart';

/// The Retailer Manager shell's navigation state.
///
/// Bound to [RetailerManagerNavigation.model] at construction.
final class RetailerManagerShellBloc extends RoleShellBloc {
  RetailerManagerShellBloc() : super(RetailerManagerNavigation.model);
}
