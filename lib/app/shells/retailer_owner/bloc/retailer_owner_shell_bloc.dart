import '../../base/role_shell_bloc.dart';
import '../retailer_owner_navigation.dart';

/// The Retailer Owner shell's navigation state.
///
/// Bound to [RetailerOwnerNavigation.model] at construction. Distinct from
/// [RetailerManagerShellBloc] by type, even though the two roles share two
/// destinations — so an Owner-only entry added later cannot reach a Manager's
/// shell through a shared object.
final class RetailerOwnerShellBloc extends RoleShellBloc {
  RetailerOwnerShellBloc() : super(RetailerOwnerNavigation.model);
}
