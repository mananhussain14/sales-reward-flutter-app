import '../../base/role_shell_bloc.dart';
import '../vendor_navigation.dart';

/// The Vendor Super Admin shell's navigation state.
///
/// Bound to [VendorNavigation.model] at construction, so it cannot address any
/// other role's destinations even by accident.
final class VendorShellBloc extends RoleShellBloc {
  VendorShellBloc() : super(VendorNavigation.model);
}
